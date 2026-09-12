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

        let longEdge = max(width, height)
        let resolution: VideoFormat.Resolution = longEdge >= 2000 ? .uhd4K : .hd1080

        return VideoFormat(
            aspectRatio: ratio,
            resolution: resolution,
            frameRate: frameRate > 0 ? Int(frameRate.rounded()) : 30
        )
    }
}
