import Domain
import Foundation
import Observation

/// One of the user's clips, as the studio shows it. The studio does not know where media lives;
/// it knows there is a clip number three, called "IMG_4821", five seconds long.
public struct StudioClip: Identifiable, Hashable, Sendable {
    public var id: Int { slot }
    /// Counting from 1, which is what sections refer to.
    public var slot: Int
    public var name: String
    public var seconds: Double

    public init(slot: Int, name: String, seconds: Double) {
        self.slot = slot
        self.name = name
        self.seconds = seconds
    }
}

/// What the run is doing to one step.
public enum StudioStepState: Hashable, Sendable {
    case waiting
    case running
    case done
    case skipped(String)
}

public struct StudioRunSummary: Hashable, Sendable {
    public var completed: Int
    public var skipped: Int

    public init(completed: Int, skipped: Int) {
        self.completed = completed
        self.skipped = skipped
    }
}

/// Everything dragged around the studio is a string with a prefix. `String` is already
/// `Transferable`, and one payload type means one drop handler per target instead of four.
enum StudioDrag {
    static let step = "step:"
    static let section = "section:"
    static let clip = "clip:"
    static let tool = "tool:"
    static let role = "role:"
}

/// The workflow being built, and every edit that can be made to it.
///
/// Edits go through methods rather than bindings into the definition, for the same reason the
/// editor's do: a drop, a tap and an AI rewrite all change the same document, and one place that
/// decides what a legal change is keeps them from disagreeing.
@MainActor
@Observable
public final class WorkflowStudioModel {
    public var definition: WorkflowDefinition
    public var clips: [StudioClip]

    public private(set) var stepStates: [WorkflowStep.ID: StudioStepState] = [:]
    public private(set) var isRunning = false
    public private(set) var lastRunSummary: StudioRunSummary?
    public var expandedStep: WorkflowStep.ID?

    public var aiRequest = ""
    public private(set) var isAuthoring = false
    public private(set) var aiFailure: String?

    /// Bumped on every structural edit, for the haptic.
    public private(set) var editPulse = 0

    public init(definition: WorkflowDefinition, clips: [StudioClip] = []) {
        self.definition = definition
        self.clips = clips
    }

    // MARK: - Sections

    public func addSection(role: String, at index: Int? = nil) {
        let section = WorkflowSection(
            role: role,
            title: role.capitalized,
            seconds: role == "hook" || role == "cta" ? 3 : 6
        )
        let position = min(index ?? definition.sections.count, definition.sections.count)
        definition.sections.insert(section, at: position)
        touch()
    }

    public func removeSection(_ id: WorkflowSection.ID) {
        definition.sections.removeAll { $0.id == id }
        touch()
    }

    public func duplicateSection(_ id: WorkflowSection.ID) {
        guard let index = definition.sections.firstIndex(where: { $0.id == id }) else { return }
        var copy = definition.sections[index]
        copy.id = UUID()
        definition.sections.insert(copy, at: index + 1)
        touch()
    }

    /// Moves a section to where another one is. Dropping onto a card means "put it here", which
    /// is what every reorderable list on the phone has taught people.
    public func moveSection(_ id: WorkflowSection.ID, before target: WorkflowSection.ID?) {
        guard let from = definition.sections.firstIndex(where: { $0.id == id }) else { return }
        let section = definition.sections.remove(at: from)
        let to = target.flatMap { t in definition.sections.firstIndex { $0.id == t } } ?? definition.sections.count
        definition.sections.insert(section, at: to)
        touch()
    }

    public func assign(clip slot: Int?, to id: WorkflowSection.ID) {
        guard let index = definition.sections.firstIndex(where: { $0.id == id }) else { return }
        definition.sections[index].clip = slot
        // A section with footage takes the footage's length as its target, because that is the
        // length it is going to be — a target that disagrees with the clip is a number nobody uses.
        if let slot, let clip = clips.first(where: { $0.slot == slot }) {
            definition.sections[index].seconds = (clip.seconds * 10).rounded() / 10
        }
        touch()
    }

    public func updateSection(_ id: WorkflowSection.ID, _ change: (inout WorkflowSection) -> Void) {
        guard let index = definition.sections.firstIndex(where: { $0.id == id }) else { return }
        change(&definition.sections[index])
        definition.updatedAt = .now
    }

    /// Fills the empty sections with the unused clips, in order. The thing someone does with
    /// five sections and five clips nine times out of ten.
    public func autoAssignClips() {
        var unused = clips.map(\.slot).filter { slot in !definition.sections.contains { $0.clip == slot } }
        for index in definition.sections.indices where definition.sections[index].clip == nil {
            guard !unused.isEmpty else { break }
            let slot = unused.removeFirst()
            definition.sections[index].clip = slot
            if let clip = clips.first(where: { $0.slot == slot }) {
                definition.sections[index].seconds = (clip.seconds * 10).rounded() / 10
            }
        }
        touch()
    }

