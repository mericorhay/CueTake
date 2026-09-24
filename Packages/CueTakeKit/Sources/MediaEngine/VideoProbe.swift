import AVFoundation
import Domain
import Foundation

/// What a video file really is: its size on screen and its frame rate, read from the file.
///
/// The camera can quietly record less than was asked for, and an export can come out at a lower
/// rate than its project; both are checked against this rather than trusted.
public enum VideoProbe {
    public struct Measured: Hashable, Sendable {
        public var width: Int
        public var height: Int
        public var frameRate: Double

        public var shortEdge: Int { min(width, height) }
    }

    public static func measure(_ url: URL) async -> Measured? {
        let asset = AVURLAsset(url: url)
        guard let track = try? await asset.loadTracks(withMediaType: .video).first,
              let natural = try? await track.load(.naturalSize),
              let transform = try? await track.load(.preferredTransform),
              let rate = try? await track.load(.nominalFrameRate)
        else { return nil }
        let size = CGRect(origin: .zero, size: natural).applying(transform).standardized.size
        return Measured(width: Int(size.width.rounded()), height: Int(size.height.rounded()), frameRate: Double(rate))
    }
}

extension VideoFormat {
    /// This format with the resolution and frame rate a file actually has, the shape kept.
    public func matching(_ measured: VideoProbe.Measured) -> VideoFormat {
        let resolution: Resolution = measured.shortEdge >= 2000 ? .uhd4K : .hd1080
        let rate = Self.frameRateChoices.min { abs(Double($0) - measured.frameRate) < abs(Double($1) - measured.frameRate) } ?? frameRate
        return VideoFormat(aspectRatio: aspectRatio, resolution: resolution, frameRate: rate)
    }
}
