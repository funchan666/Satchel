import Foundation
import OSLog
import StoreKit
import UIKit
import WebKit

private final class PortalSocketDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

@MainActor private final class PortalReceiptRefresh: NSObject, SKRequestDelegate {
    private var request: SKReceiptRefreshRequest?
    private var continuation: CheckedContinuation<Bool, Never>?

    func refresh() async -> Bool {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            let request = SKReceiptRefreshRequest()
            self.request = request
            request.delegate = self
            request.start()
        }
    }
    func requestDidFinish(_ request: SKRequest) { finish(true) }
    func request(_ request: SKRequest, didFailWithError error: Error) { finish(false) }
    private func finish(_ success: Bool) {
        let continuation = self.continuation
        self.continuation = nil
        request = nil
        continuation?.resume(returning: success)
    }
}

private func portalPayPlan(_ params: [String: Any]) -> String? {
    if params.isEmpty { return "monthly" }
    return params["plan"] as? String
}

private struct PortalOperation: Codable {
    let userID: String
    let requestID: String
    let action: String
    let plan: String?
    var productID: String? = nil
    var status: String
    var failureReason: String? = nil
    var completed: Bool? = nil
    var accountToken: UUID? = nil
    var orderID: String? = nil
    var transactionID: String? = nil
    var needsSend: Bool? = nil
    // The H5 ACK does not identify which status it received. Preserve ambiguity across restarts.
    var acknowledgedStatusCandidate: String? = nil
    var acknowledgmentAmbiguous: Bool? = nil
}

@MainActor final class PortalSocket {
    private let paymentLog = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Satchel", category: "PortalPayment")
    private let backend: PortalBackend
    private let ads: RewardedAds
    private weak var webView: WKWebView?
    private let userID: String
    private var token: String
    private var credentialsObserverID: UUID?
    private let delegate = PortalSocketDelegate()
    private var session: URLSession?
    private var socket: URLSessionWebSocketTask?
    private var loop: Task<Void, Never>?
    private var updates: Task<Void, Never>?
    private var recovery: Task<Void, Never>?
    private var operations: [PortalOperation] = []
    private var ledgerAvailable = false
    private var processing: Set<String> = []
    private var processingTransactions: Set<UInt64> = []
    private var paymentActive = false
    private var activeAccountToken: UUID?
    private var purchaseStage: PurchaseActivity?
    private var verifyingRequests: Set<String> = []
    private var stopped = false
    private let ledgerURL: URL

    init?(backend: PortalBackend, ads: RewardedAds, webView: WKWebView) {
        guard let credentials = backend.socketCredentials,
              let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        self.backend = backend; self.ads = ads; self.webView = webView
        self.userID = credentials.userID; self.token = credentials.token
        self.ledgerURL = root.appendingPathComponent("Satchel", isDirectory: true).appendingPathComponent("portal-operations.json")
        do {
            if FileManager.default.fileExists(atPath: ledgerURL.path) {
                operations = try JSONDecoder().decode([PortalOperation].self, from: Data(contentsOf: ledgerURL))
            }
            ledgerAvailable = true
        } catch { ledgerAvailable = false }
    }

