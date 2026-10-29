import Foundation
import Network
import Security

/// Development endpoints supplied by the provider; production values must be configured separately.
enum PortalConfiguration {
    static let baseURLString = "https://devapi.io-jp.com"
    static let socketHost = "devapi.io-jp.com"
    static let releaseName = "iaptest.ios"
    // Keep these aligned with the provider's H5/backend and Satchel's Apple products.
    // They must remain distinct from A-side product identifiers.
    static let monthlyProductID = "test.plan.month"
    static let yearlyProductID = "test.plan.year"
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
    @Published private(set) var url: URL?
    @Published private(set) var isSignedIn = false
    @Published private(set) var busy = false
    @Published var error: String?
    private var token: String?
    private var userID: String?
    private var sessionID = UUID()
    private var portalRequestID = UUID()
    private var refreshTask: Task<Void, Error>?
    private var credentialsObserver: (id: UUID, callback: (String, String) -> Void)?
    private(set) var paymentSettings: (sandbox: Bool, sharedKey: String)?
    private(set) var purchaseAvailable = false
    var socketCredentials: (userID: String, token: String)? {
        guard isSignedIn, let userID, let token else { return nil }
        return (userID, token)
    }
    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        return URLSession(configuration: config, delegate: NoRedirects(), delegateQueue: nil)
    }()
    func signIn() async {
        guard !busy else { return }
        busy = true; error = nil
        defer { busy = false }
        do {
            let (user, access) = try await guestCredentials()
            sessionID = UUID()
            token = access; userID = user; isSignedIn = true
        } catch { token = nil; userID = nil; isSignedIn = false; self.error = error.localizedDescription }
    }
    func open(language: String) async {
        guard !busy else { return }
        let requestID = UUID()
        portalRequestID = requestID
        busy = true; error = nil
        defer { busy = false }
        do {
            guard let base = PortalConfiguration.baseURL, !PortalConfiguration.releaseName.isEmpty else { throw PortalError.missingConfiguration }
            guard isSignedIn, let user = userID else { throw PortalError.loginFailed }
            let seconds = TimeZone.current.secondsFromGMT(); let sign = seconds < 0 ? "-" : "+"
            let zone = String(format: "GMT%@%02d:%02d", sign, abs(seconds) / 3600, (abs(seconds) % 3600) / 60)
            let query = ["platform": "IOS", "name": PortalConfiguration.releaseName, "version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0", "lang": language, "userId": user, "time": zone, "input": "手机键盘"]
            let config = try await request(base: base, path: "/app-api/flow/release-package/getV2", query: query)
            guard portalRequestID == requestID, isSignedIn, userID == user else { return }
            let fields = nested(config)
            if let ios = fields["ios"] as? [String: Any], let sandbox = ios["sandBoxTest"] as? Bool,
               let sharedKey = ios["iosVerifyShareKey"] as? String, !sharedKey.isEmpty {
                paymentSettings = (sandbox, sharedKey)
            } else { paymentSettings = nil }
            purchaseAvailable = (fields["NB01"] as? Bool) == false && paymentSettings != nil
            guard let address = fields["NB02"] as? String, let destination = URL(string: address), PortalConfiguration.isWebURL(destination),
                  var components = URLComponents(url: destination, resolvingAgainstBaseURL: false) else { throw PortalError.unsafeURL }
            var items = components.queryItems ?? []
            items.removeAll { $0.name == "userId" }
            items.append(URLQueryItem(name: "userId", value: user))
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
            "packageName": Bundle.main.bundleIdentifier ?? "", "versionCode": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0",
            "payType": "1", "source": "ios"]
        let result = try await request(base: base, path: "/app-api/flow/rights-order/buy", method: "POST", body: body, bearer: token)
        if let order = result as? String, !order.isEmpty { return order }
        if let order = result as? NSNumber { return order.stringValue }
        throw PortalError.invalidResponse
    }
    func confirmPurchase(order: String, transactionID: String, receipt: String) async throws {
        guard let base = PortalConfiguration.baseURL, let token, isSignedIn, let settings = paymentSettings else { throw PortalError.missingConfiguration }
        let body: [String: Any] = ["verificationData": receipt, "purchaseID": order, "status": "purchased",
            "sandBoxTest": settings.sandbox, "transactionId": transactionID, "iosVerifyShareKey": settings.sharedKey]
        _ = try await request(base: base, path: "/app-api/flow/rights-order/buySuccess", method: "POST", body: body, bearer: token)
    }
    func closePortal() { portalRequestID = UUID(); url = nil; paymentSettings = nil; purchaseAvailable = false; error = nil }
    func signOut() {
        closePortal(); sessionID = UUID(); refreshTask?.cancel(); refreshTask = nil
        token = nil; userID = nil; isSignedIn = false
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
    private func guestCredentials() async throws -> (String, String) {
        guard let base = PortalConfiguration.baseURL else { throw PortalError.missingConfiguration }
        let ip = (try? await publicIP()) ?? ""
        let body = ["deviceCode": try DeviceIdentity.get(), "uniqueId": ip, "source": Bundle.main.bundleIdentifier ?? ""]
        let fields = nested(try await request(base: base, path: "/app-api/member/auth/app_tourist_login", method: "POST", body: body))
        guard let access = string(fields, keys: ["accessToken", "access_token", "token"]), !access.isEmpty,
              let user = string(fields, keys: ["userId", "user_id"]), !user.isEmpty else { throw PortalError.loginFailed }
        return (user, access)
    }
    private func refreshedToken(after failedToken: String) async throws -> String {
        guard isSignedIn, let userID, let token else { throw PortalError.loginFailed }
        if token != failedToken { return token }
        if let refreshTask {
            try await refreshTask.value
        } else {
            let originalSession = sessionID
            let task = Task { @MainActor in
                let (user, access) = try await self.guestCredentials()
                guard !Task.isCancelled, self.isSignedIn, self.sessionID == originalSession,
                      self.userID == userID, user == userID else { throw PortalError.loginFailed }
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
        for address in ["https://ipv4.icanhazip.com", "https://api.ipify.org/"] {
            guard let url = URL(string: address) else { continue }
            do {
                let (data, response) = try await session.data(from: url)
                guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), data.count < 128,
                      let raw = String(data: data, encoding: .utf8) else { continue }
                let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                if IPv4Address(value) != nil { return value }
            } catch { continue }
        }
        throw PortalError.invalidIP
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
