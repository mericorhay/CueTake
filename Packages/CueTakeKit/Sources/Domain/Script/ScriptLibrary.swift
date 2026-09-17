import Foundation

/// What a brand sounds like, so a script written for it is written in its voice.
public struct BrandVoice: Hashable, Sendable, Codable {
    /// The brand or creator name.
    public var name: String
    /// What it is and does, in a sentence or two.
    public var about: String
    /// Who the videos are for.
    public var audience: String
    /// Phrases that belong in every script: a slogan, a sign-off.
    public var mustSay: String
    /// Words and claims to stay away from.
    public var avoid: String

    public init(name: String = "", about: String = "", audience: String = "", mustSay: String = "", avoid: String = "") {
        self.name = name
        self.about = about
        self.audience = audience
        self.mustSay = mustSay
        self.avoid = avoid
    }

    public var isEmpty: Bool {
        [name, about, audience, mustSay, avoid].allSatisfy { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    /// The voice as lines a model reads. Each field is cut short: this is context, not a document.
    public var briefText: String {
        var lines: [String] = []
        func add(_ label: String, _ value: String, limit: Int) {
            let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return }
            lines.append("\(label): \(String(text.prefix(limit)))")
        }
        add("Brand", name, limit: 80)
        add("About", about, limit: 400)
        add("Audience", audience, limit: 200)
        add("Must say", mustSay, limit: 200)
        add("Avoid", avoid, limit: 200)
        return lines.joined(separator: "\n")
    }
}

/// A script kept for reuse: a brand's standard intro, a product pitch, a weekly sign-off.
public struct SavedScript: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public var title: String
    public var text: String
    public var updatedAt: Date

    public init(id: UUID = UUID(), title: String, text: String, updatedAt: Date = .now) {
        self.id = id
        self.title = title
        self.text = text
        self.updatedAt = updatedAt
    }

    /// A title from the opening words, for a script saved without one.
    public static func title(for text: String) -> String {
        let words = ScriptText.words(in: text).prefix(5).map { ScriptText.emphasis($0).text }
        return words.joined(separator: " ")
    }
}

/// How long a short script may be. A prompter script is a minute or so of speech, not a page.
public enum ScriptBudget {
    public static let lengthChoices = [15, 30, 45, 60, 90]
    public static let maximumSeconds = 90.0

    /// Words that fit in `seconds` of natural speech in the language.
    public static func maxWords(seconds: Double, localeIdentifier: String) -> Int {
        let perMinute = SpeakingRate.wordsPerMinute(forLocaleIdentifier: localeIdentifier)
        return max(8, Int((min(seconds, maximumSeconds) * perMinute / 60).rounded()))
    }

    /// The draft cut down to the length asked for, if the writer ran long.
    ///
    /// A little over is allowed — people ask for "30 seconds" and mean roughly. Past that, middle
    /// beats go first (the hook and the call to action are what make it a video), then sentences
    /// from the end of the longest beat.
    public static func fit(_ draft: ScriptDraft, seconds: Double, localeIdentifier: String) -> ScriptDraft {
        let budget = Int((Double(maxWords(seconds: seconds, localeIdentifier: localeIdentifier)) * 1.15).rounded())
        var segments = draft.segments
        func total() -> Int { segments.reduce(0) { $0 + ScriptText.words(in: $1.script).count } }

        while total() > budget, segments.count > 2 {
            // The last middle beat.
            let middle = segments.indices.dropFirst().dropLast().last { segments[$0].role != .hook && segments[$0].role != .callToAction }
            guard let middle else { break }
            segments.remove(at: middle)
        }
        while total() > budget {
            guard let longest = segments.indices.max(by: {
                ScriptText.words(in: segments[$0].script).count < ScriptText.words(in: segments[$1].script).count
            }) else { break }
            let sentences = Self.sentences(segments[longest].script)
            if sentences.count > 1 {
                segments[longest].script = sentences.dropLast().joined(separator: " ")
            } else {
                // One long sentence: keep what fits of it.
                let over = total() - budget
                let words = ScriptText.words(in: segments[longest].script)
                let keep = max(3, words.count - over)
                guard keep < words.count else { break }
                segments[longest].script = words.prefix(keep).joined(separator: " ")
            }
        }
        let perMinute = SpeakingRate.wordsPerMinute(forLocaleIdentifier: localeIdentifier)
        for index in segments.indices {
            let words = Double(ScriptText.words(in: segments[index].script).count)
            segments[index].estimatedDuration = MediaTime(seconds: max(2, words / perMinute * 60))
        }
        return ScriptDraft(title: draft.title, segments: segments)
    }

    static func sentences(_ text: String) -> [String] {
        var result: [String] = []
        var current: [Substring] = []
        for word in ScriptText.words(in: text) {
            current.append(word)
            if ScriptText.endsSentence(word) {
                result.append(current.joined(separator: " "))
                current = []
            }
        }
        if !current.isEmpty { result.append(current.joined(separator: " ")) }
        return result
    }
}
