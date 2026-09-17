import Domain
import FoundationModels
import Foundation

/// The shape the model is asked to fill in.
///
/// Guided generation rather than "return JSON and hope": the type is the contract, so a missing
/// field or a hallucinated extra one is impossible rather than something to validate afterwards.
/// The guides are doing real work here — a model asked for "a script" writes an essay, and a
/// model told a hook is one sentence writes a hook.
@Generable
struct GeneratedScript {
    @Guide(description: "A short title for the video, at most six words.")
    var title: String

    @Guide(description: "The beats of the video in order, between three and five of them.")
    var beats: [GeneratedBeat]
}

@Generable
struct GeneratedBeat {
    @Guide(description: "One of: hook, intro, point, example, cta.")
    var role: String

    @Guide(description: "Two or three words naming this beat.")
    var title: String

    @Guide(description: "What the creator says out loud, in the language of the request. Spoken sentences, no stage directions, no emoji, no hashtags.")
    var spoken: String

    @Guide(description: "How many seconds this beat takes to say out loud.")
    var seconds: Int
}

/// Script writing on the on-device model.
///
/// On-device is not a compromise here, it is the product: no key, no per-call cost, no queue, and
/// a creator drafting ten hooks in a row costs exactly nothing. It is also the thing that makes
/// the free tier possible at all — a cloud call per idea is a bill per idea.
public struct FoundationModelsScriptWriter: ScriptWriting, ScriptSegmenting {
    public let descriptor = AIProviderDescriptor(id: "apple.foundation-models", location: .onDevice)

    public init() {}

    public func availability(for capability: AICapability, localeIdentifier: String) async -> AIAvailability {
        switch capability {
        case .scriptWriting, .scriptSegmentation:
            switch SystemLanguageModel.default.availability {
            case .available: .available
            // The distinction matters to the caller: a device that will never run this needs a
            // different answer than one that is still downloading the model.
            case .unavailable(.deviceNotEligible): .unavailable(.deviceNotEligible)
            case .unavailable(.modelNotReady): .unavailable(.modelNotReady)
            case .unavailable: .unavailable(.notConfigured)
            @unknown default: .unavailable(.notConfigured)
            }
        default:
            .unavailable(.notImplemented)
        }
    }

    // MARK: - Writing

    public func writeScript(
        _ brief: ScriptBrief,
        localeIdentifier: String
    ) -> AsyncThrowingStream<ScriptDraft, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let session = LanguageModelSession(instructions: Self.instructions)
                    let response = try await session.respond(
                        to: Self.prompt(for: brief, localeIdentifier: localeIdentifier),
                        generating: GeneratedScript.self
                    )
                    continuation.yield(Self.draft(from: response.content))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func segment(script: String, localeIdentifier: String) async throws -> [SegmentDraft] {
        let session = LanguageModelSession(instructions: Self.instructions)
        let response = try await session.respond(
            to: """
            Split this script into its beats. Keep every word the writer wrote; only decide where \
            one beat ends and the next begins. Answer in the same language as the script.

            \(script)
            """,
            generating: GeneratedScript.self
        )
        return Self.draft(from: response.content).segments
    }

    // MARK: - Prompting

    /// Instructions rather than a longer prompt: they stay in force for every turn of the session,
    /// and they are where the house style belongs — a prompt is about this video, instructions are
    /// about how this app writes.
    private static let instructions = """
    You write short-form video scripts for a single creator talking to camera.

    Write only what is said out loud. No shot descriptions, no camera directions, no emoji, no \
    hashtags, no labels like "Hook:". Short sentences, the way people actually speak.

    Always answer in the same language the request is written in.
    """

    private static func prompt(for brief: ScriptBrief, localeIdentifier: String) -> String {
        let seconds = Int(brief.targetDuration.seconds.rounded())
        let language = Locale(identifier: localeIdentifier)
            .localizedString(forLanguageCode: localeIdentifier) ?? localeIdentifier

        var lines = [
            "Write a \(seconds) second script for \(brief.platform.rawValue).",
            "Language: \(language).",
        ]
        if let topic = brief.topic, !topic.isEmpty {
            lines.append("Topic: \(topic)")
        }
        if let tone = brief.tone, !tone.isEmpty {
            lines.append("Tone: \(tone)")
        }
        let words = ScriptBudget.maxWords(seconds: brief.targetDuration.seconds, localeIdentifier: localeIdentifier)
        lines.append("At most \(words) words in total. Short and spoken, not an essay.")
        if let brand = brief.brand, !brand.isEmpty {
            lines.append("Write in this brand's voice. Use the must-say phrases naturally and never the words to avoid.")
            lines.append(brand.briefText)
        }
        return lines.joined(separator: "\n")
    }

    private static func draft(from generated: GeneratedScript) -> ScriptDraft {
        ScriptDraft(
            title: generated.title,
            segments: generated.beats.map { beat in
                SegmentDraft(
                    role: role(from: beat.role),
                    title: beat.title,
                    script: beat.spoken,
                    // Clamped rather than trusted: a model asked for seconds will occasionally
                    // answer 0, and a zero-length segment is a segment nobody can select.
                    estimatedDuration: MediaTime(seconds: Double(min(max(beat.seconds, 1), 120)))
                )
            }
        )
    }

    /// Free text to a known role. Anything unrecognised keeps its own name rather than being
    /// forced into the nearest role, which would quietly relabel the writer's own structure.
    private static func role(from raw: String) -> SegmentRole {
        switch raw.lowercased().trimmingCharacters(in: .whitespaces) {
        case "hook": .hook
        case "intro", "introduction": .intro
        case "point", "mainpoint", "main point": .mainPoint
        case "example": .example
        case "cta", "calltoaction", "call to action": .callToAction
        case let other: .custom(other)
        }
    }
}
