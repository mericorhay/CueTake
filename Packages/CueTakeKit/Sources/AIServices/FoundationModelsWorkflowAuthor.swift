import Domain
import Foundation
import FoundationModels

/// A section, as the model is allowed to write it.
@Generable
struct GeneratedSection {
    @Guide(description: "What this beat of the video is.", .anyOf(["hook", "intro", "point", "example", "cta"]))
    var role: String

    @Guide(description: "Two or three words naming the section.")
    var title: String

    @Guide(description: "How many seconds this section should last.", .range(1...90))
    var seconds: Int

    @Guide(description: "Which of the user's clips fills this section, counting from 1. Use 0 when the user did not say.")
    var clip: Int
}

/// A step, flattened to the three fields every step can be described with.
///
/// Flat on purpose. Guided generation is strongest when the shape is simple, and a union of eight
/// parameter types is the kind of shape a small model gets subtly wrong. Each tool has at most one
/// number and one word worth choosing, so that is exactly what is asked for.
@Generable
struct GeneratedStep {
    @Guide(
        description: "The tool.",
        .anyOf([
            "assembleSections", "analyzeSpeech", "cleanup", "bestTakes", "trimSilences", "cutWords", "setSpeed",
            "cleanAudio", "musicBed", "generateCaptions", "applyCaptionStyle", "addTitle", "filter",
            "trackFace", "autoZoom", "transitions", "soundDesign", "applyStyle", "stockBroll", "beatSync", "brandKit", "export",
        ])
    )
    var type: String

    @Guide(description: "The one number the tool needs: pause length in seconds for trimSilences (0.3 to 1.5), playback speed for setSpeed (0.5 to 2), music level in dB for musicBed (-30 to -3). 0 for every other tool.")
    var amount: Double

    @Guide(description: "The one word the tool needs: which section for setSpeed (all, hook, intro, point, example, cta), the caption look for applyCaptionStyle (pop, clean, karaoke), the look for filter (cinematic, warm, cool, vivid, vintage, mono), the transition for transitions (crossfade, fadeBlack, slideLeft, zoomIn), punch, push or mixed for autoZoom, subtle, normal or bold for soundDesign, the style for applyStyle (boldBusiness, vlog, podcast, ugcAd, minimal, energetic). Empty for every other tool.")
    var target: String
}

@Generable
struct GeneratedWorkflow {
    @Guide(description: "A short name for the workflow, at most four words.")
    var name: String

    @Guide(description: "One sentence saying what the workflow does.")
    var summary: String

    @Guide(description: "The structure of the video in order.", .count(1...10))
    var sections: [GeneratedSection]

    @Guide(description: "The tools to run, in the order they should run.", .count(1...16))
    var steps: [GeneratedStep]

    @Guide(description: "Caption look.", .anyOf(["pop", "clean", "karaoke"]))
    var captionPreset: String

    @Guide(description: "Where captions sit.", .anyOf(["top", "middle", "bottom"]))
    var captionPosition: String

    @Guide(description: "Frames per second.", .anyOf(["24", "30", "60", "120"]))
    var frameRate: String
}

/// Writes and rewrites workflows from what the user asks for, on the device.
///
/// The model never produces JSON text directly. It fills in a typed shape, and the app turns that
/// into the document — so a workflow from the model is valid by construction, and the JSON the
/// user then sees and edits is the app's, formatted the way every other workflow is.
public struct FoundationModelsWorkflowAuthor: Sendable {
    public init() {}

    public enum AuthorError: Error, Hashable, Sendable {
        case unavailable
    }

