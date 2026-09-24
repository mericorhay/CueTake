import DesignSystem
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
    /// The video the run wrote, when it got that far.
    public var video: URL?
    /// What the workflow's API said, when it has one.
    public var delivery: StudioDeliveryResult?

    public init(completed: Int, skipped: Int, video: URL? = nil, delivery: StudioDeliveryResult? = nil) {
        self.completed = completed
        self.skipped = skipped
        self.video = video
        self.delivery = delivery
    }
}

/// How sending to a workflow's API went.
public enum StudioDeliveryResult: Hashable, Sendable {
    case sending
    case sent(status: Int)
    case failed(String)
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
    /// A frame of the first clip, as JPEG, for the preview. Nil draws a stand-in scene.
    public var previewFrame: Data?
    /// How long the open project's video is, when there is one: the scale of the preview's
    /// timeline. Without it the sections' planned lengths stand in.
    public var videoSeconds: Double?

    /// The length the timeline shows: the real video, else the outline, else half a minute.
    public var timelineSeconds: Double {
        if let videoSeconds, videoSeconds > 0.5 { return videoSeconds }
        return totalSeconds > 0.5 ? totalSeconds : 30
    }

    public private(set) var stepStates: [WorkflowStep.ID: StudioStepState] = [:]
    public private(set) var isRunning = false
    public private(set) var lastRunSummary: StudioRunSummary?
    /// A durable run found for this workflow/project. The run button becomes an explicit resume
    /// action instead of silently starting halfway through.
    public private(set) var resumableProgress: Double?
    /// The videos a "Generate video" step is making, or made on the last run.
    public var generation: GenerationBoard?
    /// True between asking a run to stop and the run noticing.
    public private(set) var isStopping = false
    public var expandedStep: WorkflowStep.ID?

    public var aiRequest = ""
    public private(set) var isAuthoring = false
    public private(set) var aiFailure: String?

    /// Bumped on every structural edit, for the haptic.
    public private(set) var editPulse = 0
    /// A word about what a running step is doing right now ("sending to your API").
    public private(set) var stepNotes: [WorkflowStep.ID: String] = [:]
    /// The connection test of the workflow's API, from the button beside its settings.
    public var deliveryTest: StudioDeliveryResult?
    /// Bumped when a change was refused — moving or removing the closing export — for a nudge.
    public private(set) var refusedPulse = 0

