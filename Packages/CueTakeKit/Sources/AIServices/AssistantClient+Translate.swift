import Domain
import Foundation

extension AssistantClient {
    private struct TranslateRequest: Encodable {
        struct Line: Encodable {
            var id: String
            var text: String
        }

        var lines: [Line]
        var locale: String
        var target: String
    }

    private struct TranslateResponse: Decodable {
        var translation: String?
    }

    private struct TranslateAnswer: Decodable {
        struct Line: Decodable {
            var id: String
            var text: String
        }

        var lines: [Line]
    }

    /// Caption lines in another language, by cue. Sent in pieces of about a hundred lines, each with
    /// a little of the piece before it for context, so a long video translates as reliably as a
    /// short one. Only the lines' text leaves the phone.
    public func translateCaptions(
        _ lines: [(id: CaptionCue.ID, text: String)],
        from localeIdentifier: String,
        to target: String,
        progress: @Sendable (Double) async -> Void = { _ in }
    ) async throws -> [CaptionCue.ID: String] {
        guard let endpoint else { throw AssistantError.notConfigured }
        let chunk = 100
        var result: [CaptionCue.ID: String] = [:]
        var start = 0
        while start < lines.count {
            try Task.checkCancellation()
            let end = min(start + chunk, lines.count)
            // Short ids keep the request small; the answer maps back through the index.
            let piece = Array(lines[start..<end])
            let body = TranslateRequest(
                lines: piece.enumerated().map { TranslateRequest.Line(id: String($0.offset + 1), text: $0.element.text) },
                locale: localeIdentifier,
                target: target
            )

            var request = URLRequest(url: endpoint.url.appending(path: "translate"))
            request.httpMethod = "POST"
            request.timeoutInterval = 150
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
            let decoded = try JSONDecoder().decode(TranslateResponse.self, from: data)
            guard let text = decoded.translation,
                  let open = text.firstIndex(of: "{"), let close = text.lastIndex(of: "}"), open < close
            else { throw AssistantError.empty }
            let answer = try JSONDecoder().decode(TranslateAnswer.self, from: Data(text[open...close].utf8))
            for line in answer.lines {
                guard let number = Int(line.id.trimmingCharacters(in: .whitespaces)), piece.indices.contains(number - 1) else { continue }
                let translated = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !translated.isEmpty { result[piece[number - 1].id] = translated }
            }
            start = end
            await progress(Double(end) / Double(lines.count))
        }
        guard !result.isEmpty else { throw AssistantError.empty }
        return result
    }
}
