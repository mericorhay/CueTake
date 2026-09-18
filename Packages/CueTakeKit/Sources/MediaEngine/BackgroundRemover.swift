import AVFoundation
import CoreImage
import CoreImage.CIFilterBuiltins
import Domain
import Foundation
import ImageIO
import Vision

/// Cuts the person out of a clip and puts something else behind them.
///
/// Apple's on-device person segmentation, run on every frame with a sequence handler so the edge
/// stays steady from one frame to the next. Chosen over open-source matting models on purpose: the
/// best of those (Robust Video Matting) is GPL and cannot ship in this app, and the permissive ones
/// would add 50–100 MB and still need converting and tuning.
///
/// Rendered once per take, range and look, and cached beside the footage. The render never runs
/// inside a preview build — it used to, and a render that stalled took the preview down with it —
/// the editor renders in the background with progress and switches the preview over when done.
/// The sound is not in the file: the composer keeps the voice from the original recording.
public struct BackgroundRemover: Sendable {
    public init() {}

    public enum RemoveError: Error {
        case noVideoTrack
        case cannotWrite
        case cancelled
    }

    /// The long side of the processed picture. Past this the phone heats up for detail nobody sees
    /// behind a person; the composer scales it into the frame like any clip.
    static let longestSide: CGFloat = 1920

    /// The file name of the processed copy of one take: the whole take, so moving or stretching an
    /// effect inside it never needs a new render.
    public static func cacheName(take: Take, reversed: Bool, settings: BackgroundSettings) -> String {
        "\(VideoReverser.key(for: take))\(reversed ? "-rev" : "")-bg-\(settings.token).mov"
    }

    public static func cachedURL(take: Take, reversed: Bool, settings: BackgroundSettings, in directory: URL) -> URL {
        directory.appending(path: cacheName(take: take, reversed: reversed, settings: settings), directoryHint: .notDirectory)
    }

    /// One processed copy a project needs.
    public struct Job: Hashable, Sendable {
        public var name: String
        /// The picture it is made from: the recording, or the clip's reversed copy.
        public var source: URL
        public var range: CMTimeRange
        public var settings: BackgroundSettings
        public var destination: URL
        /// The reversed copy it is made from has not been written yet.
        public var waitsForReverse: Bool
    }

    /// Every processed copy the project's background effects need, whether or not it exists yet.
    public static func jobs(for project: Project, in mediaDirectory: URL) -> [Job] {
        var result: [Job] = []
        var names = Set<String>()
        for (index, segment) in project.segments.enumerated() {
            let wanted = project.backgrounds(ofSegmentAt: index)
            guard !wanted.isEmpty,
                  let take = segment.selectedTake,
                  let recording = project.recording(id: take.recordingID)
            else { continue }
            let reversed = segment.playback.isReversed && segment.playback.freeze == nil
            let length = CMTime(seconds: take.sourceRange.duration.seconds, preferredTimescale: 600)
            let source: URL
            let range: CMTimeRange
            var waits = false
            if reversed {
                source = VideoReverser.cachedURL(for: take, in: mediaDirectory)
                range = CMTimeRange(start: .zero, duration: length)
                waits = !FileManager.default.fileExists(atPath: source.path(percentEncoded: false))
            } else {
                source = mediaDirectory.appending(
                    path: (recording.relativePath as NSString).lastPathComponent,
                    directoryHint: .notDirectory
                )
                range = CMTimeRange(start: CMTime(seconds: take.sourceRange.start.seconds, preferredTimescale: 600), duration: length)
            }
            for settings in wanted {
                let name = cacheName(take: take, reversed: reversed, settings: settings)
                guard names.insert(name).inserted else { continue }
                result.append(Job(
                    name: name,
                    source: source,
                    range: range,
                    settings: settings,
                    destination: mediaDirectory.appending(path: name, directoryHint: .notDirectory),
                    waitsForReverse: waits
                ))
            }
        }
        return result
    }

