import Foundation
import Network
import Security

/// Configuration must be filled with the provider's actual deployment values.
enum PortalConfiguration {
    static let baseURLString = ""
    static let releaseName = "iaptest.ios"
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
    case missingConfiguration, invalidIP, invalidResponse, loginFailed, rejected(String), unsafeURL
    var errorDescription: String? {
        switch self {
        case .missingConfiguration: return "The online service is not configured yet."
        case .invalidIP: return "The public network address could not be obtained."
        case .invalidResponse: return "The service returned an invalid response."
        case .loginFailed: return "Guest sign-in did not return valid credentials."
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
            guard let base = PortalConfiguration.baseURL else { throw PortalError.missingConfiguration }
            let ip = try await publicIP()
            let device = try DeviceIdentity.get()
            let body = ["deviceCode": device, "uniqueId": ip, "source": Bundle.main.bundleIdentifier ?? ""]
            let login = try await request(base: base, path: "/app-api/member/auth/app_tourist_login", method: "POST", body: body)
            let fields = nested(login)
            guard let access = string(fields, keys: ["accessToken", "access_token", "token"]), !access.isEmpty,
                  let user = string(fields, keys: ["userId", "user_id"]), !user.isEmpty else { throw PortalError.loginFailed }
            token = access; userID = user; isSignedIn = true
        } catch { token = nil; userID = nil; isSignedIn = false; self.error = error.localizedDescription }
    }
    func open(language: String) async {
        guard !busy else { return }
        busy = true; error = nil
        defer { busy = false }
        do {
            guard let base = PortalConfiguration.baseURL, !PortalConfiguration.releaseName.isEmpty else { throw PortalError.missingConfiguration }
            guard isSignedIn, let user = userID else { throw PortalError.loginFailed }
            let seconds = TimeZone.current.secondsFromGMT(); let sign = seconds < 0 ? "-" : "+"
            let zone = String(format: "GMT%@%02d:%02d", sign, abs(seconds) / 3600, (abs(seconds) % 3600) / 60)
            let query = ["platform": "IOS", "name": PortalConfiguration.releaseName, "version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0", "lang": language, "userId": user, "time": zone, "input": "手机键盘"]
            let config = try await request(base: base, path: "/app-api/flow/release-package/getV2", query: query)
            guard let address = nested(config)["NB02"] as? String, let destination = URL(string: address), PortalConfiguration.isWebURL(destination) else { throw PortalError.unsafeURL }
            url = destination
        } catch { self.error = error.localizedDescription }
    }
    func userStatus() async throws -> Any {
        guard let base = PortalConfiguration.baseURL, let token, userID != nil else { throw PortalError.loginFailed }
        return try await request(base: base, path: "/app-api/member/user/get", bearer: token)
    }
    func closePortal() { url = nil; error = nil }
    func signOut() { closePortal(); token = nil; userID = nil; isSignedIn = false }
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
    private func request(base: URL, path: String, method: String = "GET", query: [String: String] = [:], body: [String: String]? = nil, bearer: String? = nil) async throws -> Any {
        guard var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else { throw PortalError.missingConfiguration }
        components.path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.path = "/" + ([components.path, path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))].filter { !$0.isEmpty }.joined(separator: "/"))
        if !query.isEmpty { components.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) } }
        guard let url = components.url else { throw PortalError.missingConfiguration }
        var req = URLRequest(url: url); req.httpMethod = method; req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body { req.httpBody = try JSONSerialization.data(withJSONObject: body); req.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        if let bearer { req.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization") }
        let (data, response) = try await session.data(for: req)
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
