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
        apply(snapshot.project)
        pulse(.undo)
    }

    public func redo() {
        guard let snapshot = future.popLast() else { return }
        past.append(
            EditSnapshot(project: snapshot.project, entry: snapshot.entry, coalescingKey: nil)
        )
        apply(snapshot.project)
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
        apply(original)
    }

    /// Puts a project back and repairs whatever pointed into the old one.
    private func apply(_ restored: Project) {
        project = restored
        if let inspected = inspectedSegment, !restored.segments.contains(where: { $0.id == inspected }) {
            inspectedSegment = nil
        }
        if let selected = selectedAudio, !restored.audio.contains(where: { $0.id == selected }) {
            selectedAudio = nil
        }
        // Through `seek` rather than the property: the player has to be told too, or the picture
        // stays where the undone edit left it.
        pause()
        seek(to: min(playhead, duration))
    }
}
