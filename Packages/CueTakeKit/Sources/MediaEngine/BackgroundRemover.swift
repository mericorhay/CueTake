import AVFoundation
import CoreImage
import CoreImage.CIFilterBuiltins
import Domain
import Foundation
import ImageIO
import Vision

/// Cuts the person out of a clip and puts something else behind them.
///
/// Apple's person segmentation, at its highest quality, run on every frame on the device. Chosen
/// over the open-source matting models on purpose: the best of those (Robust Video Matting) is
/// GPL and cannot ship in this app, and the permissive ones would add 50–100 MB to it and still
/// need converting and tuning. This one is built into iOS, works offline, costs nothing per
/// clip, and uses a sequence handler so the edge stays steady from one frame to the next.
///
/// Like a reversed clip, the result is a file written once and cached beside the footage under a
/// key that includes the trimmed range and the choice of background. The sound is not in it: the
/// composer keeps taking the voice from the original recording.
public struct BackgroundRemover: Sendable {
    public init() {}

    public enum RemoveError: Error {
        case noVideoTrack
        case cannotWrite
    }

    /// Where the processed copy of one take lives.
    public static func cachedURL(
        take: Take,
        reversed: Bool,
        background: ClipBackground,
        in directory: URL
    ) -> URL {
        let key = "\(take.id.uuidString)-\(Int(take.sourceRange.start.seconds * 1000))-\(Int(take.sourceRange.duration.seconds * 1000))"
        return directory.appending(
            path: "\(key)\(reversed ? "-rev" : "")-bg-\(background.token).mov",
            directoryHint: .notDirectory
        )
    }

    /// Whether any clip still has to be processed — for telling the user to wait.
    public static func needsWork(for project: Project, in directory: URL) -> Bool {
        project.segments.contains { segment in
            guard let background = segment.background, let take = segment.selectedTake else { return false }
            let url = cachedURL(take: take, reversed: segment.playback.isReversed, background: background, in: directory)
            return !FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
        }
    }

    /// The clip with its background replaced, rendering it the first time. Nil when it cannot be
    /// made, in which case the clip plays as shot.
    public func processedClip(source: URL, range: CMTimeRange, background: ClipBackground, destination: URL) async -> URL? {
        if FileManager.default.fileExists(atPath: destination.path(percentEncoded: false)) {
            return destination
        }
        return await Task.detached(priority: .userInitiated) {
            try? await Self.render(source: source, range: range, background: background, to: destination)
        }.value
    }

    static func render(source: URL, range: CMTimeRange, background: ClipBackground, to destination: URL) async throws -> URL {
        let partial = destination.deletingLastPathComponent()
            .appending(path: "partial-" + destination.lastPathComponent, directoryHint: .notDirectory)
        try? FileManager.default.removeItem(at: partial)

        let asset = AVURLAsset(url: source)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw RemoveError.noVideoTrack }
        let natural = try await track.load(.naturalSize)
        let transform = try await track.load(.preferredTransform)
        let orientation = Self.orientation(of: transform)
        let upright = orientation == .left || orientation == .right
            ? CGSize(width: natural.height, height: natural.width)
            : natural
        let width = Int(upright.width) / 2 * 2
        let height = Int(upright.height) / 2 * 2

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

        let context = CIContext(options: [.cacheIntermediates: false])
        let request = VNGeneratePersonSegmentationRequest()
        request.qualityLevel = .accurate
        request.outputPixelFormat = kCVPixelFormatType_OneComponent8
        // A sequence handler, not one handler per frame: it carries what it learned about the
        // person from frame to frame, which is what keeps the outline from shimmering.
        let sequence = VNSequenceRequestHandler()
        let bounds = CGRect(x: 0, y: 0, width: width, height: height)

        while let sample = output.copyNextSampleBuffer() {
            guard let pixels = CMSampleBufferGetImageBuffer(sample) else { continue }
            let time = CMSampleBufferGetPresentationTimeStamp(sample) - range.start

            let frame = CIImage(cvPixelBuffer: pixels).oriented(orientation)
            let placed = frame.transformed(by: CGAffineTransform(translationX: -frame.extent.minX, y: -frame.extent.minY))
                .cropped(to: bounds)

            try sequence.perform([request], on: placed)
            guard let maskBuffer = request.results?.first?.pixelBuffer else { continue }
            let mask = CIImage(cvPixelBuffer: maskBuffer)
            let fitted = mask.transformed(by: CGAffineTransform(
                scaleX: bounds.width / mask.extent.width,
                y: bounds.height / mask.extent.height
            ))

            let blend = CIFilter.blendWithMask()
            blend.inputImage = placed
            blend.backgroundImage = Self.backdrop(background, behind: placed, in: bounds)
            blend.maskImage = fitted
            guard let composed = blend.outputImage?.cropped(to: bounds),
                  let pool = adaptor.pixelBufferPool
            else { continue }

            var outputBuffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &outputBuffer)
            guard let outputBuffer else { continue }
            context.render(composed, to: outputBuffer)

            while !input.isReadyForMoreMediaData {
                try await Task.sleep(for: .milliseconds(4))
            }
            adaptor.append(outputBuffer, withPresentationTime: time)
        }

        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed, reader.status == .completed else {
            try? FileManager.default.removeItem(at: partial)
            throw RemoveError.cannotWrite
        }
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: partial, to: destination)
        return destination
    }

    private static func backdrop(_ background: ClipBackground, behind frame: CIImage, in bounds: CGRect) -> CIImage {
        switch background {
        case .blur:
            return frame.clampedToExtent().applyingGaussianBlur(sigma: 28).cropped(to: bounds)
        case .black:
            return CIImage(color: CIColor(red: 0, green: 0, blue: 0)).cropped(to: bounds)
        case .white:
            return CIImage(color: CIColor(red: 1, green: 1, blue: 1)).cropped(to: bounds)
        case .green:
            return CIImage(color: CIColor(red: 0, green: 0.8, blue: 0.25)).cropped(to: bounds)
        case .studio:
            let gradient = CIFilter.radialGradient()
            gradient.center = CGPoint(x: bounds.midX, y: bounds.height * 0.6)
            gradient.radius0 = Float(min(bounds.width, bounds.height) * 0.1)
            gradient.radius1 = Float(max(bounds.width, bounds.height) * 0.75)
            gradient.color0 = CIColor(red: 0.2, green: 0.21, blue: 0.25)
            gradient.color1 = CIColor(red: 0.03, green: 0.03, blue: 0.04)
            return (gradient.outputImage ?? CIImage(color: .black)).cropped(to: bounds)
        }
    }

    /// The rotation a track's transform asks for, as an image orientation. Mirroring is ignored:
    /// the frames are written upright and the composer fits them like any other clip.
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
