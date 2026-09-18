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
        /// The signed review, for the one level that needs it.
        public var review: AssistantClient.Signed?
        /// Apple's word, through App Attest, that the real app is asking. Nil where it cannot be had.
        public var attest: AttestProof?

        public init(level: CertificationLevel, id: String, name: String, progress: CertificationProgress) {
            self.level = level.rawValue
            self.id = id
            self.name = name
            hours = progress.activeHours
            projects = progress.finishedProjects.count
            workflowRuns = progress.workflowRuns
            tasks = progress.tasks.keys.map(\.rawValue).sorted()
            self.installID = progress.installID.uuidString
            if level.requiresReview, let review = progress.review {
                self.review = AssistantClient.Signed(payload: review.payload, signature: review.signature)
            }
        }
    }

    /// A finished project sent to be reviewed.
    public struct ReviewRequest: Encodable, Sendable {
        public var installID: String
        public var projectID: String
        public var title: String
        public var locale: String
        /// The project as the assistant reads it: clips, words, captions, effects, sound.
        public var document: String
        public var attest: AttestProof?

        public init(installID: UUID, project: Project) throws {
            self.installID = installID.uuidString
            projectID = project.id.uuidString
            title = project.title
            locale = project.localeIdentifier
            let data = try EditDocument(project: project).jsonData()
            document = String(decoding: data, as: UTF8.self)
        }
    }

    private struct ReviewResponse: Decodable {
        var score: Int
        var passed: Bool
        var strengths: [String]
        var improvements: [String]
        var payload: String
        var signature: String
    }

    /// Has the server's reviewer read a finished project and sign its verdict.
    public func review(_ request: ReviewRequest) async throws -> SignedReview {
        let data = try await postCertificate("review", request, timeout: 90)
        let decoded = try JSONDecoder().decode(ReviewResponse.self, from: data)
        return SignedReview(
            projectTitle: request.title,
            score: decoded.score,
            passed: decoded.passed,
            strengths: decoded.strengths,
            improvements: decoded.improvements,
            date: .now,
            payload: decoded.payload,
            signature: decoded.signature
        )
    }

    private struct CertificateResponse: Decodable {
        var payload: String
        var signature: String
        var verifyURL: URL
    }

    /// Has the server sign a certificate the phone says was earned. The server holds the same
    /// bar and refuses a request below it.
    public func certify(_ request: CertificateRequest) async throws -> SignedCertificate {
        let data = try await postCertificate("certify", request, timeout: 20)
        let decoded = try JSONDecoder().decode(CertificateResponse.self, from: data)
        return SignedCertificate(payload: decoded.payload, signature: decoded.signature, verifyURL: decoded.verifyURL)
    }

    private func postCertificate(_ path: String, _ body: some Encodable, timeout: TimeInterval) async throws -> Data {
        guard let endpoint else { throw AssistantError.notConfigured }
        var urlRequest = URLRequest(url: endpoint.url.appending(path: path))
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = timeout
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(endpoint.appToken, forHTTPHeaderField: "x-cuetake-app")
        urlRequest.httpBody = try JSONEncoder().encode(body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: urlRequest)
        } catch {
            throw AssistantError.offline
        }
        guard let http = response as? HTTPURLResponse else { throw AssistantError.offline }
        guard (200..<300).contains(http.statusCode) else { throw AssistantError.rejected(status: http.statusCode) }
        return data
    }
}
