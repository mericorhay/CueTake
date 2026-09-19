import Domain
import Foundation
import SwiftUI

/// Sends the editor's document and an instruction to a model and gets a plan back.
public typealias AIRequester = (EditDocument, String) async throws -> EditPlan

/// The AI at work, as the studio shows it.
public struct AISession: Equatable {
    public enum Phase: Equatable {
        /// The document is with the model.
        case thinking
        /// Changes are landing one at a time.
        case applying
        case finished(applied: Int, skipped: Int)
        case failed(String)
    }

    public var instruction: String
    public var summary = ""
    public var phase: Phase = .thinking
    public var steps: [AIStepInfo] = []
    public var current = 0
    public var changeSetID: UUID?
    /// What was sent: clips and words, for the "reading" line.
    public var clips: Int
    public var words: Int
    /// 1 while the plan is made and carried out, 2 while the result is checked and finished off.
    public var pass = 1
}

public struct AIStepInfo: Identifiable, Equatable {
    public let id: Int
    public var symbol: String
    public var text: String
}

/// A stretch of the timeline an AI step is working on, drawn as a band.
public struct AIScanMark: Equatable {
    public let id: Int
    public var range: ClosedRange<Double>
}

/// One change the AI made, and what it touched.
public struct AIChangeItem: Identifiable, Equatable {
    public let id: Int
    public var symbol: String
    public var text: String
    /// Where on the finished video it happened, when it happened somewhere in particular.
    public var time: Double?
    public var targets: [AITarget]
    public var reverted = false
    /// The project just before and just after this one change. Taking back a single change restores
    /// from these rather than from the start of the run: a cut made to the second half of a clip the
    /// same run split exists only after the split, and restoring it from before the run would delete
    /// that half.
    var before: Project
    var after: Project
}

/// Everything one instruction changed, with the project as it was before and after, so any part of
/// it can be taken back — or put back — without touching what was edited since.
public struct AIChangeSet: Identifiable, Equatable {
    public let id: UUID
    public var instruction: String
    public var summary: String
    public var date: Date
    public var items: [AIChangeItem]
    var before: Project
    var after: Project

    public var activeCount: Int { items.filter { !$0.reverted }.count }
    public var isFullyReverted: Bool { items.allSatisfy(\.reverted) }
}

/// What happened when a plan was applied.
public struct EditPlanOutcome: Sendable, Equatable {
    public var applied: Int
    /// Operations that could not be carried out, by type — an unknown clip, an unknown operation.
    public var skipped: [String]
}

/// One step of a plan, ready to run against the editor.
///
/// Where it happens and what it does are worked out when the step runs, not when the plan is read:
/// by the time the fifth step runs, the first four have moved things.
struct AIStep {
    var info: AIStepInfo
    /// The plan operations folded into this step.
    var types: [String]
    var locate: (EditorModel) -> (time: Double?, scan: ClosedRange<Double>?)
    /// Nil when the step could not be carried out.
    var perform: (EditorModel) -> [AITarget]?
    /// Slow work the step needs first, such as finding a face through a clip.
    var prepare: ((EditorModel) async -> Void)? = nil
}

/// Where the pieces of a split clip went, so later steps written against the whole clip still land.
final class AISplitMap {
    /// For each clip the plan named: its pieces, by where each begins in the original footage.
    var pieces: [String: [(offset: Double, id: String)]] = [:]

    func pieces(of clip: String) -> [(offset: Double, id: String)] {
        pieces[clip] ?? [(0, clip)]
    }
}

/// The AI's hands in the studio.
///
/// A plan is carried out with the editor's own tools — a cut is `rebuild`, a speed change is
/// `updatePlayback`, a caption fix is the same call the captions screen makes — so the AI can do
/// exactly what a person could and nothing else, and every change shows on the timeline.
///
/// Run live, one step at a time: the timeline travels to where the step happens, the band shows the
/// stretch being worked on, the change lands with a spring and the thing it touched lights up. The
/// whole run is one undo step, and every change in it is listed in `aiChanges` where each can be
/// taken back on its own.
extension EditorModel {
    public var isAIDriving: Bool {
        switch aiSession?.phase {
        case .thinking, .applying: true
        default: false
        }
    }

    public func document(beatStep: Double? = nil) -> EditDocument {
        EditDocument(project: project, beatStep: beatStep)
    }

    // MARK: - Asking

    /// Sends the document, then runs whatever comes back, live.
    public func askAI(_ instruction: String, using request: @escaping AIRequester) {
        let text = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isAIDriving else { return }
        aiRequester = request
        pause()
        // Nothing stays open under the AI: a panel would show values it is about to change.
        selectedCameraMotion = nil
        selectedSubjectTrack = nil
        clearOtherSelections()

        let project = self.project
        withAnimation(.snappy(duration: 0.3)) {
            aiSession = AISession(
                instruction: text,
                clips: project.segments.count,
                words: project.segments.reduce(0) { $0 + ($1.selectedTake?.transcript?.words.count ?? 0) }
            )
        }
        aiTask?.cancel()
        aiTask = Task { [weak self] in
            do {
                // Written off the main thread: on a long video it is enough work to drop frames.
                var document = await Task.detached(priority: .userInitiated) { EditDocument(project: project) }.value
                document.videoModel = self?.aiVideoModel
                var plan = try await request(document, text)
                guard let self, !Task.isCancelled else { return }
                // A plan that would change nothing gets one more try, told why.
                if let problem = self.problem(with: plan) {
                    let second = try await request(document, text + "\n\n" + problem)
                    guard !Task.isCancelled else { return }
                    if self.problem(with: second) == nil { plan = second }
                }
                await self.drive(plan)
                await self.secondPass(after: plan, instruction: text, using: request)
                self.rememberAIRun(text)
            } catch {
                guard let self, !Task.isCancelled else { return }
                withAnimation(.snappy(duration: 0.3)) {
                    self.aiSession?.phase = .failed(
                        String(localized: "editor.ai.failed \(error.localizedDescription)", bundle: .module)
                    )
                }
            }
        }
    }

    /// Looks at the result once more and finishes what the first plan left undone.
    ///
    /// A single answer is written blind: the model plans every change against the video as it was.
    /// The second look reads the video as it now is — cuts made, captions moved, looks laid — and
    /// adds what is still missing or can be done better. An empty answer means it is done, and the
    /// run ends as it was.
    func secondPass(after plan: EditPlan, instruction: String, using request: @escaping AIRequester) async {
        guard !Task.isCancelled, case .finished(let applied, let skipped)? = aiSession?.phase, applied > 0 else { return }
        let finished = AISession.Phase.finished(applied: applied, skipped: skipped)
        withAnimation(.snappy(duration: 0.3)) {
            aiSession?.pass = 2
            aiSession?.phase = .thinking
        }
        let result = project
        var document = await Task.detached(priority: .userInitiated) { EditDocument(project: result) }.value
        document.videoModel = aiVideoModel
        let note = """

        [Second pass. You already made these changes: \(plan.summary) The document now shows the video after them, with new ids. \
        Check it against the request and add only what is still missing or clearly better: exact timing against the words, captions, \
        titles, looks, sound, rhythm. Do not repeat or undo what is done. If nothing is left, return an empty operations list.]
        """
        guard let second = try? await request(document, instruction + note), !Task.isCancelled else {
            withAnimation(.snappy(duration: 0.3)) { aiSession?.phase = finished }
            return
        }
        let resolved = second.resolvingReferences(in: project)
        guard !aiSteps(for: resolved).steps.isEmpty else {
            withAnimation(.snappy(duration: 0.3)) { aiSession?.phase = finished }
            return
        }
        await drive(second, carrying: (applied, skipped))
    }

    /// Why a plan would change nothing, written for the model; nil when it would change something.
    func problem(with plan: EditPlan) -> String? {
        let resolved = plan.resolvingReferences(in: project)
        let (steps, skipped) = aiSteps(for: resolved)
        guard steps.isEmpty else { return nil }
        if resolved.operations.isEmpty {
            return "[Your previous answer had no operations and changed nothing. The user wants this change: carry it out with operations. Return an empty list only if no operation can do it, and then say in summary which tool is missing.]"
        }
        if skipped.contains("deleteClip") {
            return "[Your previous answer changed nothing: deleting clips is not allowed. Cut parts inside clips instead (cut, removeWords, trimClip), and never remove a whole clip.]"
        }
        return "[Your previous answer changed nothing: these operations referred to things that do not exist: \(skipped.joined(separator: ", ")). Use only ids from the document: c1… for clips, k1… for captions, o1… for overlays, a1… for audio, t1… for takes.]"
    }

    /// Stops asking, or stops between two changes. What already landed stays, and stays reversible.
    public func stopAI() {
        if case .thinking = aiSession?.phase {
            aiTask?.cancel()
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { aiSession = nil }
            return
        }
        aiTask?.cancel()
    }

    public func retryAI() {
        guard let session = aiSession, let request = aiRequester, !isAIDriving else { return }
        aiSession = nil
        askAI(session.instruction, using: request)
    }

    public func dismissAISession() {
        guard !isAIDriving else { return }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { aiSession = nil }
    }

    // MARK: - Memory

    /// The session the AI is in, for the composer.
    public var aiSessionNumber: Int { max(project.aiConversations.count, 1) }
    public var aiSessionTurns: [AITurn] { project.currentAIConversation?.turns ?? [] }

    /// A clean slate: the AI no longer sees earlier requests of this project.
    public func startNewAISession() {
        project.startAIConversation()
    }

    /// Writes what this run did into the project's AI memory.
    func rememberAIRun(_ instruction: String) {
        guard let session = aiSession else { return }
        // Both passes of this run are the newest change sets, under the same request.
        let changed = session.changeSetID == nil
            ? []
            : aiChanges.prefix(2).filter { $0.instruction == instruction }.reversed().flatMap { $0.items.map(\.text) }
        let summary: String
        switch session.phase {
        case .failed(let reason): summary = reason
        default: summary = session.summary
        }
        project.remember(AITurn(instruction: instruction, summary: summary, changes: changed))
    }

    // MARK: - Running

