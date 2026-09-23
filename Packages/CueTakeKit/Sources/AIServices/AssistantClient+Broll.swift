import Domain
import Foundation

/// A stock shot the server found for a moment of the video.
public struct StockShot: Sendable, Decodable, Hashable {
    public struct Video: Sendable, Decodable, Hashable {
        public var id: String
        public var url: URL
        public var width: Int
        public var height: Int
        public var duration: Double
        public var page: URL?
        public var author: String
    }

    /// Where it goes on the finished video, and for how long.
    public var at: Double
    public var seconds: Double
    /// What was searched for, in English.
    public var query: String
    public var video: Video
}

extension AssistantClient {
    private struct BrollRequest: Encodable {
        var sentences: [SpokenSentence]
        var count: Int
        var orientation: String
    }

    private struct BrollResponse: Decodable {
        var shots: [StockShot]?
    }

    /// Cut-away shots for the video: the server model picks the moments from the sentences and
    /// searches a stock library the creator may use commercially. Only sentence text and times
    /// leave the phone; the library's key stays on the server.
    public func stockBroll(for sentences: [SpokenSentence], count: Int, portrait: Bool) async throws -> [StockShot] {
        guard let endpoint else { throw AssistantError.notConfigured }
        var request = URLRequest(url: endpoint.url.appending(path: "broll"))
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(endpoint.appToken, forHTTPHeaderField: "x-cuetake-app")
        request.httpBody = try JSONEncoder().encode(BrollRequest(sentences: sentences, count: count, orientation: portrait ? "portrait" : "landscape"))

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await AssistantTransport.data(for: request)
        } catch {
            throw AssistantError.offline
        }
        guard let http = response as? HTTPURLResponse else { throw AssistantError.offline }
        guard (200..<300).contains(http.statusCode) else { throw AssistantError.rejected(status: http.statusCode) }
        let shots = try JSONDecoder().decode(BrollResponse.self, from: data).shots ?? []
        guard !shots.isEmpty else { throw AssistantError.empty }
        return shots
    }
}
