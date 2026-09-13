import AVFoundation
import CoreGraphics
import Foundation

/// Small frames from a clip, for drawing it on the timeline.
///
/// A timeline of coloured boxes asks the user to remember which box is which shot. A strip of
/// frames lets them see it — the one moment in the editor where looking is faster than reading.
///
/// Small on purpose: a timeline cell is a few dozen points tall, and decoding a 4K frame to draw it
/// at that size is memory spent on pixels nobody can see.
public struct ThumbnailSampler: Sendable {
    public init() {}

    /// `count` frames spread evenly across `range` of the file at `url`. Frames that cannot be
    /// read are skipped rather than failing the strip.
    public func frames(of url: URL, from start: Double, duration: Double, count: Int) async -> [CGImage] {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 180, height: 180)
        // A little tolerance either side: exact frames cost a decode from the previous keyframe,
        // and nobody can tell a thumbnail a third of a second early.
        let tolerance = CMTime(seconds: 0.3, preferredTimescale: 600)
        generator.requestedTimeToleranceBefore = tolerance
        generator.requestedTimeToleranceAfter = tolerance

        let steps = max(1, count)
        var images: [CGImage] = []
        for index in 0..<steps {
            // The middle of each slice, not its edge: the first frame of a clip is so often a
            // blink or a hand reaching for the phone.
            let seconds = start + duration * (Double(index) + 0.5) / Double(steps)
            if let (image, _) = try? await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600)) {
                images.append(image)
            }
        }
        return images
    }
}
