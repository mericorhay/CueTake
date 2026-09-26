import Foundation

extension AssistantClient {
    private struct ReviewSignIn: Encodable {
        var username: String
        var password: String
    }

    /// Whether the name and password are the test account's. Checked on our server, where the
    /// account lives as two secrets, so nothing in the app can reveal it.
    public func reviewSignIn(username: String, password: String) async throws -> Bool {
        guard let endpoint else { throw AssistantError.notConfigured }

        var request = URLRequest(url: endpoint.url.appending(path: "review-sign-in"))
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(endpoint.appToken, forHTTPHeaderField: "x-cuetake-app")
        request.httpBody = try JSONEncoder().encode(ReviewSignIn(username: username, password: password))

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await AssistantTransport.data(for: request)
        } catch {
            throw AssistantError.offline
        }
        guard let http = response as? HTTPURLResponse else { throw AssistantError.offline }
        if http.statusCode == 401 { return false }
        guard (200..<300).contains(http.statusCode) else { throw AssistantError.rejected(status: http.statusCode) }
        struct Answer: Decodable { var ok: Bool }
        return (try? JSONDecoder().decode(Answer.self, from: data))?.ok == true
    }
}
