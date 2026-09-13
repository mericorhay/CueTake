import Domain
import Foundation
import FoundationModels

@Generable
struct RewrittenLine {
    @Guide(description: "The new text the creator will say out loud. Same language as the original. Spoken sentences only: no quotes around it, no stage directions, no emoji, no hashtags.")
    var spoken: String
}

/// Rewrites one beat of a script on the on-device model.
///
/// The script screen's "shorter", "more energetic" and friends used to be string tricks — the
/// first sentence, an exclamation mark, sentences in reverse order — which looked like a feature
/// and produced nonsense. This asks the model, with the rest of the script as context so a
/// rewritten hook still leads into the intro that follows it.
public struct ScriptRewriter: Sendable {
    public enum Instruction: String, CaseIterable, Sendable {
        case rewrite
        case shorter
        case longer
        case moreNatural
        case moreEnergetic

        var direction: String {
            switch self {
            case .rewrite: "Say the same thing in a fresh way."
            case .shorter: "Make it noticeably shorter — cut it to its strongest sentence or two, keep the point."
            case .longer: "Make it a little longer by adding one concrete detail or example, not filler."
            case .moreNatural: "Make it sound like someone talking to a friend: contractions, plain words, no marketing voice."
            case .moreEnergetic: "Make it punchier and more energetic: short sentences, strong verbs, momentum."
            }
        }
    }

    public init() {}

    /// Whether the on-device model can be used right now.
    public static var isAvailable: Bool {
        SystemLanguageModel.default.isAvailable
    }

    private static let instructions = """
    You edit short scripts for talking-to-camera videos (Reels, TikTok, Shorts). You rewrite one beat \
    at a time. Keep the meaning, keep the language of the original, and write only what is spoken.
    """

    /// - Parameters:
    ///   - text: the beat as it is now.
    ///   - role: what the beat is for — hook, intro, main point, call to action.
    ///   - script: the whole script, for context.
    public func rewrite(
        _ text: String,
        instruction: Instruction,
        role: String,
        script: String,
        localeIdentifier: String
    ) async throws -> String {
        let session = LanguageModelSession(instructions: Self.instructions)
        let language = Locale(identifier: "en").localizedString(forIdentifier: localeIdentifier) ?? localeIdentifier
        let prompt = """
        The whole script, for context:
        \(script)

        The beat to rewrite is the \(role). Its current text:
        \(text)

        \(instruction.direction)
        Write in \(language) if the original is in \(language); otherwise keep the original's language.
        """
        let response = try await session.respond(to: prompt, generating: RewrittenLine.self)
        return response.content.spoken
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"“”"))
    }
}
