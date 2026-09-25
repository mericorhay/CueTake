import Domain
import Foundation

extension AssistantClient {
    private struct AgentBody: Encodable {
        var locale: String
        var request: AgentRequest

        func encode(to encoder: any Encoder) throws {
            try request.encode(to: encoder)
            var container = encoder.container(keyedBy: Key.self)
            try container.encode(locale, forKey: .locale)
        }

        enum Key: String, CodingKey { case locale }
    }

    /// One round of the AI editor: the conversation so far, and what the model does next.
    ///
    /// A 503 means the server has no model for this (the tools need the main model, not the
    /// fallback): the caller edits the old way instead.
    public func agentRound(_ agentRequest: AgentRequest, localeIdentifier: String) async throws -> AgentReply {
        guard let endpoint else { throw AssistantError.notConfigured }

        var request = URLRequest(url: endpoint.url.appending(path: "agent"))
        request.httpMethod = "POST"
        request.timeoutInterval = 150
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(endpoint.appToken, forHTTPHeaderField: "x-cuetake-app")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        request.httpBody = try encoder.encode(AgentBody(locale: localeIdentifier, request: agentRequest))

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await AssistantTransport.data(for: request)
        } catch {
            throw AssistantError.offline
        }
        guard let http = response as? HTTPURLResponse else { throw AssistantError.offline }
        guard (200..<300).contains(http.statusCode) else {
            throw AssistantError.rejected(status: http.statusCode)
        }
        return try JSONDecoder().decode(AgentReply.self, from: data)
    }
}