    /// Renders the processed copy if it is not there yet. Nil when it could not be made.
    ///
    /// - Parameter progress: 0…1, called from the render's own thread.
    /// Runs off the caller's actor and stops when the task that asked is cancelled.
    @concurrent
    public func render(
        source: URL,
        range: CMTimeRange,
        settings: BackgroundSettings,
        destination: URL,
        progress: @escaping @Sendable (Double) -> Void = { _ in }
    ) async -> URL? {
        if Self.isUsableCache(destination) {
            return destination
        }
        return try? await Self.render(source: source, range: range, settings: settings, to: destination, progress: progress)
    }

    static func render(
        source: URL,
        range: CMTimeRange,
        settings: BackgroundSettings,
        to destination: URL,
        progress: @Sendable (Double) -> Void
    ) async throws -> URL {
        let partial = destination.deletingLastPathComponent().appending(
            path: "partial-\(UUID().uuidString)-\(destination.lastPathComponent)",
            directoryHint: .notDirectory
        )
        defer { try? FileManager.default.removeItem(at: partial) }

        let asset = AVURLAsset(url: source)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw RemoveError.noVideoTrack }
        let natural = try await track.load(.naturalSize)
        let transform = try await track.load(.preferredTransform)
        let frameRate = Double(try await track.load(.nominalFrameRate))
        let orientation = Self.orientation(of: transform)
        let upright = orientation == .left || orientation == .right
            ? CGSize(width: natural.height, height: natural.width)
            : natural
        let factor = min(1, longestSide / max(upright.width, upright.height, 1))
        let width = max(2, Int(upright.width * factor) / 2 * 2)
        let height = max(2, Int(upright.height * factor) / 2 * 2)
        let expectedFrames = max(1, range.duration.seconds * max(frameRate, 24))

        let reader = try AVAssetReader(asset: asset)
        reader.timeRange = range
        let output = AVAssetReaderTrackOutput(
            track: track,
            outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        )
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { throw RemoveError.cannotWrite }
        reader.add(output)