    func drive(_ original: EditPlan, carrying earlier: (applied: Int, skipped: Int) = (0, 0)) async {
        let plan = original.resolvingReferences(in: project)
        let (steps, skipped) = aiSteps(for: plan)
        guard !steps.isEmpty else {
            withAnimation(.snappy(duration: 0.3)) {
                aiSession?.phase = .failed(
                    plan.summary.isEmpty
                        ? String(localized: "editor.ai.nothing", bundle: .module)
                        : String(localized: "editor.ai.nothingDone \(plan.summary)", bundle: .module)
                )
            }
            return
        }
        // About six seconds for the whole run, however many changes: slow enough to follow a few,
        // fast enough that thirty do not become a wait.
        let pace = min(1.0, max(0.28, 6.0 / Double(steps.count)))

        let before = project
        record("editor.change.ai", symbol: "sparkles")
        let entry = past.last?.entry.id
        isApplyingPlan = true

        withAnimation(.spring(response: 0.5, dampingFraction: 0.82)) {
            let before = aiSession?.summary ?? ""
            aiSession?.summary = earlier.applied > 0 && !before.isEmpty ? before + " " + plan.summary : plan.summary
            aiSession?.steps = steps.map(\.info)
            aiSession?.current = 0
            aiSession?.phase = .applying
        }

        var items: [AIChangeItem] = []
        var applied = 0
        var skippedCount = skipped.count

        for (n, step) in steps.enumerated() {
            if Task.isCancelled { break }
            withAnimation(.snappy) { aiSession?.current = n }

            // Go to where it happens first, and hold for a beat, so the eye is there when it lands.
            let place = step.locate(self)
            if let time = place.time { seek(to: min(max(0, time), duration)) }
            if let scan = place.scan { aiScan = AIScanMark(id: (aiScan?.id ?? 0) + 1, range: scan) }
            if place.time != nil {
                try? await Task.sleep(for: .seconds(pace * 0.4))
            }
            if Task.isCancelled { break }
            if let prepare = step.prepare {
                await prepare(self)
                if Task.isCancelled { break }
            }

            let stepBefore = project
            let targets = withAnimation(.snappy(duration: 0.3)) {
                let touched = step.perform(self)
                project.updatedAt = .now
                // The tools select what they make; mid-run that would open a panel over the timeline.
                inspectedSegment = nil
                selectedOverlay = nil
                selectedEffect = nil
                selectedVideoLayer = nil
                return touched
            }
            guard let targets else {
                skippedCount += step.types.count
                continue
            }
            applied += step.types.count
            items.append(AIChangeItem(
                id: n, symbol: step.info.symbol, text: step.info.text, time: place.time, targets: targets,
                before: stepBefore, after: project
            ))

            // A moment for anything new to appear before it is lit, or it would appear already lit.
            try? await Task.sleep(for: .milliseconds(40))
            aiBeat += 1
            glow(targets)
            try? await Task.sleep(for: .seconds(pace * 0.6))
        }

        isApplyingPlan = false
        inspectedSegment = nil
        selectedOverlay = nil
        seek(to: min(playhead, duration))

        guard !items.isEmpty else {
            if past.last?.entry.id == entry { past.removeLast() }
            withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                if Task.isCancelled {
                    // Stopped before the first change landed: nothing to report.
                    aiSession = nil
                } else if earlier.applied > 0 {
                    aiSession?.phase = .finished(applied: earlier.applied, skipped: earlier.skipped)
                } else {
                    aiSession?.phase = .failed(String(localized: "editor.ai.nothing", bundle: .module))
                }
            }
            return
        }

