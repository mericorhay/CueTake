import Domain
import Foundation

/// The suflör's cards, written on the server from the brand's brief.
extension AssistantClient {
    private struct SuflorRequest: Encodable {
        struct Brief: Encodable {
            var kind: String
            var platform: String
            var brand: String
            var product: String
            var mustSay: [String]
            var tone: String
            var topic: String
            var details: String
        }

        var brief: Brief
        var locale: String
    }

    private struct SuflorResponse: Decodable {
        var cues: String?
    }

    public func writeSuflor(_ brief: SuflorBrief, localeIdentifier: String) async throws -> [SuflorCue] {
        guard let endpoint else { throw AssistantError.notConfigured }
        let body = SuflorRequest(
            brief: .init(
                kind: brief.kind.rawValue,
                platform: brief.platform.rawValue,
                brand: brief.brand,
                product: brief.product,
                mustSay: brief.mustSay,
                tone: brief.tone,
                topic: brief.topic,
                details: brief.details
            ),
            locale: localeIdentifier
        )
        var request = URLRequest(url: endpoint.url.appending(path: "suflor"))
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(endpoint.appToken, forHTTPHeaderField: "x-cuetake-app")
        request.httpBody = try JSONEncoder().encode(body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw AssistantError.offline
        }
        guard let http = response as? HTTPURLResponse else { throw AssistantError.offline }
        guard (200..<300).contains(http.statusCode) else { throw AssistantError.rejected(status: http.statusCode) }
        guard let text = try JSONDecoder().decode(SuflorResponse.self, from: data).cues else { throw AssistantError.empty }
        let cues = SuflorPlan.cues(fromModelText: text)
        guard !cues.isEmpty else { throw AssistantError.empty }
        return cues
    }
}
