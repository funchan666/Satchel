import Foundation
import Network
import OSLog
import Security

enum PortalConfiguration {
    static let baseURLString = "https://u9v8kve.satchel.click"
    static let socketHost = "u9v8kve.satchel.click"
    static let releaseName = "Satchel"
    // Backend registration is independent of the installed app's bundle identifier.
    static let servicePackageName = "com.satchel.traveljournal"
    // A and B share these Apple products; their purchase records and backend
    // fulfillment are still handled by their respective flows.
    static let monthlyProductID = SubscriptionProductIDs.monthly
    static let yearlyProductID = SubscriptionProductIDs.yearly
    static func productID(for plan: String) -> String? {
        switch plan {
        case "monthly": return monthlyProductID
        case "yearly": return yearlyProductID
        default: return nil
        }
    }
    static var baseURL: URL? {
        guard let url = URL(string: baseURLString), url.scheme?.lowercased() == "https", url.host != nil, url.user == nil, url.password == nil else { return nil }
        return url
    }
    static func isWebURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), ["https", "http"].contains(scheme), url.host != nil else { return false }
        return url.user == nil && url.password == nil
    }

}

private enum AdvertisingConfiguration {
    static func unitID(for type: Int, fields: [String: Any]) -> String? {
        guard let appID = Bundle.main.object(forInfoDictionaryKey: "GADApplicationIdentifier") as? String,
              let entries = fields["adList"] as? [[String: Any]] else { return nil }
        let matches = entries.filter {
            ($0["adType"] as? Int) == type &&
            ($0["advertiser"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "google"
        }
        guard matches.count == 1, let config = matches[0]["config"] as? [String: Any],
              let returnedAppID = (config["appId"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              let unitID = (config["adUnitId"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              returnedAppID == appID,
              appID.range(of: #"^ca-app-pub-[0-9]{16}~[0-9]{10}$"#, options: .regularExpression) != nil,
              unitID.range(of: #"^ca-app-pub-[0-9]{16}/[0-9]{10}$"#, options: .regularExpression) != nil,
              appID.split(separator: "~").first == unitID.split(separator: "/").first else { return nil }
        return unitID
    }
}

enum PortalError: LocalizedError {
    case missingConfiguration, invalidIP, invalidResponse, loginFailed, unauthorized, rejected(String), unsafeURL
    var errorDescription: String? {
        switch self {
        case .missingConfiguration: return "The online service is not configured yet."
        case .invalidIP: return "The public network address could not be obtained."
        case .invalidResponse: return "The service returned an invalid response."
        case .loginFailed: return "Guest sign-in did not return valid credentials."
        case .unauthorized: return "The session has expired. Please sign in again."
        case .rejected(let message): return message
        case .unsafeURL: return "The service did not return a valid web address."
        }
    }
}

private enum DeviceIdentity {
    private static let service = "Satchel.Portal"
    private static let account = "deviceCode"
    static func get() throws -> String {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
        var result: CFTypeRef?
        var find = query; find[kSecReturnData as String] = true; find[kSecMatchLimit as String] = kSecMatchLimitOne
        let status = SecItemCopyMatching(find as CFDictionary, &result)
        if status == errSecSuccess, let data = result as? Data, let value = String(data: data, encoding: .utf8), !value.isEmpty { return value }
        guard status == errSecItemNotFound else { throw PortalError.loginFailed }
        let value = UUID().uuidString
        var add = query; add[kSecValueData as String] = Data(value.utf8); add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        guard SecItemAdd(add as CFDictionary, nil) == errSecSuccess else { throw PortalError.loginFailed }
        return value
    }
}

private final class NoRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

@MainActor final class PortalBackend: ObservableObject {
    private let startupLog = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Satchel", category: "PortalStartup")
    private let paymentLog = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Satchel", category: "PortalPayment")
    @Published var purchaseActivity: PurchaseActivity?
    @Published private(set) var url: URL?
    @Published private(set) var isSignedIn = false
    @Published private(set) var busy = false
    @Published var error: String?
    private var token: String?
    private var loginDeviceCode: String?
    @Published private(set) var userID: String?
    private var sessionID = UUID()
    private var portalRequestID = UUID()
    private var refreshTask: Task<Void, Error>?
    private var credentialsObserver: (id: UUID, callback: (String, String) -> Void)?
    private(set) var purchaseAvailable = false
    private var adUnits: [Int: String] = [:]
    func adUnitID(for type: Int) -> String? { adUnits[type] }
    var socketCredentials: (userID: String, token: String)? {
        guard isSignedIn, let userID, let token else { return nil }
        return (userID, token)
    }
    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        return URLSession(configuration: config, delegate: NoRedirects(), delegateQueue: nil)
    }()
    private let ipSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 5
        config.timeoutIntervalForResource = 5
        return URLSession(configuration: config, delegate: NoRedirects(), delegateQueue: nil)
    }()
    func signIn() async {
        guard !busy else { return }
        adUnits = [:]
        let started = Date()
        busy = true; error = nil
        defer {
            busy = false
            startupLog.info("Guest login finished; success=\(self.isSignedIn), seconds=\(Date().timeIntervalSince(started), privacy: .public)")
        }
        do {
            let (user, access, deviceCode) = try await guestCredentials()
            sessionID = UUID()
            token = access; userID = user; loginDeviceCode = deviceCode; isSignedIn = true
        } catch { token = nil; userID = nil; loginDeviceCode = nil; isSignedIn = false; self.error = error.localizedDescription }
    }
    func open(language: String) async {
        guard !busy else { return }
        adUnits = [:]
        let started = Date()
        let requestID = UUID()
        portalRequestID = requestID
        busy = true; error = nil
        defer {
            busy = false
            startupLog.info("Portal configuration finished; addressAvailable=\(self.url != nil), seconds=\(Date().timeIntervalSince(started), privacy: .public)")
        }
        do {
            guard let base = PortalConfiguration.baseURL, !PortalConfiguration.releaseName.isEmpty else { throw PortalError.missingConfiguration }
            guard isSignedIn, let user = userID, let deviceCode = loginDeviceCode else { throw PortalError.loginFailed }
            guard let appID = Bundle.main.bundleIdentifier, !appID.isEmpty else { throw PortalError.missingConfiguration }
            let zone = TimeZone.current.identifier
            let query = ["platform": "ios", "name": PortalConfiguration.releaseName, "version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0", "lang": language, "userId": user, "time": zone, "input": "手机键盘"]
            let config = try await request(base: base, path: "/app-api/flow/release-package/getV2", query: query)
            guard portalRequestID == requestID, isSignedIn, userID == user else { return }
            let fields = nested(config)
            for type in [1, 5] {
                adUnits[type] = AdvertisingConfiguration.unitID(for: type, fields: fields)
            }
            if let disabled = fields["NB01"] as? Bool {
                purchaseAvailable = !disabled
            } else {
                // A missing/null switch permits purchases; an unrecognized value does not.
                purchaseAvailable = fields["NB01"] == nil || fields["NB01"] is NSNull
            }
            guard let address = fields["NB02"] as? String, !address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                url = nil
                return
            }
            guard let destination = URL(string: address), PortalConfiguration.isWebURL(destination),
                  var components = URLComponents(url: destination, resolvingAgainstBaseURL: false) else {
                url = nil
                throw PortalError.unsafeURL
            }
            var items = components.queryItems ?? []
            items.removeAll { $0.name == "deviceCode" || $0.name == "appId" }
            items.append(URLQueryItem(name: "deviceCode", value: deviceCode))
            items.append(URLQueryItem(name: "appId", value: appID))
            components.queryItems = items
            guard let resolvedURL = components.url else { throw PortalError.unsafeURL }
            url = resolvedURL
        } catch { if portalRequestID == requestID { self.error = error.localizedDescription } }
    }
    func userStatus() async throws -> Any {
        guard let base = PortalConfiguration.baseURL, let token, userID != nil else { throw PortalError.loginFailed }
        return try await request(base: base, path: "/app-api/member/user/get", bearer: token)
    }
    func createOrder(productID: String, price: String, usdPrice: String) async throws -> String {
        guard let base = PortalConfiguration.baseURL, let token, isSignedIn else { throw PortalError.loginFailed }
        let body: [String: Any] = ["rightsName": productID, "price": price, "usdPrice": usdPrice,
            "packageName": PortalConfiguration.servicePackageName, "versionCode": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0",
            "payType": "1", "source": "ios"]
        let result = try await request(base: base, path: "/app-api/flow/rights-order/buy", method: "POST", body: body, bearer: token)
        if let order = result as? String, !order.isEmpty { return order }
        if let order = result as? NSNumber { return order.stringValue }
        throw PortalError.invalidResponse
    }
    func confirmPurchase(order: String, transactionID: String, receipt: String) async throws {
        guard let base = PortalConfiguration.baseURL, let token, isSignedIn else { throw PortalError.loginFailed }
        let body: [String: Any] = ["verificationData": receipt, "purchaseID": order, "status": "purchased",
            "transactionId": transactionID]
        _ = try await request(base: base, path: "/app-api/flow/rights-order/buySuccess", method: "POST", body: body, bearer: token)
    }
    func closePortal() { portalRequestID = UUID(); url = nil; purchaseAvailable = false; error = nil }
    func signOut() {
        closePortal(); sessionID = UUID(); refreshTask?.cancel(); refreshTask = nil
        adUnits = [:]
        token = nil; userID = nil; loginDeviceCode = nil; isSignedIn = false
    }
    func observeCredentials(_ callback: @escaping (String, String) -> Void) -> UUID {
        let id = UUID()
        credentialsObserver = (id, callback)
        return id
    }
    func removeCredentialsObserver(_ id: UUID) {
        if credentialsObserver?.id == id { credentialsObserver = nil }
    }
    func renewCredentialsAfterUnauthorized(_ failedToken: String) async throws {
        _ = try await refreshedToken(after: failedToken)
    }
    private func guestCredentials() async throws -> (String, String, String) {
        guard let base = PortalConfiguration.baseURL else { throw PortalError.missingConfiguration }
        let started = Date()
        let ip = (try? await publicIP()) ?? ""
        startupLog.info("Public IP lookup finished; available=\(!ip.isEmpty), seconds=\(Date().timeIntervalSince(started), privacy: .public)")
        let deviceCode = try DeviceIdentity.get()
        let body = ["deviceCode": deviceCode, "uniqueId": ip, "source": PortalConfiguration.servicePackageName]
        let fields = nested(try await request(base: base, path: "/app-api/member/auth/app_tourist_login", method: "POST", body: body))
        guard let access = string(fields, keys: ["accessToken", "access_token", "token"]), !access.isEmpty,
              let user = string(fields, keys: ["userId", "user_id"]), !user.isEmpty else { throw PortalError.loginFailed }
        return (user, access, deviceCode)
    }
    private func refreshedToken(after failedToken: String) async throws -> String {
        guard isSignedIn, let userID, let token else { throw PortalError.loginFailed }
        if token != failedToken { return token }
        if let refreshTask {
            try await refreshTask.value
        } else {
            let originalSession = sessionID
            let task = Task { @MainActor in
                let (user, access, deviceCode) = try await self.guestCredentials()
                guard !Task.isCancelled, self.isSignedIn, self.sessionID == originalSession,
                      self.userID == userID, user == userID, self.loginDeviceCode == deviceCode else { throw PortalError.loginFailed }
                guard self.token == failedToken else { return }
                self.token = access
                self.credentialsObserver?.callback(user, access)
            }
            refreshTask = task
            defer { if sessionID == originalSession { refreshTask = nil } }
            try await task.value
        }
        guard isSignedIn, self.userID == userID, let updated = self.token else { throw PortalError.loginFailed }
        return updated
    }
    private func publicIP() async throws -> String {
        let session = ipSession
        let result = await withTaskGroup(of: String?.self, returning: String?.self) { group in
            for address in ["https://ipv4.icanhazip.com", "https://api.ipify.org/"] {
                guard let url = URL(string: address) else { continue }
                group.addTask {
                    guard let (data, response) = try? await session.data(from: url),
                          let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                          data.count < 128, let raw = String(data: data, encoding: .utf8) else { return nil }
                    let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                    return IPv4Address(value) == nil ? nil : value
                }
            }
            for await value in group {
                if let value { group.cancelAll(); return value }
            }
            return nil
        }
        guard let result else { throw PortalError.invalidIP }
        return result
    }
    private func request(base: URL, path: String, method: String = "GET", query: [String: String] = [:], body: [String: Any]? = nil, bearer: String? = nil) async throws -> Any {
        let originalSession = sessionID
        do {
            return try await sendRequest(base: base, path: path, method: method, query: query, body: body, bearer: bearer)
        } catch PortalError.unauthorized {
            guard let bearer, originalSession == sessionID else { throw PortalError.unauthorized }
            let renewed = try await refreshedToken(after: bearer)
            guard originalSession == sessionID else { throw PortalError.loginFailed }
            return try await sendRequest(base: base, path: path, method: method, query: query, body: body, bearer: renewed)
        }
    }
    private func sendRequest(base: URL, path: String, method: String, query: [String: String], body: [String: Any]?, bearer: String?) async throws -> Any {
        guard var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else { throw PortalError.missingConfiguration }
        components.path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.path = "/" + ([components.path, path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))].filter { !$0.isEmpty }.joined(separator: "/"))
        if !query.isEmpty { components.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) } }
        guard let url = components.url else { throw PortalError.missingConfiguration }
        var req = URLRequest(url: url); req.httpMethod = method; req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body { req.httpBody = try JSONSerialization.data(withJSONObject: body); req.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        if let bearer { req.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization") }
        let (data, response) = try await session.data(for: req)
        if ["/app-api/flow/rights-order/buy", "/app-api/flow/rights-order/buySuccess"].contains(path), let http = response as? HTTPURLResponse {
            let code = data.count <= 2_000_000 ? ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])?["code"] as? Int : nil
            let stage = path.hasSuffix("buySuccess") ? "confirmation" : "order"
            paymentLog.info("Backend \(stage, privacy: .public) response; HTTP=\(http.statusCode), businessCode=\(code.map { String($0) } ?? "missing", privacy: .public)")
        }
        if let http = response as? HTTPURLResponse, http.statusCode == 401 { throw PortalError.unauthorized }
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), data.count <= 2_000_000,
              let result = try JSONSerialization.jsonObject(with: data) as? [String: Any], let code = result["code"] as? Int else { throw PortalError.invalidResponse }
        guard code == 0 else { throw PortalError.rejected(result["msg"] as? String ?? "The service rejected the request.") }
        return result["data"] ?? NSNull()
    }
    private func nested(_ value: Any) -> [String: Any] {
        guard let dict = value as? [String: Any] else { return [:] }
        if let data = dict["data"] as? [String: Any] { return data }
        if let result = dict["result"] as? [String: Any] { return result }
        return dict
    }
    private func string(_ fields: [String: Any], keys: [String]) -> String? {
        for key in keys { if let value = fields[key] as? String { return value }; if let value = fields[key] as? NSNumber { return value.stringValue } }
        return nil
    }
}
