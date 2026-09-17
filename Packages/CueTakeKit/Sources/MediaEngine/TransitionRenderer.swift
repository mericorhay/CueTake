import AVFoundation
import CoreImage
import CryptoKit
import Domain
import Foundation

/// Transitions as short rendered films, laid over their cuts.
///
/// Each cut's transition is drawn once, frame by frame, from the finished picture of the edit
/// without transitions — framing, zoom, tracking and added videos already in it — and written
/// beside the footage. The composition then plays that film over the cut exactly like an added
/// video. There is no second clip track, no animated instruction and no custom drawing at play
/// time, which is what made the first version fail on the phone: the player stopped at every cut
/// and the clip after it lost its framing.
///
/// The leaving clip holds its last frame after the cut and the arriving clip its first frame
/// before it, so the video keeps its length and nothing else on the timeline moves.
public enum TransitionRenderer {
    public struct Job: Hashable, Sendable {
        /// The file, in the project's media folder.
        public var name: String
        public var destination: URL
        public var kind: ClipTransition.Kind
        /// Seconds on the finished video.
        public var start: Double
        public var cut: Double
        public var end: Double

        public var isReady: Bool {
            ((try? destination.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0) > 0
        }
    }

    public enum RenderError: Error {
        case noPicture
        case cannotWrite
        case cancelled
    }

    /// The edit a transition is drawn from: no transitions, and no filters — the filters are laid
    /// over the finished frame, the transition film included, so they are not applied twice.
    public static func base(of project: Project) -> Project {
        var base = project
        base.transitions = []
        base.effects = project.effects.filter { $0.filter == nil }
        return base
    }

    /// Every transition film the project needs, whether written yet or not.
    public static func jobs(for project: Project, in directory: URL) -> [Job] {
        guard !project.transitions.isEmpty, project.segments.count > 1 else { return [] }
        let fingerprint = fingerprint(of: base(of: project))
        var jobs: [Job] = []
        var time = 0.0
        var lastEnd = 0.0
        let segments = project.segments
        for index in segments.indices.dropLast() {
            let outgoing = segments[index]
            let incoming = segments[index + 1]
            time += outgoing.barWeight
            guard let transition = project.transition(after: outgoing.id),
                  outgoing.selectedTake != nil, incoming.selectedTake != nil
            else { continue }
            let seconds = ClipTransition.usableDuration(transition.duration, outgoing: outgoing.barWeight, incoming: incoming.barWeight)
            guard seconds >= 0.1 else { continue }
            let start = max(0, time - seconds / 2)
            guard start >= lastEnd - 0.0001 else { continue }
            let end = time + seconds / 2
            lastEnd = end
            let token = hex("\(fingerprint)|\(index)|\(transition.kind.rawValue)|\(Int((seconds * 1000).rounded()))").prefix(20)
            let name = "transition-\(token).mov"
            jobs.append(Job(
                name: name,
                destination: directory.appending(path: name, directoryHint: .notDirectory),
                kind: transition.kind,
                start: start,
                cut: time,
                end: end
            ))
        }
        return jobs
    }

    /// The project as the composer should play it: each written transition film as a silent added
    /// video over its cut, on top of everything else. Cuts whose film is not written yet stay cuts.
    public static func layered(_ project: Project, in directory: URL) -> Project {
        var result = project
        result.transitions = []
        for job in jobs(for: project, in: directory) where job.isReady {
            let id = uuid(for: job.name)
            var recording = Recording(
                id: id,
                relativePath: job.name,
                format: project.format,
                camera: .back,
                duration: MediaTime(seconds: job.end - job.start)
            )
            recording.reframe = nil
            result.recordings.append(recording)
            var layer = VideoLayer(
                id: id,
                recordingID: id,
                title: job.name,
                start: MediaTime(seconds: job.start),
                sourceRange: MediaTimeRange(start: .zero, duration: MediaTime(seconds: job.end - job.start)),
                placement: VideoPlacement(fillsFrame: true)
            )
            layer.isMuted = true
            layer.volume = 0
            result.videoLayers.append(layer)
        }
        return result
    }

