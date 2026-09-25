import Foundation

/// What the creator asked the AI editor to remember about their videos, across projects:
/// "always yellow captions", "no emoji in titles", "my brand is Kahve Durağı".
///
/// Kept on the phone, sent with every AI edit, and shown in Settings where each line can be
/// deleted. Only what the creator said goes in: the AI saves a line with its `remember` tool when
/// the creator states a lasting preference, never its own guesses.
public enum AIMemory {
    static let key = "cuetake.ai.memory"
    /// Lines kept; the oldest go first.
    public static let limit = 20
    /// Characters a line may have.
    static let length = 200

    public static var facts: [String] {
        UserDefaults.standard.stringArray(forKey: key) ?? []
    }

    /// Saves a line, unless the same one is already there. Returns the line as kept.
    @discardableResult
    public static func remember(_ fact: String) -> String? {
        let line = String(fact.trimmingCharacters(in: .whitespacesAndNewlines).prefix(length))
        guard !line.isEmpty else { return nil }
        var facts = facts.filter { $0.compare(line, options: [.caseInsensitive, .diacriticInsensitive]) != .orderedSame }
        facts.append(line)
        UserDefaults.standard.set(Array(facts.suffix(limit)), forKey: key)
        return line
    }

    public static func forget(_ fact: String) {
        UserDefaults.standard.set(facts.filter { $0 != fact }, forKey: key)
    }

    public static func forgetAll() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
