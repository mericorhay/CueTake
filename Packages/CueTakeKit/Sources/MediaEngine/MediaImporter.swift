import AVFoundation
import Domain
import Foundation

/// Brings footage the user already has into a project.
///
/// This is the front door. Asking someone to change how they shoot before the app has done
/// anything for them is the hardest sell there is; asking them for a file they already have is
/// no sell at all. Everything the editor can do works on imported clips exactly as it does on
/// recorded ones, because the model never cared where a `Recording` came from — the comment on
/// `Take` already described this case: one file, split into segments by different `sourceRange`s.
public struct MediaImporter: Sendable {
    /// Reached through `.default` rather than stored: `FileManager` is not `Sendable`, and the
    /// operations used here are the ones Foundation documents as safe from any thread.
    private var fileManager: FileManager { .default }

    public init() {}

    public enum ImportError: Error, Hashable, Sendable {
        case unreadable(URL)
        case notVideo(URL)
        case notAudio(URL)
    }

    /// One imported clip: the file in place, plus what was learned by reading it.
    public struct ImportedClip: Hashable, Sendable {
        public var recording: Recording
        public var take: Take
        public var suggestedTitle: String
    }

    /// Copies a clip into the project and reads back what it actually is.
    ///
    /// Copying rather than referencing: a photo-library URL is a loan, revoked when the picker's
    /// scope ends or the user deletes the original, and a project whose media can evaporate is not
    /// a project. The copy is the point at which the footage becomes ours to promise.
    public func importClip(from source: URL, into mediaDirectory: URL) async throws -> ImportedClip {
        try fileManager.createDirectory(at: mediaDirectory, withIntermediateDirectories: true)

        let recordingID = UUID()
        let fileExtension = source.pathExtension.isEmpty ? "mov" : source.pathExtension
        let fileName = "\(recordingID.uuidString).\(fileExtension)"
        let destination = mediaDirectory.appending(path: fileName, directoryHint: .notDirectory)

        // The picker hands back a security-scoped URL; without this the read fails with a
        // permissions error that looks like a missing file.
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }

        do {
            if fileManager.fileExists(atPath: destination.path(percentEncoded: false)) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.copyItem(at: source, to: destination)
        } catch {
            throw ImportError.unreadable(source)
        }

        let asset = AVURLAsset(url: destination)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            try? fileManager.removeItem(at: destination)
            throw ImportError.notVideo(source)
        }

        let duration = try await asset.load(.duration)
        let size = try await track.load(.naturalSize)
        let frameRate = try await track.load(.nominalFrameRate)

        let recording = Recording(
            id: recordingID,
            relativePath: "media/\(fileName)",
            format: Self.format(for: size, frameRate: frameRate),
            // Imported footage carries no record of which lens shot it, and guessing would put a
            // wrong fact in the document. Front is the default a retake would use.
            camera: .front,
            duration: MediaTime(seconds: duration.seconds)
        )

        let take = Take(
            recordingID: recording.id,
            sourceRange: MediaTimeRange(start: .zero, duration: recording.duration),
            status: .ready
        )

        return ImportedClip(
            recording: recording,
            take: take,
            suggestedTitle: source.deletingPathExtension().lastPathComponent
        )
    }

    /// Reads the shape of the footage rather than assuming it. A clip shot in landscape and laid
    /// out as a vertical reel is the most common way an import looks broken.
    static func format(for size: CGSize, frameRate: Float) -> VideoFormat {
        let width = abs(size.width)
        let height = abs(size.height)
        let ratio: VideoFormat.AspectRatio =
            if abs(width - height) < 1 { .square1x1 }
            else if height > width { .portrait9x16 }
            else { .landscape16x9 }

        // Thresholds a little under the nominal edge, because footage is not always exactly the
        // number on the box: 3840, 4096 and 4056 are all 4K as far as anybody cares.
        let longEdge = max(width, height)
        let resolution: VideoFormat.Resolution =
            if longEdge >= 7000 { .uhd8K }
            else if longEdge >= 2000 { .uhd4K }
            else { .hd1080 }

        return VideoFormat(
            aspectRatio: ratio,
            resolution: resolution,
            frameRate: frameRate > 0 ? Int(frameRate.rounded()) : 30
        )
    }
}


extension MediaImporter {
    /// One imported sound: the file in place, and a clip ready to drop on the timeline.
    public struct ImportedAudio: Hashable, Sendable {
        public var clip: AudioClip
    }

    /// Brings a piece of music, a voiceover or an effect into the project.
    ///
    /// The same promise as footage: copied, not referenced. A track picked out of Files is a loan
    /// that ends when the picker's scope does, and a project whose music disappears a week later
    /// is worse than one that never had any.
    public func importAudio(
        from source: URL,
        role: AudioClip.Role = .music,
        startingAt start: MediaTime = .zero,
        into mediaDirectory: URL
    ) async throws -> ImportedAudio {
        try fileManager.createDirectory(at: mediaDirectory, withIntermediateDirectories: true)

        let id = UUID()
        let fileExtension = source.pathExtension.isEmpty ? "m4a" : source.pathExtension
        let fileName = "\(id.uuidString).\(fileExtension)"
        let destination = mediaDirectory.appending(path: fileName, directoryHint: .notDirectory)

        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }

        do {
            if fileManager.fileExists(atPath: destination.path(percentEncoded: false)) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.copyItem(at: source, to: destination)
        } catch {
            throw ImportError.unreadable(source)
        }

        let asset = AVURLAsset(url: destination)
        guard let duration = try? await asset.load(.duration),
              duration.seconds > 0.05,
              ((try? await asset.loadTracks(withMediaType: .audio))?.first) != nil
        else {
            try? fileManager.removeItem(at: destination)
            throw ImportError.notAudio(source)
        }

        return ImportedAudio(
            clip: AudioClip(
                id: id,
                name: source.deletingPathExtension().lastPathComponent,
                relativePath: "media/\(fileName)",
                role: role,
                start: start,
                sourceRange: MediaTimeRange(start: .zero, duration: MediaTime(seconds: duration.seconds)),
                // Music arrives loud. Laid in at unity it buries the voice, and the first thing
                // every user does is reach for the level — so it lands where they would have put
                // it, roughly −8 dB, and ducking does the rest.
                gain: role == .music ? 0.4 : 1,
                ducksUnderVoice: role == .music
            )
        )
    }
}
