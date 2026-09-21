import Foundation

public struct CreatorAccount: Codable, Sendable, Equatable {
    public var id: String
    public var name: String
}

public struct AccountSession: Codable, Sendable {
    public var token: String
    public var expiresAt: Double
    public var user: CreatorAccount
    public var appleUserID: String?
    public var deletionPending: Bool?
}

public struct AccountChallenge: Decodable, Sendable {
    public var id: String
    public var nonce: String
}

public struct AccountStatus: Decodable, Sendable {
    public var user: CreatorAccount
    public var expiresAt: Double
    public var deletionPending: Bool
}

public enum AccountError: Error, Sendable {
    case notConfigured, unauthorized, rateLimited, unavailable, invalidResponse, secureStorage
}

/// Native Apple credentials are exchanged only with our HTTPS account boundary.
/// The shared assistant token is deliberately neither sent nor accepted as a user identity.
public struct AccountClient: Sendable {
    public let endpoint: URL?
    public init(endpoint: URL?) {
        self.endpoint = endpoint?.scheme == "https" ? endpoint : nil
    }

    public static func bundled(_ bundle: Bundle = .main) -> Self {
        struct Configuration: Decodable { var url: URL }
        guard let file = bundle.url(forResource: "AssistantEndpoint", withExtension: "json"),
              let data = try? Data(contentsOf: file),
              let configuration = try? JSONDecoder().decode(Configuration.self, from: data)
        else { return Self(endpoint: nil) }
        return Self(endpoint: configuration.url)
    }

    public func challenge() async throws -> AccountChallenge {
        try await send("challenge", method: "POST")
    }

    public func signIn(challenge: String, code: String, identityToken: String, name: String?) async throws -> AccountSession {
        try await send("apple", method: "POST", body: [
            "challenge": challenge, "code": code, "identityToken": identityToken, "name": name ?? "",
        ])
    }

    public func status(token: String) async throws -> AccountStatus {
        try await send("session", method: "GET", token: token)
    }

    public func end(token: String, deleting: Bool) async throws {
        struct Result: Decodable, Sendable { var ok: Bool }
        let result: Result = try await send(deleting ? "account" : "logout", method: deleting ? "DELETE" : "POST", token: token)
        guard result.ok else { throw AccountError.invalidResponse }
    }

    private func send<Response: Decodable & Sendable>(
        _ path: String, method: String, token: String? = nil, body: [String: String]? = nil
    ) async throws -> Response {
        guard let endpoint else { throw AccountError.notConfigured }
        // Root paths: the configured assistant URL may itself include a route.
        guard let url = URL(string: "/auth/\(path)", relativeTo: endpoint)?.absoluteURL else { throw AccountError.notConfigured }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 25)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body { request.httpBody = try JSONEncoder().encode(body) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        let session = URLSession(configuration: configuration, delegate: NoAccountRedirects(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, data.count < 32_768 else { throw AccountError.invalidResponse }
        if http.statusCode == 401 { throw AccountError.unauthorized }
        if http.statusCode == 429 { throw AccountError.rateLimited }
        if http.statusCode == 503, String(data: data, encoding: .utf8)?.contains("not_configured") == true {
            throw AccountError.notConfigured
        }
        guard http.statusCode == 200 else { throw AccountError.unavailable }
        return try JSONDecoder().decode(Response.self, from: data)
    }
}

private final class NoAccountRedirects: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
