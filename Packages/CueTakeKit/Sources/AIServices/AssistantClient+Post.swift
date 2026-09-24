import Domain
import Foundation

extension AssistantClient {
    private struct PostRequest: Encodable {
        var transcript: String
        var platforms: [String]
    }

    /// The post kit for a finished video: cover line, title, text and hashtags per platform, and a
    /// read of the hook. Only the transcript leaves the phone.
    public func postKit(transcript: String, platforms: [String]) async throws -> PostKit {
        guard let endpoint else { throw AssistantError.notConfigured }
        var request = URLRequest(url: endpoint.url.appending(path: "post"))
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(endpoint.appToken, forHTTPHeaderField: "x-cuetake-app")
        request.httpBody = try JSONEncoder().encode(PostRequest(transcript: transcript, platforms: platforms))

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await AssistantTransport.data(for: request)
        } catch {
            throw AssistantError.offline
        }
        guard let http = response as? HTTPURLResponse else { throw AssistantError.offline }
        guard (200..<300).contains(http.statusCode) else { throw AssistantError.rejected(status: http.statusCode) }
        let kit = try JSONDecoder().decode(PostKit.self, from: data)
        guard !kit.posts.isEmpty || !kit.title.isEmpty else { throw AssistantError.empty }
        return kit
    }
}