    public var isAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    /// A new workflow, or `current` changed as asked.
    ///
    /// - Parameter clipCount: how many clips the user has picked, so sections can be assigned to
    ///   real clips instead of to clip numbers that do not exist.
    public func author(
        request: String,
        current: WorkflowDefinition?,
        clipCount: Int
    ) async throws -> WorkflowDefinition {
        guard isAvailable else { throw AuthorError.unavailable }

        let session = LanguageModelSession(instructions: """
        You design editing workflows for short talking-to-camera videos in the CueTake app.
        Keep the user's intent; do not add tools they would not want.
        When captions are wanted, analyzeSpeech must come before generateCaptions, trimSilences \
        and cutWords. assembleSections always comes first when there are sections.
        \(WorkflowDefinition.authoringGuide)
        """)

        var prompt = "The user has \(clipCount) clip\(clipCount == 1 ? "" : "s").\n"
        if let current, let json = try? current.jsonString() {
            prompt += "This is the current workflow:\n\(json)\nChange it as the user asks, keeping everything they did not mention.\n"
        }
        prompt += "The user asks: \(request)"

        let response = try await session.respond(to: prompt, generating: GeneratedWorkflow.self)
        return Self.definition(from: response.content, replacing: current, clipCount: clipCount)
    }

    static func definition(
        from generated: GeneratedWorkflow,
        replacing current: WorkflowDefinition?,
        clipCount: Int
    ) -> WorkflowDefinition {
        let sections = generated.sections.map { section in
            WorkflowSection(
                role: section.role,
                title: section.title,
                seconds: Double(section.seconds),
                // A clip number past the end is a guess, not an assignment; left for the user.
                clip: (1...max(1, clipCount)).contains(section.clip) && clipCount > 0 ? section.clip : nil
            )
        }

        let steps = generated.steps.map { step in
            WorkflowStep(kind: Self.kind(from: step))
        }

        var style = current?.style ?? WorkflowStyle()
        style.captionPreset = generated.captionPreset
        style.captionPosition = generated.captionPosition
        style.frameRate = Int(generated.frameRate) ?? style.frameRate

        var definition = WorkflowDefinition(
            id: current?.id ?? UUID(),
            name: generated.name,
            summary: generated.summary,
            origin: .ai,
            sections: sections,
            style: style,
            variables: current?.variables ?? [:],
            steps: steps,
            createdAt: current?.createdAt ?? .now
        )
        definition.updatedAt = .now
        return definition
    }

    /// Fills the tool's defaults with the one number and word the model chose, clamped. The model
    /// is trusted with intent, not with ranges.
    static func kind(from step: GeneratedStep) -> WorkflowStepKind {
        let target = step.target.trimmingCharacters(in: .whitespaces).lowercased()

        switch WorkflowStepKind.make(type: step.type) {
        case .trimSilences(var options):
            if step.amount > 0 { options.minPause = min(max(step.amount, 0.25), 2) }
            return .trimSilences(options)
        case .setSpeed(var options):
            if step.amount > 0 { options.speed = min(max(step.amount, 0.25), 4) }
            if !target.isEmpty { options.target = target }
            return .setSpeed(options)
        case .musicBed(var options):
            if step.amount < 0 { options.levelDB = min(max(step.amount, -40), 0) }
            return .musicBed(options)
        case .applyCaptionStyle:
            return .applyCaptionStyle(presetID: ["pop", "clean", "karaoke"].contains(target) ? target : "pop")
        case .filter(var options):
            if FilterSettings.Look(rawValue: target) != nil { options.look = target }
            return .filter(options)
        case .transitions(var options):
            if ClipTransition.Kind(rawValue: target) != nil { options.kind = target }
            return .transitions(options)
        case .applyStyle(var options):
            if let style = VideoStyle(rawValue: target) { options.style = style }
            return .applyStyle(options)
        case .soundDesign(var options):
            if let intensity = SoundDesignOptions.Intensity(rawValue: target) { options.intensity = intensity }
            return .soundDesign(options)
        case .autoZoom(var options):
            if let style = ZoomStepOptions.Style(rawValue: target) { options.style = style }
            return .autoZoom(options)
        case let other:
            return other
        }
    }
}
