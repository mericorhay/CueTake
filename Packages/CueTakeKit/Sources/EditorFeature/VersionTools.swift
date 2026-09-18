import Domain
import Foundation

/// What the editor can do with saved versions of the open project. The app owns the store; the
/// editor only shows the list and asks.
public struct VersionTools {
    public var versions: [ProjectVersion]
    public var save: (String) -> Void
    public var restore: (ProjectVersion) -> Void
    public var delete: (ProjectVersion.ID) -> Void
    /// Reads the list again, for when the sheet opens.
    public var refresh: () -> Void

    public init(
        versions: [ProjectVersion],
        save: @escaping (String) -> Void,
        restore: @escaping (ProjectVersion) -> Void,
        delete: @escaping (ProjectVersion.ID) -> Void,
        refresh: @escaping () -> Void
    ) {
        self.versions = versions
        self.save = save
        self.restore = restore
        self.delete = delete
        self.refresh = refresh
    }
}

extension EditorModel {
    /// Puts a saved version in place of what is open, as one step that undo can take back.
    ///
    /// Selections are put down first: they point at clips and overlays of the project being
    /// replaced, and an inspector left open on something that no longer exists is how an editor
    /// crashes.
    public func restore(_ version: Project) {
        guard version.id == project.id else { return }
        record("editor.change.versionRestore", symbol: "clock.arrow.circlepath")
        clearOtherSelections()
        selectedCameraMotion = nil
        selectedSubjectTrack = nil
        var next = version
        next.updatedAt = .now
        project = next
        loadOverlayImages()
    }
}
