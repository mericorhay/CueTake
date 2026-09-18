import Foundation

/// A saved state of a project that can be gone back to.
///
/// Undo already covers "that last thing was a mistake". It does not cover "the cut I had on
/// Tuesday was better", because undo is lost when the editor closes and walking back sixty steps
/// to find Tuesday is not a thing anyone does. A version is a whole project document, named, kept
/// beside the project; the media files are shared, so a version costs a few kilobytes.
public struct ProjectVersion: Identifiable, Hashable, Sendable, Codable {
    public enum Kind: String, Hashable, Sendable, Codable {
        /// Saved by the person, with a name they chose.
        case manual
        /// Taken by the app before something big: opening the editor, an AI edit, going back to
        /// another version. Kept only a few at a time.
        case automatic
    }

    public var id: UUID
    public var name: String
    public var kind: Kind
    public var savedAt: Date
    /// Enough to tell versions apart in a list without opening them.
    public var seconds: Double
    public var clips: Int

    public init(id: UUID = UUID(), name: String, kind: Kind, savedAt: Date = .now, seconds: Double, clips: Int) {
        self.id = id
        self.name = name
        self.kind = kind
        self.savedAt = savedAt
        self.seconds = seconds
        self.clips = clips
    }

    public init(of project: Project, name: String, kind: Kind, savedAt: Date = .now) {
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.init(
            name: cleaned.isEmpty ? project.title : String(cleaned.prefix(Self.longestName)),
            kind: kind,
            savedAt: savedAt,
            seconds: project.segments.reduce(0) { $0 + $1.barWeight },
            clips: project.segments.count
        )
    }

    public static let longestName = 60
    /// How many automatic versions are kept. A safety net, not an archive: more than this and the
    /// list stops being something anyone reads.
    public static let automaticLimit = 8
    /// Manual versions are the person's own and are never thrown away silently; this only stops a
    /// runaway loop from filling the disk.
    public static let manualLimit = 50

    /// Which versions to throw away once `new` has been added: the oldest automatic ones past the
    /// limit. Manual versions are only ever removed past their own, much larger, limit.
    public static func overflow(in versions: [ProjectVersion]) -> [ProjectVersion.ID] {
        let newestFirst = versions.sorted { $0.savedAt > $1.savedAt }
        let automatic = newestFirst.filter { $0.kind == .automatic }.dropFirst(automaticLimit)
        let manual = newestFirst.filter { $0.kind == .manual }.dropFirst(manualLimit)
        return (automatic + manual).map(\.id)
    }

    /// Whether an automatic version is worth taking now: not if one was taken in the last hour,
    /// because opening and closing the editor ten times is not ten different states.
    public static func wantsAutomatic(since versions: [ProjectVersion], now: Date = .now) -> Bool {
        guard let last = versions.filter({ $0.kind == .automatic }).map(\.savedAt).max() else { return true }
        return now.timeIntervalSince(last) > 3600
    }
}
