import Domain
import Foundation

/// Talks to CueTake's assistant endpoint.
///
/// The app never holds a model provider's key. It talks to our own small proxy
/// (`backend/assistant`), which holds the key, owns the system prompt, and wraps the user's words
/// into it before anything reaches the model. That split is the point of the design:
/// - A key compiled into an app is a key published to everyone who downloads it.
/// - The prompt can be improved without shipping an app update.
/// - A client that cannot choose the prompt cannot be talked into using a different one.
///
/// One request, one reply. No streaming: the replies are short, and a message that arrives whole
/// is simpler to animate well than one that types itself out while the layout keeps moving.
public struct AssistantClient: Sendable {
    public struct Endpoint: Sendable, Decodable {
        public var url: URL
        /// Identifies the app to the proxy. Not a secret in the cryptographic sense — anything in
        /// an app binary can be read — but it keeps the endpoint from being an open relay for
        /// anyone who finds the URL, and it can be rotated without touching the provider key.
        public var appToken: String
    }

    public enum AssistantError: Error, Hashable, Sendable {
        /// The build has no endpoint file. Development builds, and any build made without the
        /// assistant secrets set.
        case notConfigured
        case offline
        case rejected(status: Int)
        /// The model declined. Said as such, rather than as a network error.
        case declined
        case empty
    }

    public let endpoint: Endpoint?

    public init(endpoint: Endpoint?) {
        self.endpoint = endpoint
    }

    /// Reads `AssistantEndpoint.json` from the app bundle, which CI writes from repository secrets.
    /// The file is gitignored: the repository never contains it.
    public static func bundled(_ bundle: Bundle = .main) -> AssistantClient {
        guard let url = bundle.url(forResource: "AssistantEndpoint", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let endpoint = try? JSONDecoder().decode(Endpoint.self, from: data),
              !endpoint.appToken.isEmpty
        else { return AssistantClient(endpoint: nil) }
        return AssistantClient(endpoint: endpoint)
    }

    public var isConfigured: Bool { endpoint != nil }

    private struct Request: Encodable {
        struct Turn: Encodable {
            var role: String
            var text: String
            var context: String?
        }
        var session: String
        var locale: String
        var messages: [Turn]
    }

    private struct Response: Decodable {
        var reply: String?
        var stopReason: String?

        enum CodingKeys: String, CodingKey {
            case reply
            case stopReason = "stop_reason"
        }
    }

    /// The assistant's answer to the last user message in `session`.
    public func reply(to session: AssistantSession, localeIdentifier: String) async throws -> String {
        guard let endpoint else { throw AssistantError.notConfigured }

        var request = URLRequest(url: endpoint.url)
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(endpoint.appToken, forHTTPHeaderField: "x-cuetake-app")
        request.httpBody = try JSONEncoder().encode(
            Request(
                session: session.id.uuidString,
                locale: localeIdentifier,
                messages: session.messages.map {
                    Request.Turn(role: $0.role.rawValue, text: $0.text, context: $0.context)
                }
            )
        )

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw AssistantError.offline
        }

        guard let http = response as? HTTPURLResponse else { throw AssistantError.offline }
        guard (200..<300).contains(http.statusCode) else {
            throw AssistantError.rejected(status: http.statusCode)
        }

        let decoded = try JSONDecoder().decode(Response.self, from: data)
        if decoded.stopReason == "refusal" { throw AssistantError.declined }
        guard let reply = decoded.reply?.trimmingCharacters(in: .whitespacesAndNewlines), !reply.isEmpty else {
            throw AssistantError.empty
        }
        return reply
    }

    // MARK: - Editing

    private struct EditRequest: Encodable {
        var instruction: String
        var locale: String
        var document: EditDocument
    }

    private struct EditResponse: Decodable {
        var plan: String?
    }

    /// Sends the whole editor as a document with an instruction, and gets back a plan of edits.
    ///
    /// Longer timeout than a chat reply: a three minute video is a large document and the model
    /// reads every beat of it before answering.
    public func editPlan(for document: EditDocument, instruction: String, localeIdentifier: String) async throws -> EditPlan {
        guard let endpoint else { throw AssistantError.notConfigured }

        var request = URLRequest(url: endpoint.url.appending(path: "edit"))
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(endpoint.appToken, forHTTPHeaderField: "x-cuetake-app")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        request.httpBody = try encoder.encode(
            EditRequest(instruction: instruction, locale: localeIdentifier, document: document)
        )

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw AssistantError.offline
        }
        guard let http = response as? HTTPURLResponse else { throw AssistantError.offline }
        guard (200..<300).contains(http.statusCode) else {
            throw AssistantError.rejected(status: http.statusCode)
        }

        let decoded = try JSONDecoder().decode(EditResponse.self, from: data)
        guard let text = decoded.plan, !text.isEmpty else { throw AssistantError.empty }
        return try EditPlan.decode(from: text)
    }

    // MARK: - Workflows

    private struct WorkflowRequest: Encodable {
        var description: String
        var locale: String
        var clipCount: Int
    }

    private struct WorkflowResponse: Decodable {
        var workflow: String?
    }

    /// A workflow written from a sentence, by the server model.
    public func workflow(from description: String, clipCount: Int, localeIdentifier: String) async throws -> WorkflowDefinition {
        guard let endpoint else { throw AssistantError.notConfigured }

        var request = URLRequest(url: endpoint.url.appending(path: "workflow"))
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(endpoint.appToken, forHTTPHeaderField: "x-cuetake-app")
        request.httpBody = try JSONEncoder().encode(
            WorkflowRequest(description: description, locale: localeIdentifier, clipCount: clipCount)
        )

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw AssistantError.offline
        }
        guard let http = response as? HTTPURLResponse else { throw AssistantError.offline }
        guard (200..<300).contains(http.statusCode) else {
            throw AssistantError.rejected(status: http.statusCode)
        }
        let decoded = try JSONDecoder().decode(WorkflowResponse.self, from: data)
        guard let text = decoded.workflow, !text.isEmpty else { throw AssistantError.empty }
        var workflow = try WorkflowDefinition.decode(json: text)
        guard !workflow.steps.isEmpty else { throw AssistantError.empty }
        workflow.origin = .ai
        return workflow
    }
}
