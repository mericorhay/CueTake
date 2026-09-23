import Domain
import Foundation

/// The second listener, and the judge between the two.
///
/// Whisper on the server hears a recording independently of the phone. Where the two disagree the
/// server model reads both versions — with the script, when there is one — and says which is what
/// was said. The phone's answer is never thrown away: both stay in the project, passage by passage.
extension AssistantClient {
    private struct HeardResponse: Decodable {
        /// The language Whisper heard, as a name ("english") or a code.
        var language: String?
        /// `[text, start, end]`.
        var words: [[Lossless]]?
        /// `[start, end, avgLogprob, noSpeechProb, compressionRatio]`.
        var segments: [[Double?]]?
    }

    /// A JSON value that may be a string or a number.
    private enum Lossless: Decodable {
        case text(String)
        case number(Double)
        case other

        init(from decoder: any Decoder) throws {
            if let value = try? decoder.singleValueContainer().decode(Double.self) {
                self = .number(value)
            } else if let value = try? decoder.singleValueContainer().decode(String.self) {
                self = .text(value)
            } else {
                self = .other
            }
        }

        var string: String? { if case .text(let value) = self { value } else { nil } }
        var double: Double? { if case .number(let value) = self { value } else { nil } }
    }

    /// Every word the server heard in an audio file, in seconds from its start.
    ///
    /// Words from stretches the model itself marks as probably not speech, or as a loop of repeated
    /// text, are dropped here: those are Whisper's known inventions over silence and music.
    ///
    /// - Parameter prompt: words likely to be said (the script), to help with names and terms.
    public func transcribe(audio url: URL, localeIdentifier: String, prompt: String) async throws -> [TimedWord] {
        try await hear(audio: url, localeIdentifier: localeIdentifier, prompt: prompt).words
    }

    /// The language spoken in an audio file, as a language code ("en"), by Whisper's own detection.
    public func spokenLanguage(of url: URL) async throws -> String? {
        try await hear(audio: url, localeIdentifier: "", prompt: "").language
    }

    /// A Whisper language, given as a name or a code, as a language code.
    public static func languageCode(fromWhisper value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !value.isEmpty else { return nil }
        if value.count <= 3, value.allSatisfy(\.isLetter) { return value }
        let english = Locale(identifier: "en")
        for code in Locale.LanguageCode.isoLanguageCodes.map(\.identifier) where code.count == 2 {
            if english.localizedString(forLanguageCode: code)?.lowercased() == value { return code }
        }
        return nil
    }

    private func hear(audio url: URL, localeIdentifier: String, prompt: String) async throws -> (words: [TimedWord], language: String?) {
        guard let endpoint else { throw AssistantError.notConfigured }

        var components = URLComponents(url: endpoint.url.appending(path: "transcribe"), resolvingAgainstBaseURL: false)
        let language = localeIdentifier.isEmpty ? "" : (Locale(identifier: localeIdentifier).language.languageCode?.identifier ?? "")
        var query = [URLQueryItem(name: "language", value: language)]
        let hint = String(prompt.prefix(400)).trimmingCharacters(in: .whitespacesAndNewlines)
        if !hint.isEmpty { query.append(URLQueryItem(name: "prompt", value: hint)) }
        components?.queryItems = query
        guard let address = components?.url else { throw AssistantError.notConfigured }

        var request = URLRequest(url: address)
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue("audio/mp4", forHTTPHeaderField: "Content-Type")
        request.setValue(endpoint.appToken, forHTTPHeaderField: "x-cuetake-app")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await AssistantTransport.upload(for: request, fromFile: url)
        } catch {
            throw AssistantError.offline
        }
        guard let http = response as? HTTPURLResponse else { throw AssistantError.offline }
        guard (200..<300).contains(http.statusCode) else { throw AssistantError.rejected(status: http.statusCode) }

        let decoded = try JSONDecoder().decode(HeardResponse.self, from: data)
        let doubtful: [ClosedRange<Double>] = (decoded.segments ?? []).compactMap { segment in
            guard segment.count >= 5, let start = segment[0], let end = segment[1], end >= start else { return nil }
            let logprob = segment[2] ?? 0
            let noSpeech = segment[3] ?? 0
            let compression = segment[4] ?? 1
            let invented = (noSpeech > 0.6 && logprob < -0.8) || compression > 2.6 || logprob < -1.4
            return invented ? start...end : nil
        }

        let words: [TimedWord] = (decoded.words ?? []).compactMap { item in
            guard item.count >= 3,
                  let text = item[0].string?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty,
                  let start = item[1].double, let end = item[2].double, end >= start
            else { return nil }
            let middle = (start + end) / 2
            guard !doubtful.contains(where: { $0.contains(middle) }) else { return nil }
            return TimedWord(
                text: text,
                range: MediaTimeRange(start: MediaTime(seconds: start), duration: MediaTime(seconds: max(0.05, end - start)))
            )
        }
        return (words, Self.languageCode(fromWhisper: decoded.language))
    }

    private struct JudgeRequest: Encodable {
        struct Passage: Encodable {
            var id: Int
            var a: String
            var b: String
        }
        var locale: String
        var script: String
        var passages: [Passage]
    }

    private struct JudgeResponse: Decodable {
        var choices: String?
    }

    private struct Choices: Decodable {
        struct Choice: Decodable {
            var id: Int?
            var pick: String?
        }
        var choices: [Choice]?
    }

    /// Which listener heard each disputed passage right, by the server model's reading.
    ///
    /// The versions are sent as "a" (phone) and "b" (server) so the model judges the words, not
    /// the names.
    public func judgeSpeech(
        _ passages: [TranscriptPassage],
        script: String,
        localeIdentifier: String
    ) async throws -> [TranscriptPassage.ID: SpeechSource] {
        guard let endpoint else { throw AssistantError.notConfigured }
        guard !passages.isEmpty else { return [:] }

        var request = URLRequest(url: endpoint.url.appending(path: "speech"))
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(endpoint.appToken, forHTTPHeaderField: "x-cuetake-app")
        request.httpBody = try JSONEncoder().encode(
            JudgeRequest(
                locale: localeIdentifier,
                script: String(script.prefix(4000)),
                passages: passages.prefix(150).map {
                    JudgeRequest.Passage(id: $0.id, a: String($0.text(from: .device).prefix(400)), b: String($0.text(from: .cloud).prefix(400)))
                }
            )
        )

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await AssistantTransport.data(for: request)
        } catch {
            throw AssistantError.offline
        }
        guard let http = response as? HTTPURLResponse else { throw AssistantError.offline }
        guard (200..<300).contains(http.statusCode) else { throw AssistantError.rejected(status: http.statusCode) }

        guard let text = try JSONDecoder().decode(JudgeResponse.self, from: data).choices,
              let open = text.firstIndex(of: "{"), let close = text.lastIndex(of: "}"), open < close,
              let parsed = try? JSONDecoder().decode(Choices.self, from: Data(text[open...close].utf8))
        else { throw AssistantError.empty }

        var result: [TranscriptPassage.ID: SpeechSource] = [:]
        for choice in parsed.choices ?? [] {
            guard let id = choice.id else { continue }
            switch choice.pick?.lowercased() {
            case "a": result[id] = .device
            case "b": result[id] = .cloud
            default: break
            }
        }
        return result
    }
}
