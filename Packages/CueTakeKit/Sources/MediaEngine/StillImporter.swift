import AVFoundation
import CoreVideo
import Domain
import Foundation
import ImageIO

extension MediaImporter {
    /// How long a photo stays on screen when it is first put in the video.
    public static let stillSeconds = 4.0
    /// How long the file holds it: a photo clip can be stretched this far with trim.
    public static let stillFileSeconds = 12.0

    /// A photo as a clip: the picture held still in a short movie of its own.
    ///
    /// A clip, rather than a picture laid over one, because that is what someone putting photos
    /// between their videos means: a beat of its own, in order, that can be trimmed, moved, given a
    /// transition or a caption. Made into a movie so everything that edits, plays and exports clips
    /// works on it unchanged. The picture keeps its own shape; the long edge is capped at 1920.
    public func importStill(_ data: Data, into mediaDirectory: URL, title: String) async throws -> ImportedClip {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            // Photos carry their rotation as a flag; the movie needs the picture upright.
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 1920,
        ]
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { throw ImportError.unreadable(mediaDirectory) }

        // Encoders want even sides.
        let width = max(2, image.width & ~1)
        let height = max(2, image.height & ~1)
        let movie = FileManager.default.temporaryDirectory.appending(path: "still-\(UUID().uuidString).mov", directoryHint: .notDirectory)
        try await Self.writeStill(image, width: width, height: height, seconds: Self.stillFileSeconds, to: movie)

        var clip = try await importClip(from: movie, into: mediaDirectory)
        clip.take.sourceRange = MediaTimeRange(start: .zero, duration: MediaTime(seconds: min(Self.stillSeconds, clip.recording.duration.seconds)))
        clip.suggestedTitle = title
        return clip
    }

    /// Ten frames a second of the same picture: plenty for something that does not move, and
    /// quick to write.
    private static func writeStill(_ image: CGImage, width: Int, height: Int, seconds: Double, to url: URL) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
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
        guard writer.canAdd(input) else { throw ImportError.notVideo(url) }
        writer.add(input)
        guard writer.startWriting() else { throw ImportError.notVideo(url) }
        writer.startSession(atSourceTime: .zero)

        var made: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, [
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
            kCVPixelBufferCGImageCompatibilityKey: true,
        ] as CFDictionary, &made)
        guard let buffer = made else { throw ImportError.notVideo(url) }
        CVPixelBufferLockBaseAddress(buffer, [])
        if let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) {
            context.setFillColor(CGColor(gray: 0, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            context.interpolationQuality = .high
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])

        let perSecond: Int32 = 10
        let frames = Int(seconds * Double(perSecond))
        for frame in 0...frames {
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(for: .milliseconds(5))
            }
            guard adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: perSecond)) else {
                throw ImportError.notVideo(url)
            }
        }
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else { throw ImportError.notVideo(url) }
    }
}
