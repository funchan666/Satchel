import Foundation
import StoreKit
import UIKit
import WebKit

private final class PortalSocketDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

private struct PortalOperation: Codable {
    let userID: String
    let requestID: String
    let action: String
    let plan: String?
    var status: String
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
    private var operations: [PortalOperation] = []
    private var ledgerAvailable = false
    private var processing: Set<String> = []
    private var processingTransactions: Set<UInt64> = []
    private var paymentActive = false
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
    }

    func stop() {
        stopped = true
        if let credentialsObserverID { backend.removeCredentialsObserver(credentialsObserverID); self.credentialsObserverID = nil }
        loop?.cancel(); loop = nil; updates?.cancel(); updates = nil
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
            for record in operations where record.userID == userID && record.needsSend == true {
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
              matchesUser(envelope["userId"]),
              let outerType = envelope["type"] as? String,
              var data = envelope["data"] as? [String: Any] else { return }
        if outerType == "ACK" {
            acknowledge(data)
            return
        }
        guard ["PAYMENT", "AD_REQUEST", "REQUEST"].contains(outerType) else { return }
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
              (data["platform"] as? String) != "app" else { return }
        let plan: String?
        if action == "subscription.purchase" {
            switch params["planId"] as? String {
            case "test.plan.month": plan = "monthly"
            case "test.plan.year": plan = "yearly"
            default: plan = nil
            }
        } else { plan = params["plan"] as? String }
        guard ["pay", "ad.rewarded", "ad.interstitial", "subscription.getStatus", "subscription.getProducts", "subscription.purchase", "subscription.restore"].contains(action) else { return }
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
                    let products = try await Product.products(for: ["test.plan.month", "test.plan.year"])
                    let valid = products.filter { product in
                        guard let period = product.subscription?.subscriptionPeriod, period.value == 1 else { return false }
                        return product.id == "test.plan.month" ? period.unit == .month : product.id == "test.plan.year" && period.unit == .year
                    }
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
                                      transaction.productID == ($0.plan == "monthly" ? "test.plan.month" : "test.plan.year")
                                  }), let plan = record.plan else { continue }
                            await self.send(requestID: requestID, action: action, status: "purchased", data: ["planId": plan == "monthly" ? "test.plan.month" : "test.plan.year", "transactionId": String(transaction.id), "verified": true])
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
        record.acknowledgmentAmbiguous = false
        if ["pay", "subscription.purchase"].contains(action) { record.needsSend = true }
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
                let result = action == "ad.rewarded" ? await self.ads.show(from: self.presentingController()) : await self.ads.showInterstitial(from: self.presentingController())
                guard !self.stopped else { return }
                let status = ["rewarded", "dismissed"].contains(result) ? result : "failed"
                self.updateOperation(requestID, status: status, completed: action == "ad.rewarded" ? result == "rewarded" : nil)
                if let updated = self.operation(requestID) { await self.send(record: updated) }
            }
        }
    }

    private func operation(_ id: String) -> PortalOperation? { operations.first { $0.userID == userID && $0.requestID == id } }
    private func acknowledge(_ data: [String: Any]) {
        guard data["platform"] as? String == "h5", data["status"] as? String == "received",
              data["version"] as? Int == 1, let requestID = data["requestId"] as? String,
              let action = data["action"] as? String,
              let index = operations.firstIndex(where: { $0.userID == userID && $0.requestID == requestID && $0.action == action }),
              operations[index].needsSend == true else { return }
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
    private func updateOperation(_ id: String, status: String, completed: Bool? = nil) {
        guard let index = operations.firstIndex(where: { $0.userID == userID && $0.requestID == id }) else { return }
        operations[index].status = status; operations[index].completed = completed; operations[index].needsSend = true
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
        if record.action == "subscription.purchase", record.status == "purchased", let plan = record.plan, let transactionID = record.transactionID {
            purchaseData = ["planId": plan == "monthly" ? "test.plan.month" : "test.plan.year", "transactionId": transactionID, "verified": true]
        }
        _ = await send(requestID: record.requestID, action: record.action, status: record.status, plan: record.plan, completed: record.completed, data: purchaseData)
    }
    @discardableResult private func send(requestID: String, action: String, status: String, plan: String? = nil, completed: Bool? = nil, data: Any? = nil, error: String? = nil) async -> Bool {
        var result: [String: Any] = ["requestId": requestID, "action": action, "status": status, "version": 1, "platform": "app"]
        if let plan { result["params"] = ["plan": plan] }
        if let completed { result["completed"] = completed }
        if let data { result["data"] = data }
        if let error { result["error"] = error }
        // The demo relay wraps the whole message; H5 reads the result and its payload at that level.
        var envelope = result
        envelope["type"] = "APP_RESULT"
        envelope["userId"] = userID
        guard let bytes = try? JSONSerialization.data(withJSONObject: envelope), let text = String(data: bytes, encoding: .utf8), let socket else { return false }
        do { try await socket.send(.string(text)); return true } catch { return false }
    }

    private func purchase(requestID: String, plan: String) async {
        guard !stopped, ledgerAvailable else { return }
        guard backend.purchaseAvailable else {
            updateOperation(requestID, status: "failed")
            if let record = operation(requestID) { await send(record: record) }
            return
        }
        guard !paymentActive else {
            updateOperation(requestID, status: "failed")
            if let record = operation(requestID) { await send(record: record) }
            return
        }
        guard backend.paymentSettings != nil, presentingController() != nil else {
            updateOperation(requestID, status: "failed")
            if let record = operation(requestID) { await send(record: record) }
            return
        }
        paymentActive = true; defer { paymentActive = false }
        let productID = plan == "monthly" ? "test.plan.month" : "test.plan.year"
        var orderAttempted = false
        do {
            guard let product = try await Product.products(for: [productID]).first,
                  let period = product.subscription?.subscriptionPeriod, period.value == 1,
                  (plan == "monthly" ? period.unit == .month : period.unit == .year),
                  let index = operations.firstIndex(where: { $0.userID == userID && $0.requestID == requestID }) else {
                updateOperation(requestID, status: "failed")
                if let record = operation(requestID) { await send(record: record) }
                return
            }
            guard !stopped else { return }
            let accountToken = UUID()
            operations[index].accountToken = accountToken
            guard persist() else { ledgerAvailable = false; return }
            // The pending record is saved before creating an order, so an uncertain response never starts a second purchase.
            orderAttempted = true
            let order = try await backend.createOrder(productID: product.id, price: NSDecimalNumber(decimal: product.price).stringValue, usdPrice: plan == "monthly" ? "999" : "9999")
            guard !stopped, let credentials = backend.socketCredentials, credentials.userID == userID, credentials.token == token else { return }
            guard let orderIndex = operations.firstIndex(where: { $0.userID == userID && $0.requestID == requestID }) else { return }
            operations[orderIndex].orderID = order
            guard persist() else { ledgerAvailable = false; return }
            let purchaseResult = try await product.purchase(options: [.appAccountToken(accountToken)])
            guard !stopped else { return }
            switch purchaseResult {
            case .success(let result):
                await handleTransaction(result)
            case .pending:
                if let record = operation(requestID) { await send(record: record) }
            case .userCancelled:
                updateOperation(requestID, status: "cancelled")
                if let record = operation(requestID) { await send(record: record) }
            @unknown default:
                if let record = operation(requestID) { await send(record: record) }
            }
        } catch {
            // A transport or StoreKit error may occur after the operation started; keep it pending for reconciliation.
            guard !stopped else { return }
            if !orderAttempted { updateOperation(requestID, status: "failed") }
            if let record = operation(requestID) { await send(record: record) }
        }
    }

    private func handleTransaction(_ result: VerificationResult<Transaction>) async {
        guard !stopped, ledgerAvailable, let credentials = backend.socketCredentials, credentials.userID == userID, credentials.token == token,
              case .verified(let transaction) = result, let accountToken = transaction.appAccountToken,
              transaction.revocationDate == nil,
              let index = operations.firstIndex(where: { $0.userID == userID && ["pay", "subscription.purchase"].contains($0.action) && $0.accountToken == accountToken }),
              let orderID = operations[index].orderID, !orderID.isEmpty,
              let plan = operations[index].plan,
              transaction.productID == (plan == "monthly" ? "test.plan.month" : "test.plan.year"),
              !processingTransactions.contains(transaction.id) else { return }
        let requestID = operations[index].requestID
        if operations[index].status == "purchased" {
            guard operations[index].transactionID == String(transaction.id) else { return }
            await transaction.finish()
            if let record = operation(requestID) { await send(record: record) }
            return
        }
        if let known = operations[index].transactionID, known != String(transaction.id) { return }
        processingTransactions.insert(transaction.id)
        defer { processingTransactions.remove(transaction.id) }
        operations[index].transactionID = String(transaction.id)
        guard persist() else { ledgerAvailable = false; return }
        guard let receiptURL = Bundle.main.appStoreReceiptURL,
              let receipt = try? Data(contentsOf: receiptURL), !receipt.isEmpty else {
            if let record = operation(requestID) { await send(record: record) }
            return
        }
        guard backend.paymentSettings != nil else { return }
        // The provider confirmed that repeated verification cannot issue the same entitlement twice.
        for attempt in 0..<3 {
            guard !stopped, !Task.isCancelled else { return }
            do {
                try await backend.confirmPurchase(order: orderID, transactionID: String(transaction.id), receipt: receipt.base64EncodedString())
                guard !stopped else { return }
                guard let currentIndex = operations.firstIndex(where: { $0.userID == userID && $0.requestID == requestID }) else { return }
                operations[currentIndex].status = "purchased"
                operations[currentIndex].needsSend = true
                guard persist() else { operations[currentIndex].status = "pending"; ledgerAvailable = false; return }
                await transaction.finish()
                if let record = operation(requestID) { await send(record: record) }
                return
            } catch {
                guard !stopped else { return }
                if attempt < 2 {
                    do { try await Task.sleep(nanoseconds: UInt64(attempt + 1) * 1_000_000_000) } catch { return }
                }
            }
        }
        if let record = operation(requestID) { await send(record: record) }
    }
}
