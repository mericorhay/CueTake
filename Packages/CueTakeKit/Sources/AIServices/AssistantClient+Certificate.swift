import Domain
import Foundation

extension AssistantClient {
    /// What the server is asked to sign.
    public struct CertificateRequest: Encodable, Sendable {
        public var level: String
        public var id: String
        public var name: String
        public var hours: Double
        public var projects: Int
        public var workflowRuns: Int
        public var tasks: [String]
        public var installID: String

        public init(level: CertificationLevel, id: String, name: String, progress: CertificationProgress) {
            self.level = level.rawValue
            self.id = id
            self.name = name
            hours = progress.activeHours
            projects = progress.finishedProjects.count
            workflowRuns = progress.workflowRuns
            tasks = progress.tasks.keys.map(\.rawValue).sorted()
            self.installID = progress.installID.uuidString
        }
    }

    private struct CertificateResponse: Decodable {
        var payload: String
        var signature: String
        var verifyURL: URL
    }

    /// Has the server sign a certificate the phone says was earned. The server holds the same
    /// bar and refuses a request below it.
    public func certify(_ request: CertificateRequest) async throws -> SignedCertificate {
        guard let endpoint else { throw AssistantError.notConfigured }
        var urlRequest = URLRequest(url: endpoint.url.appending(path: "certify"))
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = 20
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(endpoint.appToken, forHTTPHeaderField: "x-cuetake-app")
        urlRequest.httpBody = try JSONEncoder().encode(request)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: urlRequest)
        } catch {
            throw AssistantError.offline
        }
        guard let http = response as? HTTPURLResponse else { throw AssistantError.offline }
        guard (200..<300).contains(http.statusCode) else { throw AssistantError.rejected(status: http.statusCode) }
        let decoded = try JSONDecoder().decode(CertificateResponse.self, from: data)
        return SignedCertificate(payload: decoded.payload, signature: decoded.signature, verifyURL: decoded.verifyURL)
    }
}