    public var totalSeconds: Double {
        definition.sections.reduce(0) { $0 + $1.seconds }
    }

    // MARK: - Steps

    public func addStep(type: String, before target: WorkflowStep.ID? = nil) {
        let step = WorkflowStep(kind: .make(type: type))
        let index = target.flatMap { t in definition.steps.firstIndex { $0.id == t } } ?? definition.steps.count
        definition.steps.insert(step, at: index)
        expandedStep = step.id
        touch()
    }

    public func moveStep(_ id: WorkflowStep.ID, before target: WorkflowStep.ID?) {
        guard id != target, let from = definition.steps.firstIndex(where: { $0.id == id }) else { return }
        let step = definition.steps.remove(at: from)
        let to = target.flatMap { t in definition.steps.firstIndex { $0.id == t } } ?? definition.steps.count
        definition.steps.insert(step, at: to)
        touch()
    }

    public func removeStep(_ id: WorkflowStep.ID) {
        definition.steps.removeAll { $0.id == id }
        if expandedStep == id { expandedStep = nil }
        touch()
    }

    public func toggleStep(_ id: WorkflowStep.ID) {
        guard let index = definition.steps.firstIndex(where: { $0.id == id }) else { return }
        definition.steps[index].isEnabled.toggle()
        touch()
    }

    public func updateStep(_ id: WorkflowStep.ID, kind: WorkflowStepKind) {
        guard let index = definition.steps.firstIndex(where: { $0.id == id }) else { return }
        definition.steps[index].kind = kind
        definition.updatedAt = .now
    }

    /// Order problems worth saying out loud, per step: captions before anything has listened to
    /// the footage produce nothing, and a user who builds that pipeline deserves to know why.
    public func warning(for step: WorkflowStep) -> String.LocalizationValue? {
        guard let index = definition.steps.firstIndex(where: { $0.id == step.id }) else { return nil }
        let before = definition.steps[..<index].filter(\.isEnabled).map(\.kind.typeName)

        switch step.kind {
        case .trimSilences, .cutWords, .generateCaptions:
            return before.contains("analyzeSpeech") ? nil : "studio.warning.needsSpeech"
        case .applyCaptionStyle:
            return before.contains("generateCaptions") ? nil : "studio.warning.needsCaptions"
        case .unsupported:
            return "studio.warning.unsupported"
        case .export:
            let after = definition.steps[(index + 1)...].contains { $0.isEnabled }
            return after ? "studio.warning.exportLast" : nil
        default:
            return nil
        }
    }

    // MARK: - JSON

    public var json: String {
        (try? definition.jsonString()) ?? "{}"
    }

    /// Replaces the workflow with a document. Returns false, and changes nothing, when it does
    /// not read — a half-typed edit must never wipe the workflow underneath it.
    @discardableResult
    public func apply(json: String) -> Bool {
        guard var decoded = try? WorkflowDefinition.decode(json: json) else { return false }
        // The document is this workflow, whatever id the pasted text carried. Otherwise pasting a
        // friend's workflow would silently fork a second file.
        decoded = WorkflowDefinition(
            id: definition.id,
            name: decoded.name,
            summary: decoded.summary,
            origin: decoded.origin,
            sections: decoded.sections,
            style: decoded.style,
            steps: decoded.steps,
            createdAt: definition.createdAt
        )
        definition = decoded
        stepStates = [:]
        touch()
        return true
    }

    // MARK: - AI

    public func beginAuthoring() {
        isAuthoring = true
        aiFailure = nil
    }

    public func finishAuthoring(with workflow: WorkflowDefinition?) {
        isAuthoring = false
        guard let workflow else {
            aiFailure = String(localized: "studio.ai.failed", bundle: .module)
            return
        }
        definition = workflow
        stepStates = [:]
        aiRequest = ""
        touch()
    }

    // MARK: - Run

    public func beginRun() {
        isRunning = true
        lastRunSummary = nil
        stepStates = Dictionary(uniqueKeysWithValues: definition.steps.map { ($0.id, .waiting) })
    }

    public func mark(_ id: WorkflowStep.ID, _ state: StudioStepState) {
        stepStates[id] = state
    }

    public func finishRun() {
        isRunning = false
        lastRunSummary = StudioRunSummary(
            completed: stepStates.values.filter { $0 == .done }.count,
            skipped: stepStates.values.filter {
                if case .skipped = $0 { return true }
                return false
            }.count
        )
    }

    public func state(of id: WorkflowStep.ID) -> StudioStepState? {
        stepStates[id]
    }

    private func touch() {
        definition.updatedAt = .now
        editPulse += 1
    }
}
