import AVFoundation
import Domain
import Foundation

/// Builds the finished video out of the timeline, and writes it to a file.
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

    /// A composition plus the instructions that say how each clip is framed inside it.
    public struct Assembled: @unchecked Sendable {
        public var composition: AVMutableComposition
        /// Travels with the composition everywhere. The export needs it, and so does the preview,
        /// or the editor shows something the exported file will not match.
        public var videoComposition: AVMutableVideoComposition
    }

    /// Assembles the project's selected takes, in segment order.
    ///
    /// - Parameter mediaDirectory: where `Recording.relativePath` resolves against. The document
    ///   stores paths relative to the project because the container path changes between installs.
    public func compose(project: Project, mediaDirectory: URL) async throws -> Assembled {
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
        let renderSize = CGSize(
            width: CGFloat(project.format.renderSize.width),
            height: CGFloat(project.format.renderSize.height)
        )

        var cursor = CMTime.zero
        var instructions: [AVMutableVideoCompositionInstruction] = []

        for segment in project.segments {
            guard let take = segment.selectedTake,
                  let recording = recordings[take.recordingID]
            else { continue }

            let url = mediaDirectory.appending(
                path: (recording.relativePath as NSString).lastPathComponent,
                directoryHint: .notDirectory
            )
            let asset = AVURLAsset(url: url)

            guard let sourceVideo = try await asset.loadTracks(withMediaType: .video).first else {
                throw ComposeError.noVideoTrack(recording.id)
            }

            // Clamped to what the file actually contains. Trimming a segment longer than its
            // recording asked AVFoundation for time that does not exist, which it answers by
            // trapping — that was the crash on export.
            let assetDuration = try await asset.load(.duration)
            let start = CMTime(seconds: take.sourceRange.start.seconds, preferredTimescale: 600)
            guard start < assetDuration else { continue }
            let wanted = CMTime(seconds: take.sourceRange.duration.seconds, preferredTimescale: 600)
            let range = CMTimeRange(start: start, duration: min(wanted, assetDuration - start))
            guard range.duration.seconds > 0.01 else { continue }

            try videoTrack.insertTimeRange(range, of: sourceVideo, at: cursor)
            // Audio is optional on purpose: a clip with no audio track is a legitimate thing to
            // put in a video, and refusing the whole export over it would be absurd.
            if let sourceAudio = try await asset.loadTracks(withMediaType: .audio).first {
                try? audioTrack.insertTimeRange(range, of: sourceAudio, at: cursor)
            }

            let natural = try await sourceVideo.load(.naturalSize)
            let preferred = try await sourceVideo.load(.preferredTransform)

            let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)
            layer.setTransform(Self.fit(natural: natural, preferred: preferred, into: renderSize), at: cursor)

            let instruction = AVMutableVideoCompositionInstruction()
            instruction.timeRange = CMTimeRange(start: cursor, duration: range.duration)
            instruction.layerInstructions = [layer]
            instructions.append(instruction)

            cursor = cursor + range.duration
        }

        guard !instructions.isEmpty else { throw ComposeError.nothingToCompose }

        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = renderSize
        videoComposition.frameDuration = CMTime(
            value: 1,
            timescale: CMTimeScale(max(24, project.format.frameRate))
        )
        videoComposition.instructions = instructions

        return Assembled(composition: composition, videoComposition: videoComposition)
    }

    /// Places one clip inside the render frame.
    ///
    /// Fit rather than fill. Filling a landscape clip into a vertical frame throws away three
    /// quarters of the width, which on a talking-head shot means throwing away the head. Bars are
    /// honest about what the footage is; a crop silently destroys the take. Per-clip crop and zoom
    /// belong to the user, not to an exporter acting behind their back.
    ///
    /// `preferredTransform` is applied first — it is what makes a portrait clip portrait, and
    /// ignoring it is why footage comes back sideways — and its origin is normalised, because a
    /// rotation leaves the content sitting in negative space.
    static func fit(natural: CGSize, preferred: CGAffineTransform, into render: CGSize) -> CGAffineTransform {
        let rotated = CGRect(origin: .zero, size: natural).applying(preferred)
        let display = CGSize(width: abs(rotated.width), height: abs(rotated.height))
        guard display.width > 0, display.height > 0, render.width > 0, render.height > 0 else {
            return preferred
        }

        let scale = min(render.width / display.width, render.height / display.height)
        let scaled = CGSize(width: display.width * scale, height: display.height * scale)

        return preferred
            .concatenating(CGAffineTransform(translationX: -rotated.origin.x, y: -rotated.origin.y))
            .concatenating(CGAffineTransform(scaleX: scale, y: scale))
            .concatenating(
                CGAffineTransform(
                    translationX: (render.width - scaled.width) / 2,
                    y: (render.height - scaled.height) / 2
                )
            )
    }

    /// Writes the assembled video to a file, reporting real progress as it goes.
    ///
    /// - Parameter onProgress: called on the main actor with 0...1. The export screen used to
    ///   advance on a timer, which finished before the file did on anything long.
    public func write(
        _ assembled: Assembled,
        to destination: URL,
        onProgress: (@MainActor @Sendable (Double) -> Void)? = nil
    ) async throws -> URL {
        try? FileManager.default.removeItem(at: destination)

        // A passthrough preset ignores the video composition and hands back the source frames,
        // sideways and unscaled. The render size lives in the composition, so the preset only has
        // to be one that re-encodes.
        guard let session = AVAssetExportSession(
            asset: assembled.composition,
            presetName: AVAssetExportPresetHighestQuality
        ) else {
            throw ComposeError.exportFailed("no export session")
        }
        session.videoComposition = assembled.videoComposition

        // `AVAssetExportSession` is not Sendable, so the polling task cannot hold it. Reading one
        // atomic float from another thread is safe in a way the type system has no way to express,
        // and this box says so once rather than scattering the claim.
        let reader = ProgressReader(session: session)
        let reporter: Task<Void, Never>? = onProgress.map { report in
            Task {
                while !Task.isCancelled {
                    let value = reader.value
                    await report(value)
                    if value >= 0.999 { return }
                    try? await Task.sleep(for: .milliseconds(120))
                }
            }
        }
        defer { reporter?.cancel() }

        do {
            try await session.export(to: destination, as: .mov)
        } catch {
            throw ComposeError.exportFailed(error.localizedDescription)
        }
        return destination
    }
}

/// Reads an export session's progress from another task.
private struct ProgressReader: @unchecked Sendable {
    let session: AVAssetExportSession
    var value: Double { Double(session.progress) }
}
