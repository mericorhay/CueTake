import Domain
import Foundation

/// The camera on the music: punch-ins on the beat, found from the music itself.
extension EditorModel {
    public var canSyncToBeat: Bool { beatFinder != nil && project.hasMusic && !project.segments.isEmpty }

    /// Finds the beats of any music not analysed yet, then lays punch-ins on its pulse. One undo
    /// step. Returns how many moves were laid in.
    @discardableResult
    public func syncToBeat(_ options: BeatSyncOptions) async -> Int {
        guard let beatFinder, !beatSyncing else { return 0 }
        beatSyncing = true
        defer { beatSyncing = false }
        for index in project.audio.indices where project.audio[index].role == .music && project.audio[index].beats == nil {
            if let grid = await beatFinder(project.audio[index]), project.audio.indices.contains(index) {
                project.audio[index].beats = grid
            }
        }
        let operations = BeatSync.plan(options, project: project, document: document())
        guard !operations.isEmpty else { return 0 }
        record("editor.change.beatSync", symbol: "metronome")
        return await applyAutomated(EditPlan(summary: "", operations: operations)).applied
    }
}
