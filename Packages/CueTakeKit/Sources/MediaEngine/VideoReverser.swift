import AVFoundation
import Foundation

/// Writes a clip backwards.
///
/// This is the one effect in the app that cannot be expressed as a composition. Speed is a scaled
/// time range and a freeze is a one-frame range held open, but reversing means handing the decoder
/// frames in an order the file does not contain — inter-frame compression makes every frame depend
/// on the ones before it, so the only way back is to decode forwards and write out in reverse.
///
/// Done in chunks sized by a memory budget rather than by a fixed number of frames: a second of
/// 1080p is 47 MB of decoded video and a second of 8K is a gigabyte and a half. A fixed chunk
/// either wastes the small case or kills the app on the large one, so the chunk is whatever fits
/// in 192 MB at this clip's resolution — three frames at 8K, a hundred at 1080p.
///
/// The result is cached next to the media under a key that includes the trimmed range, so
/// scrubbing a reversed clip costs nothing after the first time, and the original is untouched.
public struct VideoReverser: Sendable {
    public init() {}

    public enum ReverseError: Error {
        case noVideoTrack
        case cannotWrite
    }

    /// Roughly what a phone can hold without being killed for it.
    static let memoryBudget = 192_000_000

    /// The reversed version of one clip, rendering it if this is the first time.
    ///
    /// Returns nil rather than throwing: a reverse that could not be made should leave the clip
    /// playing forwards, not stop the whole composition from being built.
    public func reversedClip(
        source: URL,
        range: CMTimeRange,
        key: String,
        in directory: URL
    ) async -> URL? {
        let destination = directory.appending(path: "\(key)-rev.mov", directoryHint: .notDirectory)
        if FileManager.default.fileExists(atPath: destination.path(percentEncoded: false)) {
            return destination
        }
        return await Task.detached(priority: .userInitiated) {
            try? await Self.render(source: source, range: range, to: destination)
        }.value
    }

    static func render(source: URL, range: CMTimeRange, to destination: URL) async throws -> URL {
        try? FileManager.default.removeItem(at: destination)

        let asset = AVURLAsset(url: source)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw ReverseError.noVideoTrack
        }

        let size = try await track.load(.naturalSize)
        let transform = try await track.load(.preferredTransform)
        let nominal = try await track.load(.nominalFrameRate)
        let fps = nominal > 1 ? Double(nominal) : 30
        let frameDuration = CMTime(seconds: 1 / fps, preferredTimescale: 600)

        let width = Int(abs(size.width).rounded())
        let height = Int(abs(size.height).rounded())
        guard width > 0, height > 0 else { throw ReverseError.cannotWrite }

        // 4:2:0 is twelve bits a pixel where BGRA is thirty-two. Nothing here looks at the pixels,
        // it only reorders them, so the cheapest format the decoder will hand over is the right one.
        let frameBytes = max(1, width * height * 3 / 2)
        let framesPerChunk = max(1, memoryBudget / frameBytes)
        let chunkSeconds = Double(framesPerChunk) / fps

        let writer = try AVAssetWriter(outputURL: destination, fileType: .mov)
        let input = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.hevc,
                AVVideoWidthKey: width,
                AVVideoHeightKey: height,
            ]
        )
        input.expectsMediaDataInRealTime = false
        // Carried over, or a portrait clip comes back reversed *and* sideways.
        input.transform = transform

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
            ]
        )

        guard writer.canAdd(input) else { throw ReverseError.cannotWrite }
        writer.add(input)
        guard writer.startWriting() else { throw ReverseError.cannotWrite }
        writer.startSession(atSourceTime: .zero)

        var cursor = CMTime.zero
        var chunkEnd = range.end
        let start = range.start

        // Backwards through the clip, a chunk at a time, and each chunk's frames written in
        // reverse. Two levels of reversal, which is what keeps the memory bounded: the whole clip
        // is never decoded at once.
        while chunkEnd > start {
            let chunkStart = CMTimeMaximum(
                start,
                chunkEnd - CMTime(seconds: chunkSeconds, preferredTimescale: 600)
            )
            let frames = try Self.frames(
                of: asset,
                track: track,
                in: CMTimeRange(start: chunkStart, end: chunkEnd)
            )
            for frame in frames.reversed() {
                while !input.isReadyForMoreMediaData {
                    try await Task.sleep(for: .milliseconds(4))
                }
                adaptor.append(frame, withPresentationTime: cursor)
                cursor = cursor + frameDuration
            }
            chunkEnd = chunkStart
        }

        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else { throw ReverseError.cannotWrite }
        return destination
    }

    /// Decodes one chunk.
    static func frames(of asset: AVAsset, track: AVAssetTrack, in range: CMTimeRange) throws -> [CVPixelBuffer] {
        let reader = try AVAssetReader(asset: asset)
        reader.timeRange = range

        let output = AVAssetReaderTrackOutput(
            track: track,
            outputSettings: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
            ]
        )
        reader.add(output)
        reader.startReading()

        var result: [CVPixelBuffer] = []
        while let sample = output.copyNextSampleBuffer() {
            if let buffer = CMSampleBufferGetImageBuffer(sample) {
                result.append(buffer)
            }
        }
        reader.cancelReading()
        return result
    }
}