    func start() {
        guard loop == nil else { return }
        stopped = false
        credentialsObserverID = backend.observeCredentials { [weak self] user, access in
            guard let self, !self.stopped, user == self.userID else { return }
            self.token = access
            self.socket?.cancel(with: .goingAway, reason: nil)
            self.socket = nil
        }
        session = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)
        loop = Task { [weak self] in
            guard let self else { return }
            await self.connectLoop()
        }
        updates = Task { [weak self] in
            for await result in Transaction.updates {
                guard let self, !Task.isCancelled else { return }
                await self.handleTransaction(result)
            }
        }
        Task { [weak self] in await self?.recoverUnfinished() }
        recovery = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(nanoseconds: 30_000_000_000) } catch { return }
                guard let self, !self.stopped else { return }
                await self.recoverUnfinished()
            }
        }
    }

    func stop() {
        stopped = true
        backend.purchaseActivity = nil
        if let credentialsObserverID { backend.removeCredentialsObserver(credentialsObserverID); self.credentialsObserverID = nil }
        loop?.cancel(); loop = nil; updates?.cancel(); updates = nil; recovery?.cancel(); recovery = nil
        socket?.cancel(with: .goingAway, reason: nil); socket = nil
        session?.invalidateAndCancel(); session = nil
    }

    private func connectLoop() async {
        var delay: UInt64 = 1
        var refreshedAfterUnauthorized = false
        while !Task.isCancelled {
            guard let credentials = backend.socketCredentials, credentials.userID == userID, credentials.token == token,
                  var components = URLComponents(string: "wss://\(PortalConfiguration.socketHost)/admin-api/ws/version") else { return }
            let attemptedToken = token
            components.queryItems = [URLQueryItem(name: "userId", value: userID), URLQueryItem(name: "clientType", value: "app"), URLQueryItem(name: "accessToken", value: attemptedToken)]
            guard let address = components.url, let session else { return }
            let connection = session.webSocketTask(with: address)
            connection.maximumMessageSize = 65_536
            socket = connection; connection.resume()
            Task { [weak self] in await self?.recoverUnfinished() }
            for record in operations where record.userID == userID && record.needsSend == true && !(record.status == "pending" && processing.contains(record.requestID)) {
                await send(record: record)
            }
            do {
                while !Task.isCancelled {
                    let message = try await connection.receive()
                    delay = 1
                    refreshedAfterUnauthorized = false
                    let data: Data
                    switch message {
                    case .data(let value): data = value
                    case .string(let value): data = Data(value.utf8)
                    @unknown default: continue
                    }
                    receive(data)
                }
            } catch {
                let failure = error as NSError
                paymentLog.error("WebSocket receive failed; domain=\(failure.domain, privacy: .public), code=\(failure.code)")
                if (connection.response as? HTTPURLResponse)?.statusCode == 401 {
                    guard !refreshedAfterUnauthorized else { return }
                    refreshedAfterUnauthorized = true
                    do { try await backend.renewCredentialsAfterUnauthorized(attemptedToken) }
                    catch { return }
                }
            }
            connection.cancel(with: .goingAway, reason: nil)
            if socket === connection { socket = nil }
            guard !Task.isCancelled else { return }
            do { try await Task.sleep(nanoseconds: delay * 1_000_000_000) } catch { return }
            delay = min(delay * 2, 30)
        }
    }

    private func receive(_ bytes: Data) {
        guard !stopped, bytes.count <= 65_536,
              let envelope = (try? JSONSerialization.jsonObject(with: bytes)) as? [String: Any],
              let outerType = envelope["type"] as? String,
              var data = envelope["data"] as? [String: Any] else { return }
        guard matchesUser(envelope["userId"]) else {
            if ["PAYMENT", "PAYMENT_REQUEST"].contains(outerType) {
                paymentLog.error("Payment socket message ignored: user does not match App session")
            }
            return
        }
        if outerType == "ACK" {
            acknowledge(data)
            return
        }
        guard ["PAYMENT", "PAYMENT_REQUEST", "AD_REQUEST", "REQUEST"].contains(outerType) else { return }
        if data["type"] as? String == "ACK", matchesUser(data["userId"]),
           let acknowledgment = data["data"] as? [String: Any] {
            acknowledge(acknowledgment)
            return
        }
        if let nestedType = data["type"] as? String, ["AD_REQUEST", "REQUEST", "PAYMENT", "PAYMENT_REQUEST"].contains(nestedType),
           let nested = data["data"] as? [String: Any] {
            guard matchesUser(data["userId"]) else { return }
            data = nested
        }
        guard let requestID = data["requestId"] as? String, (1...128).contains(requestID.count),
              let action = data["action"] as? String, let version = data["version"] as? Int, version == 1,
              let params = data["params"] as? [String: Any],
              (data["platform"] as? String) != "app" else {
            if ["PAYMENT", "PAYMENT_REQUEST"].contains(outerType) {
                paymentLog.error("Payment socket message ignored: unsupported or incomplete payload")
            }
            return
        }
        let plan: String?
        if action == "subscription.purchase" {
            switch params["planId"] as? String {
            case PortalConfiguration.monthlyProductID: plan = "monthly"
            case PortalConfiguration.yearlyProductID: plan = "yearly"
            default: plan = nil
            }
        } else if action == "pay" { plan = portalPayPlan(params) }
        else { plan = params["plan"] as? String }
        guard ["pay", "ad.rewarded", "ad.interstitial", "subscription.getStatus", "subscription.getProducts", "subscription.purchase", "subscription.restore"].contains(action) else { return }
        if ["pay", "subscription.purchase"].contains(action) {
            let logID = UUID(uuidString: requestID)?.uuidString ?? "non_uuid"
            paymentLog.info("Payment request accepted; requestId=\(logID, privacy: .public), action=\(action, privacy: .public)")
        }
        if action == "subscription.getStatus" {
            Task { [weak self] in
                guard let self else { return }
                do { let value = try await self.backend.userStatus(); await self.send(requestID: requestID, action: action, status: "available", data: value) }
                catch { await self.send(requestID: requestID, action: action, status: "failed", error: "user_query_failed") }
            }
            return
        }
        if action == "subscription.getProducts" {
            Task { [weak self] in
                guard let self else { return }
                do {
                    let ids = [PortalConfiguration.monthlyProductID, PortalConfiguration.yearlyProductID]
                    guard Set(ids).count == 2 else {
                        await self.send(requestID: requestID, action: action, status: "failed", error: "invalid_product_configuration")
                        return
                    }
                    let products = try await Product.products(for: ids)
                    let valid = products.filter { ids.contains($0.id) }
                    guard !valid.isEmpty else {
                        await self.send(requestID: requestID, action: action, status: "failed", error: "products_not_found")
                        return
                    }
                    let entries: [[String: Any]] = valid.map { product in
                        ["planId": product.id, "productId": product.id,
                         "rightsName": product.id, "title": product.displayName, "description": product.description,
                         "price": product.displayPrice, "rawPrice": NSDecimalNumber(decimal: product.price),
                         "currencyCode": NSNull(), "available": true]
                    }
                    await self.send(requestID: requestID, action: action, status: "available", data: ["platform": "ios", "products": entries])
                } catch { await self.send(requestID: requestID, action: action, status: "failed", error: "product_query_failed") }
            }
            return
        }
        if action == "subscription.restore" {
            Task { [weak self] in
                guard let self else { return }
                await self.recoverUnfinished()
                do {
                    let status = try await self.backend.userStatus()
                    if self.providerEntitlementIsActive(status) {
                        for await result in Transaction.currentEntitlements {
                            guard !self.stopped else { return }
                            guard case .verified(let transaction) = result, transaction.revocationDate == nil,
                                  let accountToken = transaction.appAccountToken,
                                  let record = self.operations.first(where: {
                                      $0.userID == self.userID && ["pay", "subscription.purchase"].contains($0.action) && $0.status == "purchased" &&
                                      $0.accountToken == accountToken &&
                                      transaction.productID == self.productID(for: $0)
                                  }) else { continue }
                            await self.send(requestID: requestID, action: action, status: "purchased", data: ["planId": self.productID(for: record) ?? "", "transactionId": String(transaction.id), "verified": true])
                            return
                        }
                    }
                    await self.send(requestID: requestID, action: action, status: "pending", data: status, error: "restore_pending_reconciliation")
                } catch { await self.send(requestID: requestID, action: action, status: "pending", error: "restore_pending_reconciliation") }
            }
            return
        }
        if let record = operations.first(where: { $0.userID == userID && $0.requestID == requestID }) {
            guard record.action == action, record.plan == plan else { return }
            if record.status == "pending", processing.contains(requestID) { return }
            Task { await send(record: record) }
            return
        }
        guard ledgerAvailable, !processing.contains(requestID) else {
            Task { await send(requestID: requestID, action: action, status: "failed", error: "storage_unavailable") }
            return
        }
        if ["pay", "subscription.purchase"].contains(action), plan != "monthly" && plan != "yearly" {
            Task { await send(requestID: requestID, action: action, status: "failed", error: "invalid_plan") }
            return
        }
        var record = PortalOperation(userID: userID, requestID: requestID, action: action, plan: plan, status: "pending")
        if let plan, ["pay", "subscription.purchase"].contains(action) { record.productID = PortalConfiguration.productID(for: plan) }
        record.acknowledgmentAmbiguous = false
        operations.append(record)
        guard persist() else {
            operations.removeLast(); ledgerAvailable = false
            Task { await send(requestID: requestID, action: action, status: "failed", error: "storage_unavailable") }
            return
        }
        processing.insert(requestID)
        Task { [weak self] in
            guard let self else { return }
            defer { self.processing.remove(requestID) }
            if ["pay", "subscription.purchase"].contains(action) {
                await self.purchase(requestID: requestID, plan: plan!)
            }
            else {
                let result = action == "ad.rewarded"
                    ? await self.ads.show(from: self.presentingController(), unitID: self.backend.adUnitID(for: 5))
                    : "ad_not_configured"
                guard !self.stopped else { return }
                let status = ["rewarded", "dismissed"].contains(result) ? result : "failed"
                self.updateOperation(requestID, status: status, completed: action == "ad.rewarded" ? result == "rewarded" : nil,
                                     failureReason: status == "failed" ? result : nil)
                if let updated = self.operation(requestID) { await self.send(record: updated) }
            }
        }
    }

    private func operation(_ id: String) -> PortalOperation? { operations.first { $0.userID == userID && $0.requestID == id } }
    private func productID(for record: PortalOperation) -> String? {
        if let productID = record.productID { return productID }
        // Records from earlier versions were always made with the original demo IDs.
        switch record.plan {
        case "monthly": return "test.plan.month"
        case "yearly": return "test.plan.year"
        default: return nil
        }
    }
    private func acknowledge(_ data: [String: Any]) {
        guard data["platform"] as? String == "h5", data["status"] as? String == "received",
              data["version"] as? Int == 1, let requestID = data["requestId"] as? String,
              let action = data["action"] as? String,
              let index = operations.firstIndex(where: { $0.userID == userID && $0.requestID == requestID && $0.action == action }),
              operations[index].needsSend == true else { return }
        paymentLog.info("H5 result ACK received; action=\(action, privacy: .public), currentStatus=\(self.operations[index].status, privacy: .public)")
        if let received = data["receivedStatus"] as? String {
            guard operations[index].status == received else { return }
        } else {
            // A delayed ACK for an earlier status must not acknowledge a newer result.
            guard operations[index].acknowledgmentAmbiguous == false,
                  operations[index].acknowledgedStatusCandidate == operations[index].status else { return }
        }
        operations[index].needsSend = false
        if !persist() { ledgerAvailable = false }
    }
    private func recoverUnfinished() async {
        for await result in Transaction.unfinished {
            guard !stopped, !Task.isCancelled else { return }
            await handleTransaction(result)
        }
    }
    private func providerEntitlementIsActive(_ value: Any) -> Bool {
        guard let fields = value as? [String: Any], let raw = fields["rightExpireTime"] else { return false }
        let seconds: Double?
        if let number = raw as? NSNumber { seconds = number.doubleValue }
        else if let text = raw as? String, let number = Double(text) { seconds = number }
        else if let text = raw as? String { return ISO8601DateFormatter().date(from: text).map { $0 > Date() } ?? false }
        else { return false }
        guard let seconds, seconds.isFinite, seconds > 0 else { return false }
        return Date(timeIntervalSince1970: seconds > 100_000_000_000 ? seconds / 1000 : seconds) > Date()
    }
    private func matchesUser(_ value: Any?) -> Bool {
        if let value = value as? String { return value == userID }
        if let value = value as? NSNumber { return value.stringValue == userID }
        return false
    }
    @discardableResult private func persist() -> Bool {
        do {
            try FileManager.default.createDirectory(at: ledgerURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(operations).write(to: ledgerURL, options: .atomic)
            return true
        } catch { return false }
    }
    private func updateOperation(_ id: String, status: String, completed: Bool? = nil, failureReason: String? = nil) {
        guard let index = operations.firstIndex(where: { $0.userID == userID && $0.requestID == id }) else { return }
        operations[index].status = status; operations[index].completed = completed; operations[index].needsSend = true
        operations[index].failureReason = failureReason
        if !persist() { ledgerAvailable = false }
    }
    private func presentingController() -> UIViewController? {
        var responder: UIResponder? = webView
        while let current = responder { if let controller = current as? UIViewController { return controller }; responder = current.next }
        return nil
    }
    private func send(record: PortalOperation) async {
        guard !stopped, let index = operations.firstIndex(where: { $0.userID == userID && $0.requestID == record.requestID }),
              operations[index].status == record.status else { return }
        if ["pay", "subscription.purchase"].contains(record.action), record.status == "pending" { return }
        operations[index].needsSend = true
        if operations[index].acknowledgmentAmbiguous == nil {
            // A record created by an older version has no reliable send history.
            operations[index].acknowledgmentAmbiguous = true
        } else if let candidate = operations[index].acknowledgedStatusCandidate {
            if candidate != record.status { operations[index].acknowledgmentAmbiguous = true }
        } else {
            operations[index].acknowledgedStatusCandidate = record.status
        }
        guard persist() else { ledgerAvailable = false; return }
        var purchaseData: [String: Any]?
        if record.action == "subscription.purchase", record.status == "purchased", let productID = productID(for: record), let transactionID = record.transactionID {
            purchaseData = ["planId": productID, "transactionId": transactionID, "verified": true]
        }
        _ = await send(requestID: record.requestID, action: record.action, status: record.status, plan: record.plan, completed: record.completed, data: purchaseData, error: record.failureReason)
    }
    @discardableResult private func send(requestID: String, action: String, status: String, plan: String? = nil, completed: Bool? = nil, data: Any? = nil, error: String? = nil) async -> Bool {
        if ["pay", "subscription.purchase"].contains(action), status == "pending" { return false }
        var result: [String: Any] = ["requestId": requestID, "action": action, "status": status, "version": 1, "platform": "app"]
        if let plan { result["params"] = ["plan": plan] }
        if let completed { result["completed"] = completed }
        if let data { result["data"] = data }
        if let error { result["error"] = error }
        // The demo relay wraps the whole message; H5 reads the result and its payload at that level.
        var envelope = result
        envelope["type"] = "APP_RESULT"
        envelope["userId"] = userID
        guard let bytes = try? JSONSerialization.data(withJSONObject: envelope), let text = String(data: bytes, encoding: .utf8) else {
            paymentLog.error("Result serialization failed; action=\(action, privacy: .public), status=\(status, privacy: .public)")
            return false
        }
        guard let connection = socket else {
            paymentLog.error("Result waiting for socket; action=\(action, privacy: .public), status=\(status, privacy: .public)")
            return false
        }
        do {
            try await connection.send(.string(text))
            paymentLog.info("Result sent to relay; action=\(action, privacy: .public), status=\(status, privacy: .public)")
            return true
        } catch {
            let failure = error as NSError
            paymentLog.error("Result send failed; action=\(action, privacy: .public), status=\(status, privacy: .public), domain=\(failure.domain, privacy: .public), code=\(failure.code)")
            if socket === connection { connection.cancel(with: .goingAway, reason: nil) }
            return false
        }
    }

    private func purchase(requestID: String, plan: String) async {
        guard !stopped, ledgerAvailable else { return }
        guard backend.purchaseAvailable else {
            await failPurchase(requestID, reason: "purchase_disabled")
            return
        }
        guard !paymentActive else {
            await failPurchase(requestID, reason: "purchase_in_progress")
            return
        }
        guard presentingController() != nil else {
            await failPurchase(requestID, reason: "presentation_unavailable")
            return
        }
        paymentActive = true
        purchaseStage = .preparing
        updatePurchaseActivity()
        defer { paymentActive = false; activeAccountToken = nil; purchaseStage = nil; updatePurchaseActivity() }
        guard let record = operation(requestID), let productID = productID(for: record),
              PortalConfiguration.monthlyProductID != PortalConfiguration.yearlyProductID else {
            await failPurchase(requestID, reason: "invalid_product_configuration")
            return
        }
        var orderAttempted = false
        var storeKitStarted = false
        do {
            paymentLog.info("B-side StoreKit product lookup started")
            let productLookupStartedAt = Date()
            guard let product = try await Product.products(for: [productID]).first else {
                paymentLog.notice("B-side StoreKit product unavailable; seconds=\(Date().timeIntervalSince(productLookupStartedAt), privacy: .public)")
                await failPurchase(requestID, reason: "product_not_found")
                return
            }
            paymentLog.info("B-side StoreKit product lookup finished; seconds=\(Date().timeIntervalSince(productLookupStartedAt), privacy: .public)")
            let period = product.subscription.map { "\($0.subscriptionPeriod.value) \(String(describing: $0.subscriptionPeriod.unit))" } ?? "none"
            paymentLog.info("StoreKit product \(productID, privacy: .public): period \(period, privacy: .public); requested plan \(plan, privacy: .public)")
            guard let index = operations.firstIndex(where: { $0.userID == userID && $0.requestID == requestID }) else {
                paymentLog.error("Purchase operation missing before order creation")
                return
            }
            guard !stopped else { return }
            let accountToken = UUID()
            activeAccountToken = accountToken
            operations[index].accountToken = accountToken
            guard persist() else {
                ledgerAvailable = false
                paymentLog.error("Could not save B-side purchase record before order creation")
                await send(requestID: requestID, action: record.action, status: "failed", plan: plan, error: "storage_unavailable")
                return
            }
            // The pending record is saved before creating an order, so an uncertain response never starts a second purchase.
            orderAttempted = true
            paymentLog.info("B-side order creation started")
            let orderStartedAt = Date()
            let order = try await backend.createOrder(productID: product.id, price: NSDecimalNumber(decimal: product.price).stringValue, usdPrice: plan == "monthly" ? "999" : "9999")
            paymentLog.info("B-side order creation succeeded; seconds=\(Date().timeIntervalSince(orderStartedAt), privacy: .public)")
            guard !stopped else { return }
            guard let credentials = backend.socketCredentials, credentials.userID == userID, credentials.token == token else {
                await failPurchase(requestID, reason: "session_unavailable")
                return
            }
            guard let orderIndex = operations.firstIndex(where: { $0.userID == userID && $0.requestID == requestID }) else { return }
            operations[orderIndex].orderID = order
            guard persist() else {
                ledgerAvailable = false
                paymentLog.error("Could not save B-side order before Apple purchase")
                await send(requestID: requestID, action: record.action, status: "failed", plan: plan, error: "storage_unavailable")
                return
            }
            purchaseStage = .awaitingApple
            updatePurchaseActivity()
            storeKitStarted = true
            paymentLog.info("B-side StoreKit purchase started")
            let purchaseStartedAt = Date()
            let purchaseResult = try await product.purchase(options: [.appAccountToken(accountToken)])
            paymentLog.info("B-side StoreKit purchase returned; seconds=\(Date().timeIntervalSince(purchaseStartedAt), privacy: .public)")
            guard !stopped else { return }
            switch purchaseResult {
            case .success(let result):
                paymentLog.info("StoreKit returned a transaction")
                switch result {
                case .verified(let transaction) where transaction.appAccountToken == accountToken && transaction.productID == productID:
                    await handleTransaction(result, refreshMissingReceipt: true)
                case .verified(let transaction):
                    paymentLog.error("B-side verified transaction did not match purchase: productMatches=\(transaction.productID == productID), accountTokenPresent=\(transaction.appAccountToken != nil), accountTokenMatches=\(transaction.appAccountToken == accountToken)")
                    let previousRecord = transaction.appAccountToken.flatMap { token in
                        operations.first { $0.accountToken == token && ["pay", "subscription.purchase"].contains($0.action) }
                    }
                    let ownership = previousRecord.map { $0.userID == userID ? "same_user_b" : "other_user_b" } ?? "unknown"
                    let predatesRequest = transaction.purchaseDate < purchaseStartedAt.addingTimeInterval(-60)
                    paymentLog.info("Mismatched transaction; knownOwner=\(ownership, privacy: .public), predatesRequest=\(predatesRequest)")
                    if previousRecord?.userID == userID { await handleTransaction(result) }
                    if let record = operation(requestID) { await send(record: record) }
                case .unverified(_, let error):
                    paymentLog.error("B-side StoreKit verification failed: reason=\(String(describing: error), privacy: .public)")
                    if let record = operation(requestID) { await send(record: record) }
                }
            case .pending:
                paymentLog.info("StoreKit purchase pending")
                if let record = operation(requestID) { await send(record: record) }
            case .userCancelled:
                paymentLog.info("StoreKit purchase cancelled")
                updateOperation(requestID, status: "cancelled")
                if let record = operation(requestID) { await send(record: record) }
            @unknown default:
                if let record = operation(requestID) { await send(record: record) }
            }
        } catch {
            guard !stopped else { return }
            let failure = error as NSError
            paymentLog.error("B-side purchase operation failed; orderAttempted=\(orderAttempted), appleStarted=\(storeKitStarted), domain=\(failure.domain, privacy: .public), code=\(failure.code)")
            if !orderAttempted {
                await failPurchase(requestID, reason: "product_query_failed")
                return
            }
            if !storeKitStarted {
                // No Apple purchase was started, even if the order response was lost.
                await failPurchase(requestID, reason: "order_creation_failed")
                return
            }
            // A StoreKit error may leave the outcome uncertain; retain it for reconciliation.
            if let record = operation(requestID) { await send(record: record) }
        }
    }

    private func failPurchase(_ requestID: String, reason: String) async {
        paymentLog.error("Purchase could not start: \(reason, privacy: .public)")
        updateOperation(requestID, status: "failed", failureReason: reason)
        if let record = operation(requestID) {
            if ledgerAvailable { await send(record: record) }
            else { await send(requestID: requestID, action: record.action, status: "failed", plan: record.plan, error: reason) }
        }
    }

    private func updatePurchaseActivity() {
        guard !stopped else { return }
        backend.purchaseActivity = verifyingRequests.isEmpty ? purchaseStage : .verifying
    }

    private func handleTransaction(_ result: VerificationResult<Transaction>, refreshMissingReceipt: Bool = false) async {
        guard !stopped else { return }
        guard ledgerAvailable, let credentials = backend.socketCredentials, credentials.userID == userID, credentials.token == token else {
            paymentLog.error("Transaction recovery waiting for local storage or the current session")
            return
        }
        guard case .verified(let transaction) = result else {
            if case .unverified(_, let error) = result {
                paymentLog.error("B-side transaction recovery failed local verification: reason=\(String(describing: error), privacy: .public)")
            }
            return
        }
        guard let accountToken = transaction.appAccountToken,
              let index = operations.firstIndex(where: { $0.userID == userID && ["pay", "subscription.purchase"].contains($0.action) && $0.accountToken == accountToken }) else {
            paymentLog.info("Transaction does not match a B-side purchase record; left unfinished")
            return
        }
        guard transaction.revocationDate == nil, transaction.productID == productID(for: operations[index]) else {
            paymentLog.error("B-side transaction is revoked or its product does not match the order")
            return
        }
        guard let orderID = operations[index].orderID, !orderID.isEmpty else {
            paymentLog.error("B-side transaction has no saved backend order; confirmation not sent")
            return
        }
        guard !processingTransactions.contains(transaction.id) else { return }
        let requestID = operations[index].requestID
        if operations[index].status == "purchased" {
            guard operations[index].transactionID == String(transaction.id) else { return }
            if let record = operation(requestID) { await send(record: record) }
            await transaction.finish()
            return
        }
        if let known = operations[index].transactionID, known != String(transaction.id) { return }
        processingTransactions.insert(transaction.id)
        verifyingRequests.insert(requestID)
        updatePurchaseActivity()
        defer {
            processingTransactions.remove(transaction.id)
            verifyingRequests.remove(requestID)
            updatePurchaseActivity()
        }
        operations[index].transactionID = String(transaction.id)
        guard persist() else { ledgerAvailable = false; paymentLog.error("Could not save B-side transaction; confirmation not sent"); return }
        let receiptURL = Bundle.main.appStoreReceiptURL
        var receipt = receiptURL.flatMap { try? Data(contentsOf: $0) }
        if (receipt?.isEmpty ?? true) && (refreshMissingReceipt || transaction.appAccountToken == activeAccountToken) {
            paymentLog.info("Requesting missing App Store receipt after purchase")
            if await PortalReceiptRefresh().refresh(), let refreshedURL = Bundle.main.appStoreReceiptURL {
                receipt = try? Data(contentsOf: refreshedURL)
            }
        }
        guard let receipt, !receipt.isEmpty else {
            paymentLog.error("Verified transaction is waiting for an App Store receipt")
            if let record = operation(requestID) { await send(record: record) }
            return
        }
        // The provider confirmed that repeated verification cannot issue the same entitlement twice.
        for attempt in 0..<3 {
            guard !stopped, !Task.isCancelled else { return }
            do {
                paymentLog.info("Confirming purchase with backend; attempt=\(attempt + 1)")
                try await backend.confirmPurchase(order: orderID, transactionID: String(transaction.id), receipt: receipt.base64EncodedString())
                paymentLog.info("Backend purchase confirmation succeeded")
                guard !stopped else { return }
                guard let currentIndex = operations.firstIndex(where: { $0.userID == userID && $0.requestID == requestID }) else { return }
                operations[currentIndex].status = "purchased"
                operations[currentIndex].needsSend = true
                guard persist() else { operations[currentIndex].status = "pending"; ledgerAvailable = false; paymentLog.error("Could not save confirmed B-side transaction; result not sent"); return }
                if let record = operation(requestID) { await send(record: record) }
                await transaction.finish()
                return
            } catch {
                let category: String
                switch error {
                case PortalError.unauthorized: category = "unauthorized"
                case PortalError.rejected(_): category = "backend_rejected"
                case PortalError.invalidResponse: category = "invalid_response"
                default: category = "request_error"
                }
                let failure = error as NSError
                paymentLog.error("Backend purchase confirmation failed; attempt=\(attempt + 1), category=\(category, privacy: .public), domain=\(failure.domain, privacy: .public), code=\(failure.code)")
                guard !stopped else { return }
                if attempt < 2 {
                    do { try await Task.sleep(nanoseconds: UInt64(attempt + 1) * 1_000_000_000) } catch { return }
                }
            }
        }
        if let record = operation(requestID) { await send(record: record) }
    }
}