        let writer = try AVAssetWriter(outputURL: partial, fileType: .mov)
        let input = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.hevc,
                AVVideoWidthKey: width,
                AVVideoHeightKey: height,
            ]
        )
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
            ]
        )
        guard writer.canAdd(input) else { throw RemoveError.cannotWrite }
        writer.add(input)

        guard reader.startReading(), writer.startWriting() else { throw RemoveError.cannotWrite }
        writer.startSession(atSourceTime: .zero)

        func fail(_ error: RemoveError) -> RemoveError {
            reader.cancelReading()
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: partial)
            return error
        }

        let context = CIContext(options: [.cacheIntermediates: false])
        let request = VNGeneratePersonSegmentationRequest()
        // Balanced is Apple's setting for video: steady from frame to frame at a heat a phone can hold.
        request.qualityLevel = settings.fineEdges ? .accurate : .balanced
        request.outputPixelFormat = kCVPixelFormatType_OneComponent8
        let sequence = VNSequenceRequestHandler()
        let bounds = CGRect(x: 0, y: 0, width: width, height: height)
        var lastTime = CMTime.invalid
        var written = 0.0
        // The last frame's subject mask, already settled, which the next one is eased toward.
        var previousSubject: CIImage?

        enum Frame {
            case end, skip
            case ready(CVPixelBuffer, CMTime)
        }

        frames: while true {
            if Task.isCancelled { throw fail(.cancelled) }
            // Every frame in its own pool. Without it the decoded 4K frames, masks and Core Image
            // intermediates of the whole clip piled up until the render ran the phone out of
            // memory — which took the preview player, decoding beside it, down too.
            let frame: Frame = try autoreleasepool {
                guard let sample = output.copyNextSampleBuffer() else { return .end }
                guard let pixels = CMSampleBufferGetImageBuffer(sample) else { return .skip }
                // The reader can hand back a frame from just before the range; a negative or repeated
                // time makes the writer fail, and a failed writer never becomes ready again.
                let time = CMSampleBufferGetPresentationTimeStamp(sample) - range.start
                guard time.seconds >= 0, !lastTime.isValid || time > lastTime else { return .skip }

                let oriented = CIImage(cvPixelBuffer: pixels).oriented(orientation)
                let placed = oriented
                    .transformed(by: CGAffineTransform(translationX: -oriented.extent.minX, y: -oriented.extent.minY))
                    .transformed(by: CGAffineTransform(scaleX: CGFloat(width) / oriented.extent.width, y: CGFloat(height) / oriented.extent.height))
                    .cropped(to: bounds)

                let composed: CIImage
                if settings.cutout == .color {
                    // A keyed colour needs no mask of its own: the cube makes the screen see-through.
                    let keyed = ChromaCubes.shared.apply(settings.effectiveKey, to: placed)
                    composed = keyed.composited(over: Self.backdrop(settings, behind: placed, in: bounds)).cropped(to: bounds)
                } else if let mask = settings.cutout == .subject
                    ? Self.subjectMask(of: placed, in: bounds, after: &previousSubject, context: context)
                    : Self.personMask(of: placed, in: bounds, request: request, sequence: sequence) {
                    var fitted = mask
                    // A soft edge: the mask blurred a little, so hair and shoulders fade into the new
                    // background instead of looking cut out with scissors.
                    if settings.feather > 0.01 {
                        let radius = settings.feather * Double(min(width, height)) * 0.012
                        fitted = fitted.clampedToExtent().applyingGaussianBlur(sigma: radius).cropped(to: bounds)
                    }
                    let blend = CIFilter.blendWithMask()
                    blend.inputImage = placed
                    blend.backgroundImage = Self.backdrop(settings, behind: placed, in: bounds)
                    blend.maskImage = fitted
                    composed = blend.outputImage?.cropped(to: bounds) ?? placed
                } else {
                    // Nothing found in this frame: the frame as it is, so the clip never skips.
                    composed = placed
                }

                guard let pool = adaptor.pixelBufferPool else { throw fail(.cannotWrite) }
                var outputBuffer: CVPixelBuffer?
                CVPixelBufferPoolCreatePixelBuffer(nil, pool, &outputBuffer)
                guard let outputBuffer else { throw fail(.cannotWrite) }
                context.render(composed, to: outputBuffer)
                return .ready(outputBuffer, time)
            }

            let outputBuffer: CVPixelBuffer
            let time: CMTime
            switch frame {
            case .end: break frames
            case .skip: continue frames
            case let .ready(buffer, at):
                outputBuffer = buffer
                time = at
            }

            var waited = 0
            while !input.isReadyForMoreMediaData {
                if writer.status == .failed || Task.isCancelled || waited > 5000 { throw fail(.cannotWrite) }
                try? await Task.sleep(for: .milliseconds(2))
                waited += 1
            }
            guard adaptor.append(outputBuffer, withPresentationTime: time) else { throw fail(.cannotWrite) }
            lastTime = time
            written += 1
            if Int(written) % 10 == 0 { progress(min(0.99, written / expectedFrames)) }
        }

        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed, reader.status == .completed, written > 0 else {
            throw fail(.cannotWrite)
        }
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: partial, to: destination)
        progress(1)
        return destination
    }

    /// The people in a frame, scaled to it. Nil when there is no one.
    static func personMask(
        of frame: CIImage,
        in bounds: CGRect,
        request: VNGeneratePersonSegmentationRequest,
        sequence: VNSequenceRequestHandler
    ) -> CIImage? {
        guard (try? sequence.perform([request], on: frame)) != nil,
              let buffer = request.results?.first?.pixelBuffer
        else { return nil }
        return fit(CIImage(cvPixelBuffer: buffer), to: bounds)
    }

    /// Everything that stands out in front of a frame, scaled to it. Nil when nothing does.
    ///
    /// The foreground mask is made for photos and knows nothing of the frame before, so its edge
    /// would shimmer from frame to frame. Each mask is eased a third of the way back toward the
    /// last one, and the result drawn out to pixels so the next frame blends with a picture, not
    /// with a chain of every frame before it.
    static func subjectMask(
        of frame: CIImage,
        in bounds: CGRect,
        after previous: inout CIImage?,
        context: CIContext
    ) -> CIImage? {
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(ciImage: frame)
        guard (try? handler.perform([request])) != nil,
              let observation = request.results?.first,
              !observation.allInstances.isEmpty,
              let buffer = try? observation.generateScaledMaskForImage(forInstances: observation.allInstances, from: handler)
        else {
            previous = nil
            return nil
        }
        var mask = fit(CIImage(cvPixelBuffer: buffer), to: bounds)
        if let previous {
            mask = previous.applyingFilter("CIDissolveTransition", parameters: [
                kCIInputTargetImageKey: mask,
                kCIInputTimeKey: 0.67,
            ]).cropped(to: bounds)
        }
        // Only a mask drawn out to pixels is kept: keeping the recipe instead would chain every
        // frame of the clip into the next one.
        if let settled = context.createCGImage(mask, from: bounds, format: .L8, colorSpace: CGColorSpaceCreateDeviceGray()) {
            mask = CIImage(cgImage: settled)
            previous = mask
        } else {
            previous = nil
        }
        return mask
    }

    private static func fit(_ mask: CIImage, to bounds: CGRect) -> CIImage {
        mask
            .transformed(by: CGAffineTransform(translationX: -mask.extent.minX, y: -mask.extent.minY))
            .transformed(by: CGAffineTransform(
                scaleX: bounds.width / max(mask.extent.width, 1),
                y: bounds.height / max(mask.extent.height, 1)
            ))
            .cropped(to: bounds)
    }

    static func isUsableCache(_ url: URL) -> Bool {
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else { return false }
        return size > 0
    }

    private static func backdrop(_ settings: BackgroundSettings, behind frame: CIImage, in bounds: CGRect) -> CIImage {
        func solid(_ red: Double, _ green: Double, _ blue: Double) -> CIImage {
            CIImage(color: CIColor(red: red, green: green, blue: blue)).cropped(to: bounds)
        }
        switch settings.style {
        case .blur:
            // Strength 0 is a gentle softening, 1 is the room gone to shapes.
            let sigma = (4 + settings.strength * 56) * Double(min(bounds.width, bounds.height)) / 1080
            return frame.clampedToExtent().applyingGaussianBlur(sigma: sigma).cropped(to: bounds)
        case .dim:
            return frame.applyingFilter("CIColorControls", parameters: [
                kCIInputBrightnessKey: -0.5 * settings.strength,
                kCIInputSaturationKey: 1 - 0.6 * settings.strength,
            ]).cropped(to: bounds)
        case .black:
            return solid(0, 0, 0)
        case .white:
            return solid(1, 1, 1)
        case .green:
            return solid(0, 0.8, 0.25)
        case .color:
            let color = settings.color ?? RGBAColor(red: 0.1, green: 0.1, blue: 0.12)
            return solid(color.red, color.green, color.blue)
        case .studio:
            let gradient = CIFilter.radialGradient()
            gradient.center = CGPoint(x: bounds.midX, y: bounds.height * 0.6)
            gradient.radius0 = Float(min(bounds.width, bounds.height) * 0.1)
            gradient.radius1 = Float(max(bounds.width, bounds.height) * 0.75)
            gradient.color0 = CIColor(red: 0.2, green: 0.21, blue: 0.25)
            gradient.color1 = CIColor(red: 0.03, green: 0.03, blue: 0.04)
            return (gradient.outputImage ?? CIImage(color: CIColor(red: 0, green: 0, blue: 0))).cropped(to: bounds)
        }
    }

    /// The rotation a track's transform asks for, as an image orientation.
    static func orientation(of transform: CGAffineTransform) -> CGImagePropertyOrientation {
        let degrees = atan2(transform.b, transform.a) * 180 / .pi
        switch Int(degrees.rounded()) {
        case 90: return .right
        case -90: return .left
        case 180, -180: return .down
        default: return .up
        }
    }
}
