import AVFoundation
import Domain
import Foundation

/// Builds the finished video out of the timeline, and writes it to a file.
///
/// This is the half of the app that makes everything before it worth doing: until a file comes out
/// the other end, trimming and reordering are a drawing of an edit rather than an edit.
///
/// Composition rather than re-encoding per clip: `AVMutableComposition` references the source files
/// and describes what to play from where, so assembling a video is nearly free and only the final
/// write costs anything. It is also why a retake is cheap — one segment's range changes and the
/// composition is rebuilt from scratch in milliseconds.
public struct VideoComposer: Sendable {
    public init() {}

    public enum ComposeError: Error, Hashable, Sendable {
        case nothingToCompose
        case missingMedia(Recording.ID)
        case noVideoTrack(Recording.ID)
        case exportFailed(String)
    }

    /// Assembles the project's selected takes, in segment order, into one composition.
    ///
    /// - Parameter mediaDirectory: where `Recording.relativePath` resolves against. The document
    ///   stores paths relative to the project because the container path changes between installs.
    public func compose(
        project: Project,
        mediaDirectory: URL
    ) async throws -> AVMutableComposition {
        let composition = AVMutableComposition()
        guard
            let videoTrack = composition.addMutableTrack(
                withMediaType: .video,
                preferredTrackID: kCMPersistentTrackID_Invalid
            ),
            let audioTrack = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
            )
        else { throw ComposeError.nothingToCompose }

        let recordings = Dictionary(uniqueKeysWithValues: project.recordings.map { ($0.id, $0) })
        var cursor = CMTime.zero
        var appended = 0

        for segment in project.segments {
            guard let take = segment.selectedTake,
                  let recording = recordings[take.recordingID]
            else { continue }

            // The file name is the last component; the directory is the project's, which is what
            // makes a project movable between devices.
            let url = mediaDirectory.appending(
                path: (recording.relativePath as NSString).lastPathComponent,
                directoryHint: .notDirectory
            )
            let asset = AVURLAsset(url: url)

            guard let sourceVideo = try await asset.loadTracks(withMediaType: .video).first else {
                throw ComposeError.noVideoTrack(recording.id)
            }

            let range = CMTimeRange(
                start: CMTime(seconds: take.sourceRange.start.seconds, preferredTimescale: 600),
                duration: CMTime(seconds: take.sourceRange.duration.seconds, preferredTimescale: 600)
            )

            try videoTrack.insertTimeRange(range, of: sourceVideo, at: cursor)
            // Audio is optional on purpose: a clip with no audio track is a legitimate thing to
            // put in a video, and refusing the whole export over it would be absurd.
            if let sourceAudio = try await asset.loadTracks(withMediaType: .audio).first {
                try? audioTrack.insertTimeRange(range, of: sourceAudio, at: cursor)
            }

            // Orientation lives on the source track, and dropping it is how an imported clip ends
            // up sideways in the export while looking upright everywhere else.
            videoTrack.preferredTransform = try await sourceVideo.load(.preferredTransform)

            cursor = cursor + range.duration
            appended += 1
        }

        guard appended > 0 else { throw ComposeError.nothingToCompose }
        return composition
    }

    /// Writes the composition to a file.
    public func write(
        _ composition: AVMutableComposition,
        preset: ExportPreset,
        to destination: URL
    ) async throws -> URL {
        try? FileManager.default.removeItem(at: destination)

        let presetName = preset.format.resolution == .uhd4K
            ? AVAssetExportPreset3840x2160
            : AVAssetExportPreset1920x1080

        guard let session = AVAssetExportSession(asset: composition, presetName: presetName) else {
            throw ComposeError.exportFailed("no export session")
        }

        do {
            try await session.export(to: destination, as: .mov)
        } catch {
            throw ComposeError.exportFailed(error.localizedDescription)
        }
        return destination
    }
}
