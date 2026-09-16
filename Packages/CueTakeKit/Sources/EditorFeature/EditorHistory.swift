import Domain
import Foundation

/// One edit, as the user would describe it.
///
/// The label is written at the moment the edit happens, by the code doing it, because that is the
/// only place that knows what it was — a diff between two projects can tell you a number changed
/// but not that it was a trim. "Clip 3 trimmed" is a sentence; "segments[2].takes[0].sourceRange
/// changed" is a fact nobody asked for.
public struct ChangeEntry: Identifiable, Equatable, Sendable {
    public let id: Int
    public var label: String
    public var symbol: String
    public var at: Date

    public init(id: Int, label: String, symbol: String, at: Date = .now) {
        self.id = id
        self.label = label
        self.symbol = symbol
        self.at = at
    }
}

/// A project as it was, plus what was about to be done to it.
struct EditSnapshot {
    var project: Project
    var entry: ChangeEntry
    /// Used to fold a drag into one entry. A trim produces sixty mutations a second and sixty
    /// undo steps would make undo useless — the finger did one thing, so it is one edit.
    var coalescingKey: String?
}

extension EditorModel {
    /// Records the state *before* an edit, labelled with the edit about to happen.
    ///
    /// Snapshots rather than inverse operations. Inverse operations are smaller and faster and
    /// wrong the first time someone adds an edit and forgets to write its opposite; a whole
    /// project is a few kilobytes of value types, and copying one is cheaper than the bug.
    func record(_ label: String.LocalizationValue, symbol: String, coalescing key: String? = nil) {
        // A plan is one edit however many tools it uses; its first record is the only one kept.
        guard !isApplyingPlan else { return }
        // A drag already in progress keeps its first snapshot: what the user wants back is where
        // the clip was before they took hold of it, not where it was a frame ago.
        if let key,
           let last = past.last,
           last.coalescingKey == key,
           Date.now.timeIntervalSince(last.entry.at) < 2 {
            return
        }

        editCount += 1
        past.append(
            EditSnapshot(
                project: project,
                entry: ChangeEntry(
                    id: editCount,
                    label: String(localized: label, bundle: .module),
                    symbol: symbol
                ),
                coalescingKey: key
            )
        )
        // Deep enough to cover a working session, shallow enough that a long edit does not carry
        // a hundred copies of the project around.
        if past.count > 60 { past.removeFirst() }
        // Redo cannot survive a new edit: it describes a future that no longer follows from here.
        future.removeAll()
    }

    /// Starts work done from outside the editor — a workflow run — whose many tool calls should be
    /// one edit. Nothing is recorded until `endBatch(startingFrom:)`.
    public func beginBatch() {
        // Inside a batch already (an AI run using a tool that batches): one step, still.
        if isApplyingPlan {
            batchDepth += 1
            return
        }
        isApplyingPlan = true
    }

    /// Ends a batch as a single undo step back to `before`.
    public func endBatch(
        startingFrom before: Project,
        label: String.LocalizationValue = "editor.change.workflow",
        symbol: String = "flowchart"
    ) {
        if batchDepth > 0 {
            batchDepth -= 1
            return
        }
        isApplyingPlan = false
        guard before != project else { return }
        editCount += 1
        past.append(
            EditSnapshot(
                project: before,
                entry: ChangeEntry(
                    id: editCount,
                    label: String(localized: label, bundle: .module),
                    symbol: symbol
                ),
                coalescingKey: nil
            )
        )
        if past.count > 60 { past.removeFirst() }
        future.removeAll()
    }

    public var canUndo: Bool { !past.isEmpty }
    public var canRedo: Bool { !future.isEmpty }

    /// What has been done, newest first. What the changes sheet draws.
    public var changes: [ChangeEntry] {
        past.map(\.entry).reversed()
    }

    public var lastChange: ChangeEntry? { past.last?.entry }

    public func undo() {
        guard let snapshot = past.popLast() else { return }
        future.append(
            EditSnapshot(project: project, entry: snapshot.entry, coalescingKey: nil)
        )
        adopt(snapshot.project)
        reconcileAIChanges()
        pulse(.undo)
    }