    /// Writes the films that are missing. Failures are skipped: a cut is a fine fallback.
    /// Off the caller's actor: the editor asks from the main one.
    @concurrent
    public static func renderMissing(
        for project: Project,
        in directory: URL,
        renderBackgrounds: Bool = true,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async {
        let missing = jobs(for: project, in: directory).filter { !$0.isReady }
        guard !missing.isEmpty else { return }
        guard var assembled = try? await VideoComposer().compose(
            project: base(of: project),
            mediaDirectory: directory,
            renderBackgrounds: renderBackgrounds
        ) else { return }
        VideoComposer.pruneEmptyTracks(&assembled)
        for (index, job) in missing.enumerated() {
            if Task.isCancelled { return }
            _ = try? await render(job, from: assembled)
            progress?(Double(index + 1) / Double(missing.count))
        }
    }

    /// One transition film.
    static func render(_ job: Job, from assembled: VideoComposer.Assembled) async throws -> URL {
        let composition = assembled.composition
        let videoComposition = assembled.videoComposition
        let size = videoComposition.renderSize
        let width = max(2, Int(size.width) / 2 * 2)
        let height = max(2, Int(size.height) / 2 * 2)
        let bounds = CGRect(x: 0, y: 0, width: width, height: height)
        let frame = videoComposition.frameDuration.isValid && videoComposition.frameDuration.seconds > 0
            ? videoComposition.frameDuration
            : CMTime(value: 1, timescale: 30)
        let total = composition.duration.seconds
        let start = CMTime(seconds: max(0, job.start), preferredTimescale: 600)
        let end = CMTime(seconds: min(job.end, total), preferredTimescale: 600)
        let cut = CMTime(seconds: min(job.cut, total), preferredTimescale: 600)
        guard end > start, cut > start else { throw RenderError.noPicture }
        let videoTracks = composition.tracks(withMediaType: .video)
        guard !videoTracks.isEmpty else { throw RenderError.noPicture }

        // The frames either side of the cut, held while the other clip moves.
        let generator = AVAssetImageGenerator(asset: composition)
        generator.videoComposition = videoComposition
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        generator.maximumSize = size
        let lastBefore = try await generator.image(at: CMTimeMaximum(start, cut - frame)).image
        let firstAfter = try await generator.image(at: cut).image
        let leaving = fitted(CIImage(cgImage: lastBefore), to: bounds)
        let arriving = fitted(CIImage(cgImage: firstAfter), to: bounds)

        let partial = job.destination.deletingLastPathComponent().appending(
            path: "partial-\(UUID().uuidString)-\(job.name)",
            directoryHint: .notDirectory
        )
        defer { try? FileManager.default.removeItem(at: partial) }

        let reader = try AVAssetReader(asset: composition)
        reader.timeRange = CMTimeRange(start: start, end: end)
        let output = AVAssetReaderVideoCompositionOutput(
            videoTracks: videoTracks,
            videoSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        )
        output.videoComposition = videoComposition
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { throw RenderError.cannotWrite }
        reader.add(output)

        let writer = try AVAssetWriter(outputURL: partial, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
        ])
        guard writer.canAdd(input) else { throw RenderError.cannotWrite }
        writer.add(input)
        guard reader.startReading(), writer.startWriting() else { throw RenderError.cannotWrite }
        writer.startSession(atSourceTime: .zero)

        func fail(_ error: RenderError) -> RenderError {
            reader.cancelReading()
            writer.cancelWriting()
            return error
        }

        let context = CIContext(options: [.cacheIntermediates: false])
        let background = CIImage(color: job.kind == .fadeWhite ? CIColor(red: 1, green: 1, blue: 1) : CIColor(red: 0, green: 0, blue: 0))
            .cropped(to: bounds)
        let length = (end - start).seconds
        var lastTime = CMTime.invalid
        var written = 0

        enum Frame {
            case end, skip
            case ready(CVPixelBuffer, CMTime)
        }

        frames: while true {
            if Task.isCancelled { throw fail(.cancelled) }
            let next: Frame = try autoreleasepool {
                guard let sample = output.copyNextSampleBuffer() else { return .end }
                guard let pixels = CMSampleBufferGetImageBuffer(sample) else { return .skip }
                let time = CMSampleBufferGetPresentationTimeStamp(sample)
                let local = time - start
                guard local.seconds >= 0, !lastTime.isValid || local > lastTime else { return .skip }

                let picture = fitted(CIImage(cvPixelBuffer: pixels), to: bounds)
                let beforeCut = time < cut
                let look = TransitionLook.at(TransitionLook.eased(local.seconds / length), kind: job.kind)
                let pair = [
                    (beforeCut ? picture : leaving, look.outgoing),
                    (beforeCut ? arriving : picture, look.incoming),
                ]
                var composed = background
                for (image, move) in look.incomingOnTop ? pair : Array(pair.reversed()) {
                    if let moved = FilterCompositor.apply(move, to: image, in: bounds.size) {
                        composed = moved.composited(over: composed)
                    }
                }

                guard let pool = adaptor.pixelBufferPool else { throw fail(.cannotWrite) }
                var buffer: CVPixelBuffer?
                CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
                guard let buffer else { throw fail(.cannotWrite) }
                context.render(composed.cropped(to: bounds), to: buffer, bounds: bounds, colorSpace: CGColorSpaceCreateDeviceRGB())
                return .ready(buffer, local)
            }

            let buffer: CVPixelBuffer
            let time: CMTime
            switch next {
            case .end: break frames
            case .skip: continue frames
            case let .ready(ready, at):
                buffer = ready
                time = at
            }
            var waited = 0
            while !input.isReadyForMoreMediaData {
                if writer.status == .failed || Task.isCancelled || waited > 5000 { throw fail(.cannotWrite) }
                try? await Task.sleep(for: .milliseconds(2))
                waited += 1
            }
            guard adaptor.append(buffer, withPresentationTime: time) else { throw fail(.cannotWrite) }
            lastTime = time
            written += 1
        }

        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed, reader.status == .completed, written > 0 else {
            throw fail(.cannotWrite)
        }
        try? FileManager.default.removeItem(at: job.destination)
        try FileManager.default.moveItem(at: partial, to: job.destination)
        return job.destination
    }

