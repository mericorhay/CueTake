import Domain
import Foundation

/// Script writing and rewriting on the server, for phones without Apple Intelligence.
///
/// The on-device model is the first choice when it is there: private, free, offline. On an iPhone
/// that cannot run it, "Start with an idea" and the rewrite chips used to be dead ends; these give
/// them the same server model the editor's AI uses.
extension AssistantClient {
    private struct ScriptRequest: Encodable {
        var topic: String
        var seconds: Double
        var platform: String
        var tone: String
        var locale: String
    }

    private struct ScriptResponse: Decodable {
        var script: String?
    }

    private struct WrittenScript: Decodable {
        struct Beat: Decodable {
            var role: String?
            var title: String?
            var script: String?
            var seconds: Double?
        }
        var title: String?
        var segments: [Beat]?
    }

    public func writeScript(_ brief: ScriptBrief, localeIdentifier: String) async throws -> ScriptDraft {
        let data = try await post(
            "script",
            ScriptRequest(
                topic: brief.topic ?? "",
                seconds: brief.targetDuration.seconds,
                platform: brief.platform.rawValue,
                tone: brief.tone ?? "",
                locale: localeIdentifier
            ),
            timeout: 90
        )
        guard let text = try JSONDecoder().decode(ScriptResponse.self, from: data).script else { throw AssistantError.empty }
        return try Self.draft(from: text, fallbackTitle: brief.topic ?? "")
    }

    /// Reads a script out of what the model wrote, tolerating text around the JSON and missing fields.
    static func draft(from text: String, fallbackTitle: String) throws -> ScriptDraft {
        guard let open = text.firstIndex(of: "{"), let close = text.lastIndex(of: "}"), open < close,
              let written = try? JSONDecoder().decode(WrittenScript.self, from: Data(text[open...close].utf8))
        else { throw AssistantError.empty }

        let segments: [SegmentDraft] = (written.segments ?? []).compactMap { beat in
            let script = (beat.script ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !script.isEmpty else { return nil }
            let role: SegmentRole = switch (beat.role ?? "").lowercased() {
            case "hook": .hook
            case "intro": .intro
            case "example": .example
            case "cta", "calltoaction", "call to action": .callToAction
            default: .mainPoint
            }
            let words = Double(script.split(whereSeparator: \.isWhitespace).count)
            return SegmentDraft(
                role: role,
                title: beat.title ?? "",
                script: script,
                estimatedDuration: MediaTime(seconds: max(2, beat.seconds ?? words / 2.5))
            )
        }
        guard !segments.isEmpty else { throw AssistantError.empty }
        let title = (written.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return ScriptDraft(title: title.isEmpty ? String(fallbackTitle.prefix(40)) : title, segments: segments)
    }

    private struct RewriteRequest: Encodable {
        var text: String
        var direction: String
        var role: String
        var script: String
        var locale: String
    }

    private struct RewriteResponse: Decodable {
        var rewrite: String?
    }

    private struct Rewritten: Decodable {
        var text: String?
    }

    public func rewrite(
        _ text: String,
        direction: String,
        role: String,
        script: String,
        localeIdentifier: String
    ) async throws -> String {
        let data = try await post(
            "rewrite",
            RewriteRequest(text: text, direction: direction, role: role, script: script, locale: localeIdentifier),
            timeout: 60
        )
        guard let reply = try JSONDecoder().decode(RewriteResponse.self, from: data).rewrite else { throw AssistantError.empty }
        var result = reply
        if let open = reply.firstIndex(of: "{"), let close = reply.lastIndex(of: "}"), open < close,
           let parsed = try? JSONDecoder().decode(Rewritten.self, from: Data(reply[open...close].utf8)),
           let spoken = parsed.text {
            result = spoken
        }
        result = result
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"“”"))
        guard !result.isEmpty else { throw AssistantError.empty }
        return result
    }

    private func post(_ path: String, _ body: some Encodable, timeout: TimeInterval) async throws -> Data {
        guard let endpoint else { throw AssistantError.notConfigured }
        var request = URLRequest(url: endpoint.url.appending(path: path))
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
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
        return data
    }
}

extension ScriptRewriter.Instruction {
    /// What to ask for, in words a model understands.
    public var directionText: String { direction }
}