        let set = AIChangeSet(
            id: UUID(),
            instruction: aiSession?.instruction ?? "",
            summary: plan.summary,
            date: .now,
            items: items,
            before: before,
            after: project
        )
        aiChanges.insert(set, at: 0)
        withAnimation(.spring(response: 0.5, dampingFraction: 0.72)) {
            aiSession?.changeSetID = set.id
            aiSession?.phase = .finished(applied: applied + earlier.applied, skipped: skippedCount + earlier.skipped)
        }
    }

    /// Carries out a whole plan at once, as one undoable step. The same steps as the live run.
    @discardableResult
    public func apply(_ original: EditPlan) -> EditPlanOutcome {
        let plan = original.resolvingReferences(in: project)
        let (steps, skipped) = aiSteps(for: plan)
        let before = project
        record("editor.change.ai", symbol: "sparkles")
        isApplyingPlan = true
        defer { isApplyingPlan = false }

        var applied = 0
        var skippedTypes = skipped
        var items: [AIChangeItem] = []
        for (n, step) in steps.enumerated() {
            let stepBefore = project
            guard let targets = step.perform(self) else {
                skippedTypes.append(contentsOf: step.types)
                continue
            }
            applied += step.types.count
            items.append(AIChangeItem(
                id: n, symbol: step.info.symbol, text: step.info.text, time: nil, targets: targets,
                before: stepBefore, after: project
            ))
        }
        inspectedSegment = nil
        selectedOverlay = nil

        project.updatedAt = .now
        seek(to: min(playhead, duration))
        if !items.isEmpty {
            aiChanges.insert(
                AIChangeSet(id: UUID(), instruction: "", summary: plan.summary, date: .now, items: items, before: before, after: project),
                at: 0
            )
        }
        return EditPlanOutcome(applied: applied, skipped: skippedTypes)
    }

    // MARK: - Light

    func glow(_ targets: [AITarget]) {
        for target in targets {
            aiGlow[target, default: 0] += 1
            if target == .clipOrder {
                for segment in project.segments { aiGlow[.clip(segment.id), default: 0] += 1 }
            }
        }
    }

    public func glowToken(_ target: AITarget) -> Int {
        aiGlow[target] ?? 0
    }

    /// The captions' light: the look, the window, or the captions of the clip under the playhead.
    public var captionGlowToken: Int {
        let clip = segmentAtPlayhead.map { glowToken(.captions(project.segments[$0.index].id)) } ?? 0
        return glowToken(.captionStyle) + glowToken(.captionWindow) + clip
    }

    /// Whether a change the AI made to this is still in place.
    public func isAITouched(_ target: AITarget) -> Bool {
        aiChanges.contains { set in set.items.contains { !$0.reverted && $0.targets.contains(target) } }
    }

    // MARK: - Taking back

    public func revertAIChange(_ itemID: Int, in setID: UUID) {
        setAIChanges([itemID], in: setID, reverted: true)
    }

    public func reapplyAIChange(_ itemID: Int, in setID: UUID) {
        setAIChanges([itemID], in: setID, reverted: false)
    }

    public func revertAIChangeSet(_ setID: UUID) {
        guard let set = aiChanges.first(where: { $0.id == setID }) else { return }
        setAIChanges(set.items.map(\.id), in: setID, reverted: true)
    }

    public func reapplyAIChangeSet(_ setID: UUID) {
        guard let set = aiChanges.first(where: { $0.id == setID }) else { return }
        setAIChanges(set.items.map(\.id), in: setID, reverted: false)
    }

    /// After undo or redo: marks each AI change by whether what it touched now looks as it did
    /// before it or after it. Anything that matches neither — edited by hand since — keeps its mark.
    func reconcileAIChanges() {
        for s in aiChanges.indices {
            for i in aiChanges[s].items.indices {
                let item = aiChanges[s].items[i]
                if project.matches(item.targets, in: item.after) {
                    aiChanges[s].items[i].reverted = false
                } else if project.matches(item.targets, in: item.before)
                            || project.matches(item.targets, in: aiChanges[s].before) {
                    aiChanges[s].items[i].reverted = true
                }
            }
        }
    }

    /// Goes to a change and lights it again.
    public func showAIChange(_ item: AIChangeItem) {
        if let time = item.time { seek(to: min(max(0, time), duration)) }
        aiBeat += 1
        glow(item.targets)
    }

    /// Puts the touched things back as they were before the change (or after it, to re-apply),
    /// leaving everything else — including later edits to other things — as it is now.
    private func setAIChanges(_ itemIDs: [Int], in setID: UUID, reverted: Bool) {
        guard !isAIDriving, let s = aiChanges.firstIndex(where: { $0.id == setID }) else { return }
        let indices = aiChanges[s].items.indices.filter {
            itemIDs.contains(aiChanges[s].items[$0].id) && aiChanges[s].items[$0].reverted != reverted
        }
        guard !indices.isEmpty else { return }
        let targets = indices.flatMap { aiChanges[s].items[$0].targets }

        if reverted {
            record("editor.change.aiRevert", symbol: "arrow.uturn.backward")
        } else {
            record("editor.change.aiReapply", symbol: "sparkles")
        }
        // One change: its own moment. Several: the whole run, whose before and after hold them all.
        let source: Project
        if indices.count == 1 {
            let item = aiChanges[s].items[indices[0]]
            source = reverted ? item.before : item.after
        } else {
            source = reverted ? aiChanges[s].before : aiChanges[s].after
        }
        adopt(project.restoring(targets, from: source))
        for index in indices { aiChanges[s].items[index].reverted = reverted }

        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(60))
            self?.aiBeat += 1
            self?.glow(targets)
        }
    }

    // MARK: - Plan into steps

    func index(ofClip id: String) -> Int? {
        project.segments.firstIndex { $0.id.uuidString == id }
    }

    /// A moment of a clip's footage, on the finished video.
    func timelineSeconds(clip index: Int, footage seconds: Double) -> Double {
        let segment = project.segments[index]
        let offset = segment.playback.freeze == nil ? segment.playback.timelineSeconds(forSource: max(0, seconds)) : 0
        return start(at: index) + min(segment.barWeight, offset)
    }

    private func clipRange(_ index: Int) -> ClosedRange<Double> {
        let begin = start(at: index)
        return begin...(begin + project.segments[index].barWeight)
    }

    private func caption(_ id: String) -> (segment: Int, cue: UUID)? {
        guard let uuid = UUID(uuidString: id),
              let segment = project.segments.firstIndex(where: { $0.captions.contains { $0.id == uuid } })
        else { return nil }
        return (segment, uuid)
    }

    private func captionPlace(_ id: String) -> (time: Double?, scan: ClosedRange<Double>?) {
        guard let uuid = UUID(uuidString: id), let cue = project.captionCues.first(where: { $0.id == uuid }) else {
            return (nil, nil)
        }
        let start = cue.range.start.seconds
        return (start + min(0.1, cue.range.duration.seconds / 2), start...cue.range.end.seconds)
    }

    private func overlayPlace(_ id: String) -> (time: Double?, scan: ClosedRange<Double>?) {
        guard let overlay = project.overlays.first(where: { $0.id.uuidString == id }) else { return (nil, nil) }
        let start = overlay.start.seconds
        let end = start + overlay.duration.seconds
        return (start + min(0.3, overlay.duration.seconds / 2), start...end)
    }

    /// The plan as steps in a safe order, and the operations that cannot be run at all.
    ///
    /// Settings first — the look, captions, sound, overlays — because they are addressed by ids a
    /// cut can replace. Then splits, then speed, then footage, then deletions and order last, so
    /// nothing is looked for after something else has removed it.
    func aiSteps(for plan: EditPlan) -> (steps: [AIStep], skipped: [String]) {
        var steps: [AIStep] = []
        var skipped: [String] = []
        let splits = AISplitMap()
        let ops = plan.operations

        func add(_ symbol: String, _ text: String, _ op: EditPlan.Operation,
                 locate: @escaping (EditorModel) -> (time: Double?, scan: ClosedRange<Double>?) = { _ in (nil, nil) },
                 perform: @escaping (EditorModel) -> [AITarget]?) {
            steps.append(AIStep(info: AIStepInfo(id: steps.count, symbol: symbol, text: text), types: [op.type], locate: locate, perform: perform))
        }

        for op in ops {
            if case .unknown(let type) = op { skipped.append(type) }
        }

        // Title
        for op in ops {
            guard case .setTitle(let title) = op else { continue }
            add("character.cursor.ibeam", L("editor.ai.op.title \(title)"), op) { m in
                let clean = String(title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
                guard !clean.isEmpty else { return nil }
                m.project.title = clean
                return [.title]
            }
        }

        // Names, scripts and takes — before anything that reads a clip's words
        for op in ops {
            let clipStart: (String) -> (EditorModel) -> (time: Double?, scan: ClosedRange<Double>?) = { clip in
                { m in
                    guard let i = m.index(ofClip: clip) else { return (nil, nil) }
                    return (m.start(at: i) + 0.05, m.clipRange(i))
                }
            }
            switch op {
            case .renameClip(let clip, let title):
                guard index(ofClip: clip) != nil else { skipped.append(op.type); continue }
                add("tag", L("editor.ai.op.rename \(clipNumber(clip)) \(title)"), op, locate: clipStart(clip)) { m in
                    guard let i = m.index(ofClip: clip) else { return nil }
                    m.project.segments[i].title = String(title.prefix(60))
                    return [.clip(m.project.segments[i].id)]
                }
            case .setRole(let clip, let name):
                guard index(ofClip: clip) != nil, let role = SegmentRole(documentName: name) else {
                    skipped.append(op.type)
                    continue
                }
                add("sparkles", L("editor.ai.op.role \(clipNumber(clip)) \(role.displayLabel)"), op, locate: clipStart(clip)) { m in
                    guard let i = m.index(ofClip: clip), m.project.segments[i].role != role else { return nil }
                    m.project.segments[i].role = role
                    m.project.segments[i].metadata["roleAssignment"] = "ai"
                    return [.clip(m.project.segments[i].id)]
                }
            case .setScript(let clip, let text):
                guard index(ofClip: clip) != nil else { skipped.append(op.type); continue }
                add("text.alignleft", L("editor.ai.op.script \(clipNumber(clip))"), op, locate: clipStart(clip)) { m in
                    guard let i = m.index(ofClip: clip) else { return nil }
                    m.project.segments[i].script = text
                    return [.clip(m.project.segments[i].id)]
                }
            case .selectTake(let clip, let take):
                guard let i = index(ofClip: clip),
                      let takeID = UUID(uuidString: take),
                      project.segments[i].takes.contains(where: { $0.id == takeID })
                else { skipped.append(op.type); continue }
                add("film.stack", L("editor.ai.op.take \(clipNumber(clip))"), op, locate: clipStart(clip)) { m in
                    guard let i = m.index(ofClip: clip) else { return nil }
                    m.selectTake(takeID, at: i)
                    return [.clip(m.project.segments[i].id)]
                }
            default:
                continue
            }
        }

        // Individual captions — before the look, whose words-per-caption can give every cue a new id
        for op in ops {
            // Checked now, so a plan pointing at captions that do not exist is known to do nothing.
            switch op {
            case .setCaptionText(let id, _), .captionTiming(let id, _, _), .splitCaption(let id), .mergeCaption(let id), .removeCaption(let id):
                if caption(id) == nil { skipped.append(op.type); continue }
            default:
                break
            }
            switch op {
            case .shiftCaptions(let clip, let by):
                if let clip, index(ofClip: clip) == nil { skipped.append(op.type); continue }
                add("arrow.left.and.right", L("editor.ai.op.shiftCaptions \(Self.seconds(by))"), op) { m in
                    var indices = Array(m.project.segments.indices)
                    if let clip {
                        guard let i = m.index(ofClip: clip) else { return nil }
                        indices = [i]
                    }
                    var touched: [AITarget] = []
                    for i in indices {
                        let length = m.project.segments[i].sourceSeconds
                        m.project.segments[i].captions = m.project.segments[i].captions.compactMap { cue in
                            let start = max(0, cue.range.start.seconds + by)
                            let end = min(length, cue.range.end.seconds + by)
                            guard end - start >= Segment.shortestCaption else { return nil }
                            var moved = cue
                            moved.range = MediaTimeRange(start: MediaTime(seconds: start), duration: MediaTime(seconds: end - start))
                            moved.isUserEdited = true
                            return moved
                        }
                        touched.append(.captions(m.project.segments[i].id))
                    }
                    return touched.isEmpty ? nil : touched
                }
            case .setCaptionText(let id, let text):
                add("text.bubble", L("editor.ai.op.caption \(text)"), op, locate: { $0.captionPlace(id) }) { m in
                    guard let found = m.caption(id) else { return nil }
                    m.project.segments[found.segment].setCaptionText(found.cue, to: text)
                    return [.captions(m.project.segments[found.segment].id)]
                }
            case .captionTiming(let id, let start, let end):
                add("timer", L("editor.ai.op.captionTiming \(captionText(id))"), op, locate: { $0.captionPlace(id) }) { m in
                    guard let found = m.caption(id),
                          let cue = m.project.segments[found.segment].captions.first(where: { $0.id == found.cue })
                    else { return nil }
                    let deltaStart = start.map { $0 - cue.range.start.seconds } ?? 0
                    let deltaEnd = end.map { $0 - cue.range.end.seconds } ?? 0
                    m.project.segments[found.segment].nudgeCaption(found.cue, start: deltaStart, end: deltaEnd)
                    return [.captions(m.project.segments[found.segment].id)]
                }
            case .splitCaption(let id):
                add("rectangle.split.2x1", L("editor.ai.op.captionSplit \(captionText(id))"), op, locate: { $0.captionPlace(id) }) { m in
                    guard let found = m.caption(id), m.project.segments[found.segment].canSplitCaption(found.cue) else { return nil }
                    m.project.segments[found.segment].splitCaption(found.cue)
                    return [.captions(m.project.segments[found.segment].id)]
                }
            case .mergeCaption(let id):
                add("arrow.trianglehead.merge", L("editor.ai.op.captionMerge \(captionText(id))"), op, locate: { $0.captionPlace(id) }) { m in
                    guard let found = m.caption(id), m.project.segments[found.segment].canMergeCaption(found.cue) else { return nil }
                    m.project.segments[found.segment].mergeCaptionWithNext(found.cue)
                    return [.captions(m.project.segments[found.segment].id)]
                }
            case .removeCaption(let id):
                add("text.badge.minus", L("editor.ai.op.captionRemove \(captionText(id))"), op, locate: { $0.captionPlace(id) }) { m in
                    guard let found = m.caption(id) else { return nil }
                    m.project.segments[found.segment].removeCaption(found.cue)
                    return [.captions(m.project.segments[found.segment].id)]
                }
            default:
                continue
            }
        }

        // Caption look and window
        for op in ops {
            switch op {
            case .captionStyle(let preset, let position):
                add("captions.bubble", L("editor.ai.op.style \(preset)"), op) { m in
                    m.applyCaptionLook(EditPlan.CaptionLook(preset: preset, position: position))
                }
            case .captionLook(let look):
                add("textformat.size", L("editor.ai.op.look"), op) { m in
                    m.applyCaptionLook(look)
                }
            case .captionWindow(let from, let to):
                let text = from == nil && to == nil
                    ? L("editor.ai.op.windowAll")
                    : L("editor.ai.op.window \(Self.seconds(from ?? 0)) \(Self.seconds(to ?? duration))")
                add("clock.badge", text, op, locate: { m in
                    guard from != nil || to != nil else { return (nil, nil) }
                    let a = max(0, from ?? 0), b = min(m.duration, to ?? m.duration)
                    return (a, a...max(a, b))
                }) { m in
                    guard from != nil || to != nil else {
                        m.project.captionWindow = nil
                        return [.captionWindow]
                    }
                    let a = max(0, from ?? 0), b = min(m.duration, to ?? m.duration)
                    guard b - a >= 0.2 else { return nil }
                    m.project.captionWindow = MediaTimeRange(start: MediaTime(seconds: a), duration: MediaTime(seconds: b - a))
                    return [.captionWindow]
                }
            default:
                continue
            }
        }

        // Voice
        for op in ops {
            switch op {
            case .voiceCleanup(let on):
                add("waveform.and.person.filled", on ? L("editor.ai.op.voiceOn") : L("editor.ai.op.voiceOff"), op) { m in
                    m.setVoiceEffects(AudioEffects(noiseReduction: on, voiceEnhance: on, deRumble: on))
                    return [.voice]
                }
            case .voiceEffects(let noise, let enhance, let rumble):
                add("waveform.and.person.filled", L("editor.ai.op.voice"), op) { m in
                    var effects = m.project.voiceEffects
                    if let noise { effects.noiseReduction = noise }
                    if let enhance { effects.voiceEnhance = enhance }
                    if let rumble { effects.deRumble = rumble }
                    m.setVoiceEffects(effects)
                    return [.voice]
                }
            default:
                continue
            }
        }

        // Sound
        for op in ops {
            switch op {
            case .setMusicLevel(let id, _), .updateAudio(let id, _), .removeAudio(let id):
                if !project.audio.contains(where: { $0.id.uuidString == id }) { skipped.append(op.type); continue }
            default:
                break
            }
            switch op {
            case .setMusicLevel(let id, let gain):
                add("music.note", L("editor.ai.op.music \(String(format: "%.0f", gain))"), op, locate: { $0.audioPlace(id) }) { m in
                    guard let uuid = UUID(uuidString: id), m.project.audio.contains(where: { $0.id == uuid }) else { return nil }
                    m.updateAudio(uuid) { $0.setDecibels(gain) }
                    return [.audio(uuid)]
                }
            case .updateAudio(let id, let patch):
                add("slider.horizontal.3", L("editor.ai.op.audio \(audioName(id))"), op, locate: { $0.audioPlace(id) }) { m in
                    guard let uuid = UUID(uuidString: id), m.project.audio.contains(where: { $0.id == uuid }) else { return nil }
                    m.updateAudio(uuid) { clip in
                        if let gain = patch.gainDb { clip.setDecibels(gain) }
                        if let fade = patch.fadeIn { clip.fadeIn = MediaTime(seconds: min(max(0, fade), 10)) }
                        if let fade = patch.fadeOut { clip.fadeOut = MediaTime(seconds: min(max(0, fade), 10)) }
                        if let start = patch.start { clip.start = MediaTime(seconds: max(0, start)) }
                        if let muted = patch.muted { clip.isMuted = muted }
                        if let ducks = patch.ducksUnderVoice { clip.ducksUnderVoice = ducks }
                    }
                    return [.audio(uuid)]
                }
            case .removeAudio(let id):
                add("speaker.slash", L("editor.ai.op.removeAudio \(audioName(id))"), op, locate: { $0.audioPlace(id) }) { m in
                    guard let uuid = UUID(uuidString: id), m.project.audio.contains(where: { $0.id == uuid }) else { return nil }
                    m.removeAudio(uuid)
                    return [.audio(uuid)]
                }
            default:
                continue
            }
        }

        // Text and pictures over the video
        for op in ops {
            switch op {
            case .updateOverlay(let id, _), .removeOverlay(let id):
                if !project.overlays.contains(where: { $0.id.uuidString == id }) { skipped.append(op.type); continue }
            case .editTemplate(let id, _):
                if !project.overlays.contains(where: { $0.id.uuidString == id && $0.template != nil }) { skipped.append(op.type); continue }
            case .addTemplate(let request):
                if AdTemplate.match(request) == nil { skipped.append(op.type); continue }
            default:
                break
            }
            switch op {
            case .addText(let patch):
                let id = UUID()
                let here = playhead
                add("textformat", L("editor.ai.op.addText \(patch.text ?? "")"), op, locate: { m in
                    let start = max(0, patch.start ?? here)
                    let length = patch.duration ?? patch.end.map { $0 - start } ?? 3
                    return (start + min(0.3, max(0, length) / 2), start...(start + max(Overlay.shortest, length)))
                }) { m in
                    var overlay = Overlay(
                        id: id,
                        content: .text(OverlayText(text: patch.text ?? "")),
                        start: MediaTime(seconds: max(0, patch.start ?? here)),
                        transform: OverlayTransform(y: 0.3),
                        animation: .pop
                    )
                    Self.apply(patch, to: &overlay)
                    m.project.overlays.append(overlay)
                    // Through the one door every overlay edit uses, for its limits.
                    m.updateOverlay(id) { _ in }
                    return [.overlay(id)]
                }
            case .updateOverlay(let id, let patch):
                add("slider.horizontal.below.rectangle", L("editor.ai.op.updateOverlay \(overlayName(id))"), op, locate: { m in
                    if let start = patch.start { return (start + 0.1, nil) }
                    return m.overlayPlace(id)
                }) { m in
                    guard let uuid = UUID(uuidString: id), m.project.overlays.contains(where: { $0.id == uuid }) else { return nil }
                    m.updateOverlay(uuid, coalescing: "ai") { Self.apply(patch, to: &$0) }
                    return [.overlay(uuid)]
                }
            case .duplicateOverlay(let id, let start):
                guard let uuid = UUID(uuidString: id), project.overlays.contains(where: { $0.id == uuid }) else {
                    skipped.append(op.type); continue
                }
                let copyID = UUID()
                add("plus.square.on.square", L("editor.ai.op.duplicateOverlay \(overlayName(id))"), op, locate: { m in
                    let at = start ?? m.project.overlays.first(where: { $0.id == uuid })?.start.seconds ?? 0
                    return (at + 0.2, nil)
                }) { m in
                    guard let original = m.project.overlays.first(where: { $0.id == uuid }) else { return nil }
                    var copy = original
                    copy.id = copyID
                    if let start {
                        copy.start = MediaTime(seconds: max(0, start))
                    } else {
                        copy.transform.y = min(0.95, copy.transform.y + 0.08)
                    }
                    m.project.overlays.append(copy)
                    if let image = m.overlayImages[uuid] { m.overlayImages[copyID] = image }
                    return [.overlay(copyID)]
                }
            case .addTemplate(let request):
                let id = UUID()
                let here = playhead
                add("sparkles.rectangle.stack", describe(op), op, locate: { _ in
                    let start = max(0, request.start ?? here)
                    let length = request.duration ?? request.end.map { $0 - start } ?? 4
                    return (start + min(0.3, max(0, length) / 2), start...(start + max(Overlay.shortest, length)))
                }) { m in
                    m.aiAddTemplate(request, id: id, at: here)
                }
            case .editTemplate(let id, let request):
                add("character.cursor.ibeam", describe(op), op, locate: { $0.overlayPlace(id) }) { m in
                    guard let uuid = UUID(uuidString: id) else { return nil }
                    return m.aiEditTemplate(uuid, request)
                }
            case .removeOverlay(let id):
                add("rectangle.badge.minus", L("editor.ai.op.removeOverlay \(overlayName(id))"), op, locate: { $0.overlayPlace(id) }) { m in
                    guard let uuid = UUID(uuidString: id), m.project.overlays.contains(where: { $0.id == uuid }) else { return nil }
                    m.removeOverlay(uuid)
                    return [.overlay(uuid)]
                }
            default:
                continue
            }
        }

        // Splits
        for op in ops {
            guard case .splitClip(let clip, let at) = op else { continue }
            guard index(ofClip: clip) != nil else { skipped.append(op.type); continue }
            add("scissors", L("editor.ai.op.split \(clipNumber(clip)) \(Self.seconds(at))"), op, locate: { m in
                guard let i = m.index(ofClip: clip) else { return (nil, nil) }
                return (m.timelineSeconds(clip: i, footage: at), nil)
            }) { m in
                var pieces = splits.pieces(of: clip)
                guard let p = pieces.lastIndex(where: { $0.offset <= at }),
                      let i = m.index(ofClip: pieces[p].id)
                else { return nil }
                let local = at - pieces[p].offset
                let segment = m.project.segments[i]
                guard local > 0.15, local < segment.sourceSeconds - 0.15 else { return nil }
                let count = m.project.segments.count
                m.seek(to: m.start(at: i) + segment.playback.timelineSeconds(forSource: local))
                m.splitAtPlayhead(snapToWords: false)
                guard m.project.segments.count == count + 1 else { return nil }
                pieces.insert((at, m.project.segments[i + 1].id.uuidString), at: p + 1)
                splits.pieces[clip] = pieces
                return [.clip(m.project.segments[i].id), .clip(m.project.segments[i + 1].id)]
            }
        }

        // Speed and direction — for every piece of the clip
        for op in ops {
            let clip: String
            let symbol: String
            let change: (inout ClipPlayback) -> Void
            switch op {
            case .setSpeed(let id, let speed):
                clip = id; symbol = "gauge.with.dots.needle.67percent"
                change = { $0.speed = speed }
            case .reverse(let id, let on):
                clip = id; symbol = "backward.fill"
                change = { $0.isReversed = on }
            default:
                continue
            }
            guard index(ofClip: clip) != nil else { skipped.append(op.type); continue }
            add(symbol, describe(op), op, locate: { m in
                guard let i = m.index(ofClip: clip) else { return (nil, nil) }
                return (m.start(at: i) + 0.05, m.clipRange(i))
            }) { m in
                var targets: [AITarget] = []
                for piece in splits.pieces(of: clip) {
                    guard let i = m.index(ofClip: piece.id) else { continue }
                    m.updatePlayback(at: i, change)
                    targets.append(.clip(m.project.segments[i].id))
                }
                return targets.isEmpty ? nil : targets
            }
        }

        // Camera: moves and face tracking. Before any cut, because their times are the
        // document's; stored in source time, they then stay on their frames through the cuts.
        for op in ops {
            switch op {
            case .cameraMove(let request):
                if let move = request.move, UUID(uuidString: move) == nil { skipped.append(op.type); continue }
                add("plus.magnifyingglass", describe(op), op, locate: { m in
                    if let at = request.at { return (at + 0.05, at...(request.to ?? at + 1)) }
                    if let move = request.move, let id = UUID(uuidString: move),
                       let range = m.timelineRange(ofCameraMotion: id) {
                        return (range.lowerBound + 0.05, range)
                    }
                    return (nil, nil)
                }) { m in
                    m.aiCameraMove(request)
                }
            case .removeCameraMove(let move):
                guard let id = UUID(uuidString: move) else { skipped.append(op.type); continue }
                add("minus.magnifyingglass", describe(op), op, locate: { m in
                    guard let range = m.timelineRange(ofCameraMotion: id) else { return (nil, nil) }
                    return (range.lowerBound + 0.05, range)
                }) { m in
                    guard let recording = m.project.recordings.first(where: { $0.cameraMotions?.contains { $0.id == id } == true })
                    else { return nil }
                    m.removeCameraMotion(id)
                    return [.recording(recording.id)]
                }
            case .trackFace(let clip, let closeness):
                if let clip, index(ofClip: clip) == nil { skipped.append(op.type); continue }
                let box = AIFaceTrackBox()
                steps.append(AIStep(
                    info: AIStepInfo(id: steps.count, symbol: "scope", text: describe(op)),
                    types: [op.type],
                    locate: { m in
                        guard let clip, let i = m.index(ofClip: clip) else { return (nil, nil) }
                        return (m.start(at: i) + 0.05, m.timelineRange(ofSegmentAt: i))
                    },
                    perform: { m in m.aiApplyFaceTracks(box.found) },
                    prepare: { m in
                        box.found = await m.aiFindFaces(in: m.aiTrackClips(clip), closeness: closeness ?? 0.12)
                    }
                ))
            case .removeTrack(let clip):
                if let clip, index(ofClip: clip) == nil { skipped.append(op.type); continue }
                add("scope", describe(op), op) { m in m.aiRemoveTracks(clip) }
            case .transition(let clip, let kindName, let seconds):
                guard let kind = ClipTransition.Kind(loose: kindName) else { skipped.append(op.type); continue }
                if let clip, index(ofClip: clip) == nil { skipped.append(op.type); continue }
                add("square.on.square.intersection.dashed", describe(op), op, locate: { m in
                    guard let clip, let i = m.index(ofClip: clip) else { return (nil, nil) }
                    let cut = m.start(at: i) + m.project.segments[i].barWeight
                    return (cut - 0.3, (cut - 0.5)...(cut + 0.5))
                }) { m in
                    let before = m.project.transitions
                    if let clip, let i = m.index(ofClip: clip) {
                        let id = m.project.segments[i].id
                        m.project.setTransition(after: id, kind: kind, duration: seconds.map { min($0, m.longestTransition(after: id)) })
                    } else {
                        for cut in m.cuts {
                            m.project.setTransition(after: cut.after, kind: kind, duration: min(seconds ?? kind.defaultDuration, m.longestTransition(after: cut.after)))
                        }
                    }
                    return m.project.transitions == before ? nil : [.transitions]
                }
            case .removeTransition(let clip):
                if let clip, index(ofClip: clip) == nil { skipped.append(op.type); continue }
                add("scissors", describe(op), op) { m in
                    let before = m.project.transitions
                    if let clip, let i = m.index(ofClip: clip) {
                        m.project.setTransition(after: m.project.segments[i].id, kind: nil)
                    } else {
                        m.project.transitions.removeAll()
                    }
                    return m.project.transitions == before ? nil : [.transitions]
                }
            case .generateVideo(let request):
                guard aiVideoModel != nil else { skipped.append(op.type); continue }
                let box = AIGeneratedClipBox()
                steps.append(AIStep(
                    info: AIStepInfo(id: steps.count, symbol: "wand.and.stars", text: describe(op)),
                    types: [op.type],
                    locate: { m in
                        let at = request.at ?? m.playhead
                        return (at + 0.05, at...(at + (request.seconds ?? 4)))
                    },
                    perform: { m in
                        guard let clip = box.clip else { return nil }
                        return m.layInGenerated(
                            clip,
                            prompt: request.prompt,
                            at: request.at ?? m.playhead,
                            placement: request.asClip ? .clip : .broll,
                            recordingEdit: false
                        ).map { [$0, .recording(clip.recording.id)] }
                    },
                    prepare: { m in box.clip = await m.aiGenerate(request) }
                ))
            default:
                continue
            }
        }

        // Backgrounds
        for op in ops {
            if case .removeEffect(let effect) = op {
                guard project.effects.contains(where: { $0.id.uuidString == effect }) else { skipped.append(op.type); continue }
                add("trash", describe(op), op, locate: { m in
                    guard let found = m.project.effects.first(where: { $0.id.uuidString == effect }) else { return (nil, nil) }
                    return (found.start.seconds + 0.05, found.start.seconds...found.end)
                }) { m in
                    guard let found = m.project.effects.firstIndex(where: { $0.id.uuidString == effect }) else { return nil }
                    let id = m.project.effects[found].id
                    m.project.effects.remove(at: found)
                    return [.effect(id)]
                }
                continue
            }
            guard case .setBackground(let request) = op else { continue }
            let style = request.style.flatMap(ClipBackground.init(rawValue:))
            if request.style != nil, style == nil { skipped.append(op.type); continue }
            if request.from == nil, let clip = request.clip, index(ofClip: clip) == nil { skipped.append(op.type); continue }
            // The stretch: the seconds asked for, else the clip, else the whole video.
            let span: (EditorModel) -> ClosedRange<Double>? = { m in
                if let from = request.from {
                    let start = max(0, min(from, m.duration))
                    let end = min(m.duration, max(request.to ?? m.duration, start + TimelineEffect.minimumLength))
                    return start...max(end, start + TimelineEffect.minimumLength)
                }
                if let clip = request.clip {
                    guard let i = m.index(ofClip: clip) else { return nil }
                    return m.timelineRange(ofSegmentAt: i)
                }
                return 0...m.duration
            }
            add("person.crop.rectangle", describe(op), op, locate: { m in
                guard let range = span(m) else { return (nil, nil) }
                return (range.lowerBound + 0.05, range)
            }) { m in
                guard let range = span(m) else { return nil }
                var targets: [AITarget] = []
                // What was there over the same stretch goes: a new look replaces, it does not stack.
                for effect in m.project.effects where effect.background != nil
                    && effect.start.seconds >= range.lowerBound - 0.05 && effect.end <= range.upperBound + 0.05 {
                    targets.append(.effect(effect.id))
                }
                m.project.effects.removeAll { effect in targets.contains(.effect(effect.id)) }
                guard let style else { return targets.isEmpty ? nil : targets }
                var settings = BackgroundSettings(style: style)
                if let strength = request.strength { settings.strength = min(max(strength > 1 ? strength / 100 : strength, 0), 1) }
                if let feather = request.feather { settings.feather = min(max(feather > 1 ? feather / 100 : feather, 0), 1) }
                if let hex = request.color { settings.color = RGBAColor(hex: hex) }
                switch request.keep?.lowercased() {
                case "subject", "object": settings.cutout = .subject
                case "screen", "color", "colour", "chroma":
                    settings.cutout = .color
                    var key = ChromaKey.green
                    if let hex = request.screen, let color = RGBAColor(hex: hex) { key.color = color }
                    settings.key = key
                default: break
                }
                let effect = TimelineEffect(
                    start: MediaTime(seconds: range.lowerBound),
                    duration: MediaTime(seconds: range.upperBound - range.lowerBound),
                    kind: .background(settings)
                )
                m.project.effects.append(effect)
                m.failedBackgrounds.removeAll()
                targets.append(.effect(effect.id))
                return targets
            }
        }

        // Filters, sound effects and effect timing — laid on the finished video's clock, before any
        // cut moves it, so the document's times are still the times they name.
        func span(_ m: EditorModel, clip: String?, from: Double?, to: Double?) -> ClosedRange<Double>? {
            if let from {
                let start = max(0, min(from, m.duration))
                let end = min(m.duration, max(to ?? m.duration, start + TimelineEffect.minimumLength))
                return start...max(end, start + TimelineEffect.minimumLength)
            }
            if let clip {
                guard let i = m.index(ofClip: clip) else { return nil }
                return m.timelineRange(ofSegmentAt: i)
            }
            return 0...m.duration
        }
        func effectPlace(_ m: EditorModel, _ id: String) -> (time: Double?, scan: ClosedRange<Double>?) {
            guard let effect = m.project.effects.first(where: { $0.id.uuidString == id }) else { return (nil, nil) }
            return (effect.start.seconds + 0.05, effect.start.seconds...effect.end)
        }
        func videoPlace(_ m: EditorModel, _ id: String) -> (time: Double?, scan: ClosedRange<Double>?) {
            guard let layer = m.project.videoLayers.first(where: { $0.id.uuidString == id }) else { return (nil, nil) }
            return (layer.start.seconds + 0.05, layer.start.seconds...layer.end)
        }

        for op in ops {
            switch op {
            case .setFilter(let request):
                if let effect = request.effect {
                    guard let uuid = UUID(uuidString: effect), project.effects.contains(where: { $0.id == uuid && $0.filter != nil }) else {
                        skipped.append(op.type); continue
                    }
                    add("camera.filters", describe(op), op, locate: { effectPlace($0, effect) }) { m in
                        guard let current = m.project.effects.first(where: { $0.id == uuid })?.filter else { return nil }
                        m.updateEffect(uuid, coalescing: "ai") { $0.kind = .filter(request.applied(to: current)) }
                        if request.from != nil || request.to != nil, let range = span(m, clip: nil, from: request.from, to: request.to) {
                            m.updateEffect(uuid, coalescing: "ai") {
                                $0.start = MediaTime(seconds: range.lowerBound)
                                $0.duration = MediaTime(seconds: range.upperBound - range.lowerBound)
                            }
                        }
                        return [.effect(uuid)]
                    }
                } else {
                    if request.from == nil, let clip = request.clip, index(ofClip: clip) == nil { skipped.append(op.type); continue }
                    let id = UUID()
                    add("camera.filters", describe(op), op, locate: { m in
                        guard let range = span(m, clip: request.clip, from: request.from, to: request.to) else { return (nil, nil) }
                        return (range.lowerBound + 0.05, range)
                    }) { m in
                        guard let range = span(m, clip: request.clip, from: request.from, to: request.to) else { return nil }
                        let settings = request.applied(to: FilterSettings(look: .natural))
                        m.project.effects.append(TimelineEffect(
                            id: id,
                            start: MediaTime(seconds: range.lowerBound),
                            duration: MediaTime(seconds: range.upperBound - range.lowerBound),
                            kind: .filter(settings)
                        ))
                        return [.effect(id)]
                    }
                }
            case .setSound(let request):
                if let effect = request.effect {
                    guard let uuid = UUID(uuidString: effect), project.effects.contains(where: { $0.id == uuid && $0.sound != nil }) else {
                        skipped.append(op.type); continue
                    }
                    add("waveform", describe(op), op, locate: { effectPlace($0, effect) }) { m in
                        guard let current = m.project.effects.first(where: { $0.id == uuid })?.sound else { return nil }
                        m.updateEffect(uuid, coalescing: "ai") { $0.kind = .sound(request.applied(to: current)) }
                        if request.from != nil || request.to != nil, let range = span(m, clip: nil, from: request.from, to: request.to) {
                            m.updateEffect(uuid, coalescing: "ai") {
                                $0.start = MediaTime(seconds: range.lowerBound)
                                $0.duration = MediaTime(seconds: range.upperBound - range.lowerBound)
                            }
                        }
                        return [.effect(uuid)]
                    }
                } else {
                    guard request.preset.flatMap(SoundSettings.Preset.init(rawValue:)) != nil || request.volume != nil || request.pitch != nil else {
                        skipped.append(op.type); continue
                    }
                    if request.from == nil, let clip = request.clip, index(ofClip: clip) == nil { skipped.append(op.type); continue }
                    let id = UUID()
                    add("waveform", describe(op), op, locate: { m in
                        guard let range = span(m, clip: request.clip, from: request.from, to: request.to) else { return (nil, nil) }
                        return (range.lowerBound + 0.05, range)
                    }) { m in
                        guard let range = span(m, clip: request.clip, from: request.from, to: request.to) else { return nil }
                        let settings = request.applied(to: SoundSettings(preset: .clean))
                        m.project.effects.append(TimelineEffect(
                            id: id,
                            start: MediaTime(seconds: range.lowerBound),
                            duration: MediaTime(seconds: range.upperBound - range.lowerBound),
                            kind: .sound(settings)
                        ))
                        return [.effect(id)]
                    }
                }
            case .retimeEffect(let effect, let from, let to):
                guard let uuid = UUID(uuidString: effect), project.effects.contains(where: { $0.id == uuid }) else {
                    skipped.append(op.type); continue
                }
                add("arrow.left.and.right", describe(op), op, locate: { effectPlace($0, effect) }) { m in
                    guard let current = m.project.effects.first(where: { $0.id == uuid }) else { return nil }
                    let start = from ?? current.start.seconds
                    let end = to ?? (start + current.duration.seconds)
                    m.updateEffect(uuid, coalescing: "ai") {
                        $0.start = MediaTime(seconds: max(0, start))
                        $0.duration = MediaTime(seconds: max(TimelineEffect.minimumLength, end - max(0, start)))
                    }
                    return [.effect(uuid)]
                }
            case .splitEffect(let effect, let at):
                guard let uuid = UUID(uuidString: effect), project.effects.contains(where: { $0.id == uuid }) else {
                    skipped.append(op.type); continue
                }
                add("scissors", describe(op), op, locate: { _ in (at, nil) }) { m in
                    let count = m.project.effects.count
                    m.seek(to: at)
                    m.splitEffect(uuid)
                    guard m.project.effects.count > count, let index = m.project.effects.firstIndex(where: { $0.id == uuid }) else { return nil }
                    return [.effect(uuid), .effect(m.project.effects[index + 1].id)]
                }
            case .updateVideo(let video, let patch):
                guard let uuid = UUID(uuidString: video), project.videoLayers.contains(where: { $0.id == uuid }) else {
                    skipped.append(op.type); continue
                }
                add("rectangle.inset.filled", describe(op), op, locate: { videoPlace($0, video) }) { m in
                    guard let layer = m.project.videoLayers.first(where: { $0.id == uuid }) else { return nil }
                    if let sourceStart = patch.sourceStart { m.setVideoLayerSourceStart(uuid, to: sourceStart) }
                    if let start = patch.start {
                        // A new start moves the video; with an end as well, it is placed exactly.
                        if patch.end != nil { m.moveVideoLayer(uuid, to: start, coalescing: "ai") } else { m.moveVideoLayer(uuid, to: start, coalescing: "ai") }
                    }
                    if let end = patch.end { m.setVideoLayerEnd(uuid, to: end, coalescing: "ai") }
                    if patch.movesPlacement {
                        m.updateVideoLayer(uuid, coalescing: "ai") { $0.placement = patch.placement(over: layer.placement) }
                    }
                    m.updateVideoLayer(uuid, coalescing: "ai") {
                        if let volume = patch.volume { $0.volume = FilterRequest.unit(volume) }
                        if let muted = patch.muted { $0.isMuted = muted }
                        if let hidden = patch.hidden { $0.isHidden = hidden }
                        if let screen = patch.screen {
                            if screen.lowercased() == "none" {
                                $0.chroma = nil
                            } else {
                                var key = $0.chroma ?? .green
                                if let color = RGBAColor(hex: screen) { key.color = color }
                                $0.chroma = key
                            }
                        }
                    }
                    return [.videoLayer(uuid)]
                }
            case .keyframeVideo(let video, let at, let patch):
                guard let uuid = UUID(uuidString: video), project.videoLayers.contains(where: { $0.id == uuid }), patch.movesPlacement else {
                    skipped.append(op.type); continue
                }
                add("diamond", describe(op), op, locate: { _ in (at, nil) }) { m in
                    guard let layer = m.project.videoLayers.first(where: { $0.id == uuid }) else { return nil }
                    let time = min(max(at - layer.start.seconds, 0), layer.duration)
                    let placement = patch.placement(over: layer.placement(at: at))
                    m.updateVideoLayer(uuid, coalescing: "ai") { value in
                        if value.keyframes.isEmpty, time > 0.01 {
                            // Motion starts from where the video already is.
                            value.keyframes.append(VideoKeyframe(time: 0, placement: value.placement))
                        }
                        value.keyframes.removeAll { abs($0.time - time) < 0.02 }
                        value.keyframes.append(VideoKeyframe(time: time, placement: placement))
                        value.keyframes.sort { $0.time < $1.time }
                    }
                    return [.videoLayer(uuid)]
                }
            case .layoutVideos(let name):
                guard let layout = VideoLayout(rawValue: name), !project.videoLayers.isEmpty else { skipped.append(op.type); continue }
                add("rectangle.split.2x1", describe(op), op) { m in
                    m.applyVideoLayout(layout)
                    return [.mainVideo] + m.project.videoLayers.map { .videoLayer($0.id) }
                }
            case .removeVideo(let video):
                guard let uuid = UUID(uuidString: video), project.videoLayers.contains(where: { $0.id == uuid }) else {
                    skipped.append(op.type); continue
                }
                add("trash", describe(op), op, locate: { videoPlace($0, video) }) { m in
                    m.removeVideoLayer(uuid)
                    return [.videoLayer(uuid)]
                }
            case .splitVideo(let video, let at):
                guard let uuid = UUID(uuidString: video), project.videoLayers.contains(where: { $0.id == uuid }) else {
                    skipped.append(op.type); continue
                }
                add("scissors", describe(op), op, locate: { _ in (at, nil) }) { m in
                    let count = m.project.videoLayers.count
                    m.seek(to: at)
                    m.splitVideoLayer(uuid)
                    guard m.project.videoLayers.count > count, let index = m.project.videoLayers.firstIndex(where: { $0.id == uuid }) else { return nil }
                    return [.videoLayer(uuid), .videoLayer(m.project.videoLayers[index + 1].id)]
                }
            case .splitOverlay(let overlay, let at):
                guard let uuid = UUID(uuidString: overlay), project.overlays.contains(where: { $0.id == uuid }) else {
                    skipped.append(op.type); continue
                }
                add("scissors", describe(op), op, locate: { _ in (at, nil) }) { m in
                    let count = m.project.overlays.count
                    m.seek(to: at)
                    m.splitOverlay(uuid)
                    guard m.project.overlays.count > count, let index = m.project.overlays.firstIndex(where: { $0.id == uuid }) else { return nil }
                    return [.overlay(uuid), .overlay(m.project.overlays[index + 1].id)]
                }
            case .mainVolume(let volume):
                add("speaker.wave.2", describe(op), op) { m in
                    m.project.mainVideoVolume = min(max(volume, 0), 1)
                    return [.mainVideo]
                }
            case .useTranscript(let clip, let name):
                guard let source = SpeechSource(rawValue: name) else { skipped.append(op.type); continue }
                if let clip, index(ofClip: clip) == nil { skipped.append(op.type); continue }
                add("waveform.badge.magnifyingglass", describe(op), op) { m in
                    // The recordings the named clip (or every clip) is cut from.
                    let recordings = Set(m.project.segments.enumerated().compactMap { i, segment -> Recording.ID? in
                        if let clip, m.index(ofClip: clip) != i { return nil }
                        return segment.selectedTake?.recordingID
                    })
                    var targets: [AITarget] = []
                    for id in recordings {
                        guard let versions = m.project.recording(id: id)?.speech, versions.hasCloud else { continue }
                        for passage in versions.passages where passage.choice != source {
                            m.project.choose(source, forPassage: passage.id, inRecording: id, by: .ai)
                        }
                        targets.append(.recording(id))
                    }
                    guard !targets.isEmpty else { return nil }
                    targets += m.project.segments.map { .clip($0.id) }
                    return targets
                }
            default:
                continue
            }
        }

        // Duplicates
        for op in ops {
            guard case .duplicateClip(let clip) = op else { continue }
            guard index(ofClip: clip) != nil else { skipped.append(op.type); continue }
            add("plus.square.on.square", L("editor.ai.op.duplicate \(clipNumber(clip))"), op, locate: { m in
                guard let i = m.index(ofClip: clip) else { return (nil, nil) }
                return (m.start(at: i) + 0.05, m.clipRange(i))
            }) { m in
                guard let i = m.index(ofClip: clip) else { return nil }
                m.duplicateSegment(at: i)
                return [.clip(m.project.segments[i + 1].id)]
            }
        }

        // Footage: every cut for a clip gathered into one step, in the clip's original seconds.
        var order: [String] = []
        var cuts: [String: (ranges: [ClosedRange<Double>], ops: [EditPlan.Operation])] = [:]
        func gather(_ clip: String, _ ranges: [ClosedRange<Double>], _ op: EditPlan.Operation) {
            guard !ranges.isEmpty else { return }
            if cuts[clip] == nil { order.append(clip) }
            cuts[clip, default: ([], [])].ranges.append(contentsOf: ranges)
            cuts[clip, default: ([], [])].ops.append(op)
        }
        for op in ops {
            switch op {
            case .cut(let clip, let from, let to):
                guard index(ofClip: clip) != nil else { skipped.append(op.type); continue }
                gather(clip, [from...to], op)
            case .removeWords(let clip, let words):
                guard let i = index(ofClip: clip) else { skipped.append(op.type); continue }
                let spoken = spokenWords(at: i)
                let ranges = words.filter { spoken.indices.contains($0) }.map {
                    spoken[$0].range.start.seconds...spoken[$0].range.end.seconds
                }
                if ranges.isEmpty { skipped.append(op.type) } else { gather(clip, ranges, op) }
            case .trimPauses(let clip, let minPause):
                let targets = clip.map { [$0] } ?? project.segments.map(\.id.uuidString)
                for target in targets {
                    guard let i = index(ofClip: target) else { continue }
                    // A little air left at both ends of every pause, so the cut sounds like a
                    // breath rather than a splice.
                    let gaps = silenceGaps(at: i, threshold: max(0.2, minPause)).compactMap { gap -> ClosedRange<Double>? in
                        let lower = gap.lowerBound + 0.12
                        let upper = gap.upperBound - 0.12
                        return upper > lower ? lower...upper : nil
                    }
                    gather(target, gaps, op)
                }
            case .trimClip(let clip, let start, let end):
                guard let i = index(ofClip: clip) else { skipped.append(op.type); continue }
                let segment = project.segments[i]
                let total = segment.selectedTake?.sourceRange.duration.seconds ?? segment.sourceSeconds
                var ranges: [ClosedRange<Double>] = []
                if let start, start > 0.05 { ranges.append(0...min(start, total)) }
                if let end, end < total - 0.05 { ranges.append(max(0, end)...total) }
                if ranges.isEmpty { skipped.append(op.type) } else { gather(clip, ranges, op) }
            default:
                continue
            }
        }
        for clip in order {
            guard let group = cuts[clip] else { continue }
            let text = group.ops.count == 1
                ? describe(group.ops[0])
                : L("editor.ai.op.footage \(clipNumber(clip)) \(group.ranges.count)")
            let symbol = group.ops.count == 1 ? Self.symbol(for: group.ops[0]) : "scissors"
            steps.append(AIStep(
                info: AIStepInfo(id: steps.count, symbol: symbol, text: text),
                types: group.ops.map(\.type),
                locate: { m in
                    guard let i = m.index(ofClip: clip) else { return (nil, nil) }
                    let low = group.ranges.map(\.lowerBound).min() ?? 0
                    let high = group.ranges.map(\.upperBound).max() ?? low
                    let a = m.timelineSeconds(clip: i, footage: low)
                    let b = m.timelineSeconds(clip: i, footage: high)
                    return (a, a...max(a, b))
                },
                perform: { m in
                    let pieces = splits.pieces(of: clip)
                    var targets: [AITarget] = []
                    // Last piece first, so removing or rebuilding one does not move the ones before it.
                    for n in pieces.indices.reversed() {
                        let lower = pieces[n].offset
                        let upper = n + 1 < pieces.count ? pieces[n + 1].offset : .greatestFiniteMagnitude
                        let local = group.ranges.compactMap { range -> ClosedRange<Double>? in
                            let a = max(range.lowerBound, lower), b = min(range.upperBound, upper)
                            return b > a ? (a - lower)...(b - lower) : nil
                        }
                        guard !local.isEmpty, let i = m.index(ofClip: pieces[n].id) else { continue }
                        let segment = m.project.segments[i]
                        let total = segment.selectedTake?.sourceRange.duration.seconds ?? segment.sourceSeconds
                        let keep = Self.complement(of: local, within: total)
                        // Cutting everything would delete the clip, which the AI may not do.
                        if keep.isEmpty {
                            continue
                        } else {
                            let count = m.project.segments.count
                            m.rebuild(segmentAt: i, keeping: keep)
                            let added = max(0, m.project.segments.count - count)
                            for k in i...(i + added) where m.project.segments.indices.contains(k) {
                                targets.append(.clip(m.project.segments[k].id))
                            }
                        }
                    }
                    return targets.isEmpty ? nil : targets
                }
            ))
        }

        // Clips are never deleted by the AI: a whole clip gone is the one change people did not
        // expect from "make it tighter". It can cut inside clips; removing clips is the user's call.
        for op in ops {
            if case .deleteClip = op { skipped.append(op.type) }
        }

        // Order
        for op in ops {
            guard case .reorder(let order) = op else { continue }
            add("arrow.left.arrow.right", describe(op), op) { m in
                let ranked = Dictionary(order.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
                let reordered = m.project.segments.enumerated().sorted { left, right in
                    let a = ranked[left.element.id.uuidString] ?? (order.count + left.offset)
                    let b = ranked[right.element.id.uuidString] ?? (order.count + right.offset)
                    return a < b
                }.map(\.element)
                if reordered.map(\.id) != m.project.segments.map(\.id) {
                    m.project.segments = reordered
                }
                return [.clipOrder]
            }
        }

        return (steps, skipped)
    }

    /// Applies a look change and reads captions again if the words per caption changed.
    private func applyCaptionLook(_ look: EditPlan.CaptionLook) -> [AITarget]? {
        var style = project.captionStyle
        if let preset = look.preset {
            guard CaptionStyle.presetIDs.contains(preset) else { return nil }
            style = CaptionStyle.preset(preset, position: style.position)
        }
        if let size = look.size { style.relativeFontSize = min(max(size, 0.018), 0.075) }
        if let words = look.maxWords { style.maxWordsPerCue = min(max(words, 1), 8) }
        if let textCase = look.textCase.flatMap({ CaptionTextCase(rawValue: $0) }) { style.textCase = textCase }
        if let color = look.textColor.flatMap({ RGBAColor(hex: $0) }) { style.textColor = color }
        if let hex = look.highlightColor {
            style.highlightColor = hex.lowercased() == "none" ? nil : (RGBAColor(hex: hex) ?? style.highlightColor)
        }
        if let hex = look.backgroundColor {
            style.backgroundColor = hex.lowercased() == "none" ? nil : (RGBAColor(hex: hex) ?? style.backgroundColor)
        }
        if let font = look.font, Self.captionFonts.contains(font) { style.fontName = font }
        if let y = look.position { style.position = CaptionPosition(x: style.position.x, y: min(max(y, 0.08), 0.92)) }

        let previousWords = project.captionStyle.maxWordsPerCue
        project.captionStyle = style
        var targets: [AITarget] = [.captionStyle]
        if previousWords != style.maxWordsPerCue {
            for s in project.segments.indices {
                project.segments[s].refreshCaptions(maxWordsPerCue: style.maxWordsPerCue, carrying: project.segments[s].captions)
                targets.append(.captions(project.segments[s].id))
            }
        }
        return targets
    }

    static let captionFonts = OverlayText.fonts + ["InstrumentSans-Medium"]

    static func apply(_ patch: EditPlan.OverlayPatch, to overlay: inout Overlay) {
        if let start = patch.start { overlay.start = MediaTime(seconds: max(0, start)) }
        if let length = patch.duration {
            overlay.duration = MediaTime(seconds: max(Overlay.shortest, length))
        } else if let end = patch.end {
            overlay.duration = MediaTime(seconds: max(Overlay.shortest, end - overlay.start.seconds))
        }
        if let x = patch.x { overlay.transform.x = x }
        if let y = patch.y { overlay.transform.y = y }
        if let scale = patch.scale { overlay.transform.scale = scale }
        if let rotation = patch.rotation { overlay.transform.rotation = rotation }
        if let opacity = patch.opacity { overlay.transform.opacity = opacity }
        if let flip = patch.flipX { overlay.transform.flipX = flip }
        if let flip = patch.flipY { overlay.transform.flipY = flip }
        if let animation = patch.animation.flatMap({ OverlayAnimation(rawValue: $0) }) { overlay.animation = animation }
        if let behind = patch.behind { overlay.isBehindPerson = behind }
        if case .text(var content) = overlay.content {
            if let text = patch.text, !text.isEmpty { content.text = text }
            if let color = patch.color.flatMap({ RGBAColor(hex: $0) }) { content.color = color }
            if let hex = patch.background {
                content.background = hex.lowercased() == "none" ? nil : (RGBAColor(hex: hex) ?? content.background)
            }
            if let font = patch.font, OverlayText.fonts.contains(font) { content.fontName = font }
            overlay.content = .text(content)
        }
    }

    /// The parts of `0...total` not covered by any range, merged and clamped.
    static func complement(of ranges: [ClosedRange<Double>], within total: Double) -> [ClosedRange<Double>] {
        let sorted = ranges
            .map { max(0, $0.lowerBound)...min(total, max($0.lowerBound, $0.upperBound)) }
            .sorted { $0.lowerBound < $1.lowerBound }
        var merged: [ClosedRange<Double>] = []
        for range in sorted {
            if let last = merged.last, range.lowerBound <= last.upperBound + 0.02 {
                merged[merged.count - 1] = last.lowerBound...max(last.upperBound, range.upperBound)
            } else {
                merged.append(range)
            }
        }
        var keep: [ClosedRange<Double>] = []
        var cursor = 0.0
        for range in merged {
            if range.lowerBound - cursor > 0.13 { keep.append(cursor...range.lowerBound) }
            cursor = max(cursor, range.upperBound)
        }
        if total - cursor > 0.13 { keep.append(cursor...total) }
        return keep
    }

    // MARK: - Words for the steps

    private func L(_ key: String.LocalizationValue) -> String {
        String(localized: key, bundle: .module)
    }

    static func seconds(_ value: Double) -> String {
        String(format: "%.1f", value)
    }

    private func audioPlace(_ id: String) -> (time: Double?, scan: ClosedRange<Double>?) {
        guard let clip = project.audio.first(where: { $0.id.uuidString == id }) else { return (nil, nil) }
        let start = clip.start.seconds
        return (start + 0.05, start...(start + clip.timelineDuration.seconds))
    }

    private func cameraKindName(_ kind: CameraMotionRecipe.Kind) -> String {
        switch kind {
        case .pushIn: L("editor.zoom.push")
        case .pullOut: L("editor.zoom.pull")
        case .punch: L("editor.zoom.punch")
        case .hold: L("editor.zoom.static")
        }
    }

    func clipNumber(_ id: String) -> String {
        guard let index = index(ofClip: id) else { return "?" }
        return "\(index + 1)"
    }

    private func captionText(_ id: String) -> String {
        guard let uuid = UUID(uuidString: id) else { return "" }
        for segment in project.segments {
            if let cue = segment.captions.first(where: { $0.id == uuid }) { return String(cue.text.prefix(28)) }
        }
        return ""
    }

    private func audioName(_ id: String) -> String {
        project.audio.first { $0.id.uuidString == id }?.name ?? ""
    }

    private func overlayName(_ id: String) -> String {
        guard let overlay = project.overlays.first(where: { $0.id.uuidString == id }) else { return "" }
        return String(OverlayLane.label(for: overlay).prefix(28))
    }

    static func symbol(for operation: EditPlan.Operation) -> String {
        switch operation {
        case .cut, .removeWords, .trimClip, .splitClip: "scissors"
        case .trimPauses: "waveform.badge.minus"
        case .setSpeed: "gauge.with.dots.needle.67percent"
        case .reverse: "backward.fill"
        case .duplicateClip: "plus.square.on.square"
        case .deleteClip: "trash"
        case .reorder: "arrow.left.arrow.right"
        case .setCaptionText, .captionTiming, .splitCaption, .mergeCaption, .removeCaption: "text.bubble"
        case .captionStyle, .captionLook, .captionWindow: "captions.bubble"
        case .addText, .updateOverlay, .removeOverlay: "textformat"
        case .addTemplate: "sparkles.rectangle.stack"
        case .editTemplate: "character.cursor.ibeam"
        case .setMusicLevel, .updateAudio, .removeAudio: "music.note"
        case .voiceCleanup, .voiceEffects: "waveform.and.person.filled"
        case .setTitle: "character.cursor.ibeam"
        case .renameClip: "tag"
        case .setRole: "sparkles"
        case .setScript: "text.alignleft"
        case .selectTake: "film.stack"
        case .duplicateOverlay: "plus.square.on.square"
        case .shiftCaptions: "arrow.left.and.right"
        case .setBackground: "person.crop.rectangle"
        case .removeEffect: "trash"
        case .setFilter: "camera.filters"
        case .setSound: "waveform"
        case .retimeEffect: "arrow.left.and.right"
        case .splitEffect, .splitVideo, .splitOverlay: "scissors"
        case .updateVideo, .layoutVideos: "rectangle.inset.filled"
        case .keyframeVideo: "diamond"
        case .removeVideo: "trash"
        case .mainVolume: "speaker.wave.2"
        case .useTranscript: "waveform.badge.magnifyingglass"
        case .cameraMove: "plus.magnifyingglass"
        case .removeCameraMove: "minus.magnifyingglass"
        case .trackFace, .removeTrack: "scope"
        case .generateVideo: "wand.and.stars"
        case .transition: "square.on.square.intersection.dashed"
        case .removeTransition: "scissors"
        case .unknown: "questionmark"
        }
    }

    func describe(_ operation: EditPlan.Operation) -> String {
        switch operation {
        case .cut(let clip, let from, let to):
            L("editor.ai.op.cut \(clipNumber(clip)) \(Self.seconds(from)) \(Self.seconds(to))")
        case .removeWords(let clip, let words):
            L("editor.ai.op.words \(clipNumber(clip)) \(words.count)")
        case .trimPauses(let clip, let minPause):
            L("editor.ai.op.pauses \(clip.map(clipNumber) ?? "*") \(Self.seconds(minPause))")
        case .trimClip(let clip, _, _):
            L("editor.ai.op.trim \(clipNumber(clip))")
        case .splitClip(let clip, let at):
            L("editor.ai.op.split \(clipNumber(clip)) \(Self.seconds(at))")
        case .duplicateClip(let clip):
            L("editor.ai.op.duplicate \(clipNumber(clip))")
        case .setSpeed(let clip, let speed):
            L("editor.ai.op.speed \(clipNumber(clip)) \(String(format: "%.2g", speed))")
        case .reverse(let clip, _):
            L("editor.ai.op.reverse \(clipNumber(clip))")
        case .deleteClip(let clip):
            L("editor.ai.op.delete \(clipNumber(clip))")
        case .reorder:
            L("editor.ai.op.reorder")
        case .setCaptionText(_, let text):
            L("editor.ai.op.caption \(text)")
        case .captionTiming(let id, _, _):
            L("editor.ai.op.captionTiming \(captionText(id))")
        case .splitCaption(let id):
            L("editor.ai.op.captionSplit \(captionText(id))")
        case .mergeCaption(let id):
            L("editor.ai.op.captionMerge \(captionText(id))")
        case .removeCaption(let id):
            L("editor.ai.op.captionRemove \(captionText(id))")
        case .captionStyle(let preset, _):
            L("editor.ai.op.style \(preset)")
        case .captionLook:
            L("editor.ai.op.look")
        case .captionWindow(let from, let to):
            from == nil && to == nil
                ? L("editor.ai.op.windowAll")
                : L("editor.ai.op.window \(Self.seconds(from ?? 0)) \(Self.seconds(to ?? duration))")
        case .addText(let patch):
            L("editor.ai.op.addText \(patch.text ?? "")")
        case .updateOverlay(let id, _):
            L("editor.ai.op.updateOverlay \(overlayName(id))")
        case .removeOverlay(let id):
            L("editor.ai.op.removeOverlay \(overlayName(id))")
        case .addTemplate(let request):
            L("editor.ai.op.addTemplate \(request.texts["title"] ?? request.texts["code"] ?? request.style ?? "")")
        case .editTemplate(let id, _):
            L("editor.ai.op.editTemplate \(overlayName(id))")
        case .setMusicLevel(_, let gain):
            L("editor.ai.op.music \(String(format: "%.0f", gain))")
        case .updateAudio(let id, _):
            L("editor.ai.op.audio \(audioName(id))")
        case .removeAudio(let id):
            L("editor.ai.op.removeAudio \(audioName(id))")
        case .voiceCleanup(let on):
            on ? L("editor.ai.op.voiceOn") : L("editor.ai.op.voiceOff")
        case .voiceEffects:
            L("editor.ai.op.voice")
        case .setTitle(let title):
            L("editor.ai.op.title \(title)")
        case .renameClip(let clip, let title):
            L("editor.ai.op.rename \(clipNumber(clip)) \(title)")
        case .setRole(let clip, let name):
            L("editor.ai.op.role \(clipNumber(clip)) \(SegmentRole(documentName: name)?.displayLabel ?? name)")
        case .setScript(let clip, _):
            L("editor.ai.op.script \(clipNumber(clip))")
        case .selectTake(let clip, _):
            L("editor.ai.op.take \(clipNumber(clip))")
        case .duplicateOverlay(let id, _):
            L("editor.ai.op.duplicateOverlay \(overlayName(id))")
        case .shiftCaptions(_, let by):
            L("editor.ai.op.shiftCaptions \(Self.seconds(by))")
        case .setBackground(let request):
            if let from = request.from {
                L("editor.ai.op.backgroundSpan \(Self.seconds(from)) \(Self.seconds(request.to ?? from)) \(ToolDock.label(request.style.flatMap(ClipBackground.init(rawValue:))))")
            } else {
                L("editor.ai.op.background \(request.clip.map(clipNumber) ?? "*") \(ToolDock.label(request.style.flatMap(ClipBackground.init(rawValue:))))")
            }
        case .removeEffect:
            L("editor.ai.op.removeEffect")
        case .setFilter(let request):
            L("editor.ai.op.filter \(request.look.flatMap(FilterSettings.Look.init(rawValue:)).map(FilterPresets.label) ?? "")")
        case .setSound(let request):
            L("editor.ai.op.sound \(request.preset.flatMap(SoundSettings.Preset.init(rawValue:)).map(SoundPresets.label) ?? "")")
        case .retimeEffect:
            L("editor.ai.op.retimeEffect")
        case .splitEffect(_, let at), .splitVideo(_, let at), .splitOverlay(_, let at):
            L("editor.ai.op.splitAt \(Self.seconds(at))")
        case .updateVideo:
            L("editor.ai.op.video")
        case .keyframeVideo(_, let at, _):
            L("editor.ai.op.videoMove \(Self.seconds(at))")
        case .layoutVideos:
            L("editor.ai.op.layout")
        case .removeVideo:
            L("editor.ai.op.removeVideo")
        case .mainVolume(let volume):
            L("editor.ai.op.mainVolume \(Int((volume * 100).rounded()))")
        case .useTranscript(_, let source):
            L("editor.ai.op.transcript \(source == "cloud" ? SpeechVersionsRow.name(.cloud) : SpeechVersionsRow.name(.device))")
        case .cameraMove(let request):
            L("editor.ai.op.cameraMove \(cameraKindName(request.kind ?? .pushIn))")
        case .removeCameraMove:
            L("editor.ai.op.removeCameraMove")
        case .trackFace(let clip, _):
            L("editor.ai.op.trackFace \(clip.map(clipNumber) ?? "*")")
        case .removeTrack(let clip):
            L("editor.ai.op.removeTrack \(clip.map(clipNumber) ?? "*")")
        case .generateVideo(let request):
            L("editor.ai.op.generateVideo \(String(request.prompt.prefix(40)))")
        case .transition(let clip, let kind, _):
            L("editor.ai.op.transition \(ClipTransition.Kind(loose: kind).map { String(localized: TransitionMarks.titleKey($0), bundle: .module) } ?? kind) \(clip.map(clipNumber) ?? "*")")
        case .removeTransition(let clip):
            L("editor.ai.op.removeTransition \(clip.map(clipNumber) ?? "*")")
        case .unknown(let type):
            L("editor.ai.op.unknown \(type)")
        }
    }
}