    /// A frame scaled to exactly the render size, origin at zero.
    static func fitted(_ image: CIImage, to bounds: CGRect) -> CIImage {
        let extent = image.extent
        guard extent.width > 0, extent.height > 0 else { return image }
        var placed = image.transformed(by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY))
        if abs(extent.width - bounds.width) > 0.5 || abs(extent.height - bounds.height) > 0.5 {
            placed = placed.transformed(by: CGAffineTransform(scaleX: bounds.width / extent.width, y: bounds.height / extent.height))
        }
        return placed.cropped(to: bounds)
    }

    /// What the finished picture of an edit depends on, as a short stable string. Anything that
    /// cannot change a frame (titles, dates, captions, sound) is left out, so editing those does
    /// not redraw the transitions.
    static func fingerprint(of project: Project) -> String {
        var stripped = project
        stripped.title = ""
        stripped.createdAt = Date(timeIntervalSince1970: 0)
        stripped.updatedAt = Date(timeIntervalSince1970: 0)
        stripped.metadata = [:]
        stripped.aiConversations = []
        stripped.audio = []
        stripped.overlays = []
        stripped.captionWindow = nil
        stripped.effects = project.effects.filter { $0.background != nil }
        for index in stripped.segments.indices {
            stripped.segments[index].captions = []
        }
        for index in stripped.recordings.indices {
            stripped.recordings[index].speech = nil
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .secondsSince1970
        let data = (try? encoder.encode(stripped)) ?? Data()
        return hex(data)
    }

    static func hex(_ text: String) -> String {
        hex(Data(text.utf8))
    }

    static func hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// A stable id from a file name, so the same film is the same added video on every rebuild.
    static func uuid(for name: String) -> UUID {
        var bytes = Array(SHA256.hash(data: Data(name.utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x40
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }
}