    public init(definition: WorkflowDefinition, clips: [StudioClip] = []) {
        self.definition = definition.withFinalExport()
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

    /// Whether a step is the closing export, which stays last and cannot be removed.
    public func isLocked(_ id: WorkflowStep.ID) -> Bool {
        definition.finalExport?.id == id
    }

    /// Where a step lands when dropped "before" a target: never after the closing export.
    private func insertionIndex(before target: WorkflowStep.ID?) -> Int {
        let end = definition.finalExport == nil ? definition.steps.count : definition.steps.count - 1
        guard let target, let index = definition.steps.firstIndex(where: { $0.id == target }) else { return end }
        return min(index, end)
    }

    public func addStep(type: String, before target: WorkflowStep.ID? = nil) {
        // There is one export and it is always there: asking for another opens it.
        if WorkflowStepKind.make(type: type).isFinalExport {
            expandedStep = definition.finalExport?.id
            refusedPulse += 1
            return
        }
        let step = WorkflowStep(kind: .make(type: type))
        definition.steps.insert(step, at: insertionIndex(before: target))
        expandedStep = step.id
        touch()
    }

    public func moveStep(_ id: WorkflowStep.ID, before target: WorkflowStep.ID?) {
        guard id != target, !isLocked(id), let from = definition.steps.firstIndex(where: { $0.id == id }) else {
            if isLocked(id) { refusedPulse += 1 }
            return
        }
        let step = definition.steps.remove(at: from)
        definition.steps.insert(step, at: insertionIndex(before: target))
        touch()
    }

    /// One place up or down, for anyone who does not drag.
    public func moveStep(_ id: WorkflowStep.ID, by offset: Int) {
        guard !isLocked(id), let from = definition.steps.firstIndex(where: { $0.id == id }) else { return }
        let last = definition.finalExport == nil ? definition.steps.count - 1 : definition.steps.count - 2
        let to = min(max(from + offset, 0), last)
        guard to != from else { return }
        let step = definition.steps.remove(at: from)
        definition.steps.insert(step, at: to)
        touch()
    }

    public func canMoveStep(_ id: WorkflowStep.ID, by offset: Int) -> Bool {
        guard !isLocked(id), let from = definition.steps.firstIndex(where: { $0.id == id }) else { return false }
        let last = definition.finalExport == nil ? definition.steps.count - 1 : definition.steps.count - 2
        let to = from + offset
        return to >= 0 && to <= last
    }

    public func removeStep(_ id: WorkflowStep.ID) {
        guard !isLocked(id) else {
            refusedPulse += 1
            return
        }
        definition.steps.removeAll { $0.id == id }
        if expandedStep == id { expandedStep = nil }
        touch()
    }

    public func toggleStep(_ id: WorkflowStep.ID) {
        guard !isLocked(id), let index = definition.steps.firstIndex(where: { $0.id == id }) else { return }
        definition.steps[index].isEnabled.toggle()
        touch()
    }

    // MARK: - Export and delivery

    /// Resolution and frame rate, set from the export step: the same numbers the style card shows.
    public func setExportFormat(resolution: VideoFormat.Resolution? = nil, frameRate: Int? = nil) {
        if let resolution { definition.style.resolution = resolution }
        if let frameRate { definition.style.frameRate = frameRate }
        if !definition.style.format.isPhysicallyPlausible { definition.style.frameRate = 30 }
        syncFinalExport()
    }

    /// Keeps the closing export saying what the style says. Called whenever the style changes.
    public func syncFinalExport() {
        let before = definition.steps
        definition.ensureFinalExport()
        if before != definition.steps { definition.updatedAt = .now }
    }

    public func updateExport(_ change: (inout ExportPreset) -> Void) {
        guard let step = definition.finalExport, case .export(var preset) = step.kind else { return }
        change(&preset)
        updateStep(step.id, kind: .export(preset))
    }

    public func updateDelivery(_ change: (inout WorkflowDelivery) -> Void) {
        updateExport { preset in
            var delivery = preset.delivery ?? WorkflowDelivery()
            change(&delivery)
            preset.delivery = delivery
        }
        deliveryTest = nil
    }

    public func note(_ text: String?, for id: WorkflowStep.ID) {
        stepNotes[id] = text
    }

    /// The seconds a step works on; nil gives it the whole video again.
    public func setRange(_ range: WorkflowTimeRange?, for id: WorkflowStep.ID) {
        guard let index = definition.steps.firstIndex(where: { $0.id == id }),
              definition.steps[index].kind.acceptsTimeRange,
              definition.steps[index].range != range
        else { return }
        definition.steps[index].range = range
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
        case .trimSilences, .cutWords, .generateCaptions, .cleanup, .stockBroll:
            return before.contains("analyzeSpeech") ? nil : "studio.warning.needsSpeech"
        case .aiEdit(let options):
            return options.instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "studio.warning.needsInstruction" : nil
        case .applyCaptionStyle:
            return before.contains("generateCaptions") ? nil : "studio.warning.needsCaptions"
        case .unsupported:
            return "studio.warning.unsupported"
        case .export(let preset):
            if let delivery = preset.delivery, delivery.isEnabled, delivery.url == nil {
                return "studio.warning.deliveryURL"
            }
            return nil
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
            variables: decoded.variables,
            steps: decoded.steps,
            createdAt: definition.createdAt
        )
        definition = decoded.withFinalExport()
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
            aiFailure = AppLocalization.string("studio.ai.failed", bundle: .module)
            return
        }
        // The AI never sees the delivery secret, and should not lose the endpoint the user set.
        var written = workflow.withFinalExport()
        if written.delivery == nil, let delivery = definition.delivery,
           let step = written.finalExport, case .export(var preset) = step.kind {
            preset.delivery = delivery
            written.steps[written.steps.count - 1].kind = .export(preset)
        }
        definition = written
        stepStates = [:]
        aiRequest = ""
        touch()
    }

    // MARK: - Run

    public func beginRun(resumingAt stepIndex: Int = 0) {
        isRunning = true
        isStopping = false
        generation = nil
        lastRunSummary = nil
        resumableProgress = nil
        stepNotes = [:]
        syncFinalExport()
        stepStates = Dictionary(uniqueKeysWithValues: definition.steps.enumerated().map { index, step in
            (step.id, index < stepIndex ? .done : .waiting)
        })
    }

    public func setResumableProgress(_ progress: Double?) {
        resumableProgress = progress
    }

    public func mark(_ id: WorkflowStep.ID, _ state: StudioStepState) {
        stepStates[id] = state
    }

    public func requestStop() {
        guard isRunning else { return }
        isStopping = true
    }

    /// How far the run is, 0…1, counting finished and skipped steps.
    public var runProgress: Double {
        let total = definition.steps.count
        guard total > 0 else { return 0 }
        let settled = stepStates.values.filter { $0 != .waiting && $0 != .running }.count
        return Double(settled) / Double(total)
    }

    public func finishRun(video: URL? = nil, delivery: StudioDeliveryResult? = nil) {
        isRunning = false
        isStopping = false
        stepNotes = [:]
        lastRunSummary = StudioRunSummary(
            completed: stepStates.values.filter { $0 == .done }.count,
            skipped: stepStates.values.filter {
                if case .skipped = $0 { return true }
                return false
            }.count,
            video: video,
            delivery: delivery
        )
    }

    public func dismissRunSummary() {
        lastRunSummary = nil
    }

    /// The delivery was sent again after the run.
    public func updateRunDelivery(_ result: StudioDeliveryResult) {
        lastRunSummary?.delivery = result
    }

    /// Steps that were skipped on the last run, with why, for the result card.
    public var skippedReasons: [(title: String, reason: String)] {
        definition.steps.compactMap { step in
            guard case .skipped(let reason)? = stepStates[step.id] else { return nil }
            return (step.kind.typeName, reason)
        }
    }

    public func state(of id: WorkflowStep.ID) -> StudioStepState? {
        stepStates[id]
    }

    private func touch() {
        definition.updatedAt = .now
        editPulse += 1
    }
}