    public func redo() {
        guard let snapshot = future.popLast() else { return }
        past.append(
            EditSnapshot(project: snapshot.project, entry: snapshot.entry, coalescingKey: nil)
        )
        adopt(snapshot.project)
        reconcileAIChanges()
        pulse(.redo)
    }

    /// Back to how the project was when the editor opened.
    ///
    /// One step, not sixty. Someone who has made a mess of a clip wants out of it, and pressing
    /// undo twenty times while watching each step replay is not getting out of it.
    public func revertAll() {
        guard let original = past.first?.project else { return }
        future.removeAll()
        // The revert is itself undoable: it is the largest edit in the app, and the one most
        // likely to be pressed by accident.
        record("editor.change.revert", symbol: "arrow.counterclockwise")
        adopt(original)
        reconcileAIChanges()
    }

    /// Puts a project back and repairs whatever pointed into the old one.
    func adopt(_ restored: Project) {
        var restored = restored
        restored.aiConversations = project.aiConversations
        project = restored
        if let inspected = inspectedSegment, !restored.segments.contains(where: { $0.id == inspected }) {
            inspectedSegment = nil
        }
        if let selected = selectedAudio, !restored.audio.contains(where: { $0.id == selected }) {
            selectedAudio = nil
        }
        if let selected = selectedEffect, !restored.effects.contains(where: { $0.id == selected }) {
            selectedEffect = nil
        }
        if let selected = selectedOverlay, !restored.overlays.contains(where: { $0.id == selected }) {
            selectedOverlay = nil
        }
        if let selected = selectedVideoLayer, !restored.videoLayers.contains(where: { $0.id == selected }) {
            selectedVideoLayer = nil
        }
        // Through `seek` rather than the property: the player has to be told too, or the picture
        // stays where the undone edit left it.
        pause()
        seek(to: min(playhead, duration))
    }
}

extension EditorModel {
    /// The project before and after one recorded edit, by its entry.
    private func span(of entryID: ChangeEntry.ID) -> (index: Int, before: Project, after: Project)? {
        guard let index = past.firstIndex(where: { $0.entry.id == entryID }) else { return nil }
        let after = index + 1 < past.count ? past[index + 1].project : project
        return (index, past[index].project, after)
    }

    /// What taking back one edit would also take back: later edits to the same things.
    ///
    /// Taking back a trim of clip 2 restores clip 2 as it was before the trim, so a later change
    /// to clip 2's captions goes with it. Said before it happens, never discovered after.
    public func editsCaughtUp(inUndoing entryID: ChangeEntry.ID) -> [ChangeEntry] {
        guard let (index, before, after) = span(of: entryID) else { return [] }
        let touched = Set(after.changedTargets(since: before))
        guard !touched.isEmpty else { return [] }
        var caught: [ChangeEntry] = []
        for later in (index + 1)..<past.count {
            let laterAfter = later + 1 < past.count ? past[later + 1].project : project
            if !touched.isDisjoint(with: laterAfter.changedTargets(since: past[later].project)) {
                caught.append(past[later].entry)
            }
        }
        return caught
    }

    public func canUndoOnly(_ entryID: ChangeEntry.ID) -> Bool {
        guard let (_, before, after) = span(of: entryID) else { return false }
        return !after.changedTargets(since: before).isEmpty
    }

    /// Takes back one edit from anywhere in the list, leaving the edits after it in place.
    ///
    /// Undo could only walk backwards: to take back the 23rd of 25 edits, the 24th and 25th had to
    /// go too. The edit's own before and after say what it touched; only those things are put
    /// back, and taking it back is itself an edit that can be undone.
    public func undoOnly(_ entryID: ChangeEntry.ID) {
        guard let (_, before, after) = span(of: entryID) else { return }
        let targets = after.changedTargets(since: before)
        guard !targets.isEmpty, let label = past.first(where: { $0.entry.id == entryID })?.entry.label else { return }
        record("editor.change.undoOne \(label)", symbol: "arrow.uturn.backward")
        adopt(project.restoring(targets, from: before))
        reconcileAIChanges()
        pulse(.undo)
    }
}
