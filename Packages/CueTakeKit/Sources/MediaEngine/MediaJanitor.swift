import Domain
import Foundation

/// Keeps what the app stores down to what its projects use.
///
/// Every edit that works on sound or direction writes a file beside the footage — the voice copied
/// out, a cleaned version per combination of switches, a reversed copy per trimmed range, the
/// sound pulled out for listening — and none of them were ever removed. Neither were the recordings
/// of clips that had been deleted or cut away. On a phone that is how an app that has "done nothing
/// much" ends up holding more than a gigabyte.
///
/// What stays: every recording some take still uses, imported sound, overlay pictures, the cover,
/// and the caches the project's current settings still read. Everything else in a media folder can
/// be made again from what stays, or belongs to nothing.
public enum MediaJanitor {
    private static let sizeKeys: Set<URLResourceKey> = [.isRegularFileKey, .totalFileAllocatedSizeKey, .contentModificationDateKey]

    /// Bytes the app's whole container takes — what Settings in iOS calls Documents & Data.
    public static func containerBytes() -> Int64 {
        bytes(in: URL.homeDirectory)
    }

    static func bytes(in directory: URL) -> Int64 {
        guard let items = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: Array(sizeKeys)) else {
            return 0
        }
        var total: Int64 = 0
        for case let url as URL in items {
            guard let values = try? url.resourceValues(forKeys: sizeKeys), values.isRegularFile == true else { continue }
            total += Int64(values.totalFileAllocatedSize ?? 0)
        }
        return total
    }

    /// Removes what nothing in `project` uses from its media folder, and returns the bytes freed.
    ///
    /// - Parameter keepOriginals: leave recordings and pictures no clip points at any more, removing
    ///   only caches. For the project open in the editor, whose undo can still bring a clip back.
    public static func clean(project: Project, mediaDirectory: URL, keepOriginals: Bool) -> Int64 {
        let fileManager = FileManager.default
        guard let files = try? fileManager.contentsOfDirectory(at: mediaDirectory, includingPropertiesForKeys: Array(sizeKeys)) else {
            return 0
        }
        func name(_ path: String) -> String { (path as NSString).lastPathComponent }

        let used = Set(project.segments.flatMap { $0.takes.map(\.recordingID) })
        let untranscribed = Set(project.segments.flatMap { $0.takes.filter { $0.transcript == nil }.map(\.recordingID) })
        var keep: Set<String> = ["cover.jpg"]

        for recording in project.recordings where used.contains(recording.id) {
            let file = name(recording.relativePath)
            keep.insert(file)
            let id = recording.id.uuidString
            if project.voiceEffects.isActive {
                keep.insert("\(id)-voice-\(AudioEffectRenderer.token(for: project.voiceEffects)).m4a")
            }
            if project.voiceEffects.isActive || project.segments.contains(where: { $0.playback.isReversed }) {
                keep.insert("\(id)-voice.m4a")
            }
            // Still being listened to: the sound pulled out for it is in use.
            if untranscribed.contains(recording.id) {
                keep.insert((file as NSString).deletingPathExtension + "-speech.m4a")
            }
        }
        for job in BackgroundRemover.jobs(for: project, in: mediaDirectory) {
            keep.insert(job.name)
        }
        for segment in project.segments where segment.playback.isReversed {
            guard let take = segment.selectedTake else { continue }
            let key = "\(take.id.uuidString)-\(Int(take.sourceRange.start.seconds * 1000))-\(Int(take.sourceRange.duration.seconds * 1000))"
            keep.insert("\(key)-rev.mov")
            keep.insert("\(key)-rev-audio.m4a")
        }
        for clip in project.audio {
            keep.insert(name(clip.relativePath))
            keep.insert("\(clip.id.uuidString)-\(AudioEffectRenderer.token(for: clip.effects)).m4a")
        }
        for overlay in project.overlays {
            if case .image(let path, _) = overlay.content { keep.insert(name(path)) }
        }

        var freed: Int64 = 0
        for url in files {
            let file = url.lastPathComponent
            guard !keep.contains(file),
                  let values = try? url.resourceValues(forKeys: sizeKeys),
                  values.isRegularFile == true
            else { continue }
            if keepOriginals, !isCache(file) { continue }
            if (try? fileManager.removeItem(at: url)) != nil {
                freed += Int64(values.totalFileAllocatedSize ?? 0)
            }
        }
        return freed
    }

    /// Files the app writes for itself and can write again.
    static func isCache(_ file: String) -> Bool {
        file.hasSuffix("-speech.m4a")
            || file.hasSuffix("-rev.mov")
            || file.hasSuffix("-rev-audio.m4a")
            || file.contains("-voice")
            || file.hasSuffix("-dry.m4a")
            || file.contains("-bg-")
            || file.range(of: #"^[0-9A-F-]{36}-[nvr]{1,3}\.m4a$"#, options: .regularExpression) != nil
    }

    /// Removes leftovers in the temporary folder older than `age`: exports already shared, imports
    /// cut short, conversions. Returns the bytes freed.
    public static func cleanTemporaryFiles(olderThan age: TimeInterval) -> Int64 {
        let fileManager = FileManager.default
        let folder = fileManager.temporaryDirectory
        guard let items = try? fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: Array(sizeKeys)) else {
            return 0
        }
        let cutoff = Date.now.addingTimeInterval(-age)
        var freed: Int64 = 0
        for url in items {
            let values = try? url.resourceValues(forKeys: sizeKeys)
            guard let modified = values?.contentModificationDate, modified < cutoff else { continue }
            let size = values?.isRegularFile == true ? Int64(values?.totalFileAllocatedSize ?? 0) : bytes(in: url)
            if (try? fileManager.removeItem(at: url)) != nil { freed += size }
        }
        return freed
    }
}
