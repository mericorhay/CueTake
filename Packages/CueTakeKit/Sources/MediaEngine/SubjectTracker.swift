import AVFoundation
import CoreGraphics
import Foundation
import Vision

/// A point in an upright source frame that should remain inside the crop.
public struct SubjectFocus: Hashable, Sendable {
    public var time: Double
    public var x: Double
    public var y: Double
    public var confidence: Double

    public init(time: Double, x: Double, y: Double, confidence: Double) {
        self.time = time
        self.x = x
        self.y = y
        self.confidence = confidence
    }
}

public enum SubjectTrackingError: Error, Hashable, Sendable {
    case noFace
    case emptyRange
}

/// Finds and follows the principal face without uploading a frame.
///
/// Frames are sampled rather than decoded continuously. Reframing does not need sixty decisions a
/// second: the compositor interpolates between these points, which is smoother and uses far less
/// battery. A small moving average prevents detector jitter from turning into camera shake.
public struct SubjectTracker: Sendable {
    public init() {}

    @concurrent
    public func faceFocus(
        in url: URL,
        sourceStart: Double,
        duration: Double,
        progress: @escaping @MainActor @Sendable (Double) -> Void = { _ in }
    ) async throws -> [SubjectFocus] {
        guard duration.isFinite, duration > 0.05 else { throw SubjectTrackingError.emptyRange }

        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 720, height: 720)
        let tolerance = CMTime(seconds: 0.08, preferredTimescale: 600)
        generator.requestedTimeToleranceBefore = tolerance
        generator.requestedTimeToleranceAfter = tolerance

        // Half-second analysis, capped for long clips. Interpolation supplies the frames between.
        let samples = min(180, max(2, Int(ceil(duration / 0.5)) + 1))
        var detected: [SubjectFocus] = []
        var previous: CGPoint?

        for index in 0..<samples {
            try Task.checkCancellation()
            let relative = duration * Double(index) / Double(max(1, samples - 1))
            let sourceTime = sourceStart + min(relative, max(0, duration - 0.03))
            if let (image, _) = try? await generator.image(
                at: CMTime(seconds: sourceTime, preferredTimescale: 600)
            ), let observation = Self.principalFace(in: image, near: previous) {
                let box = observation.boundingBox
                let raw = CGPoint(
                    x: box.midX,
                    // Vision's origin is bottom-left. Aim a little below the face centre so the
                    // eyes sit above the middle of a portrait crop, like a camera operator would.
                    y: 1 - box.midY + box.height * 0.18
                )
                let smooth = previous.map {
                    CGPoint(x: $0.x * 0.65 + raw.x * 0.35, y: $0.y * 0.65 + raw.y * 0.35)
                } ?? raw
                previous = smooth
                detected.append(SubjectFocus(
                    time: relative,
                    x: min(max(smooth.x, 0), 1),
                    y: min(max(smooth.y, 0), 1),
                    confidence: Double(observation.confidence)
                ))
            }
            await progress(Double(index + 1) / Double(samples))
        }

        guard var first = detected.first, let last = detected.last else {
            throw SubjectTrackingError.noFace
        }
        // Tracking begins and ends with a known point. Without these, the crop drifts from the
        // centre before the first detection and snaps back after the last one.
        first.time = 0
        detected[0] = first
        if detected[detected.count - 1].time < duration - 0.02 {
            detected.append(SubjectFocus(time: duration, x: last.x, y: last.y, confidence: last.confidence))
        }
        return Self.reduce(detected)
    }

    private static func principalFace(in image: CGImage, near previous: CGPoint?) -> VNFaceObservation? {
        let request = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        guard (try? handler.perform([request])) != nil else { return nil }
        return request.results.max { left, right in
            score(left, near: previous) < score(right, near: previous)
        }
    }

    private static func score(_ face: VNFaceObservation, near previous: CGPoint?) -> Double {
        let box = face.boundingBox
        let area = Double(box.width * box.height)
        guard let previous else { return area * Double(face.confidence) }
        let point = CGPoint(x: box.midX, y: 1 - box.midY)
        let distance = Double(hypot(point.x - previous.x, point.y - previous.y))
        return area * Double(face.confidence) - distance * 0.08
    }

    /// Drops points whose movement is too small to see. Fewer keyframes produce calmer motion and
    /// make a manually adjusted result understandable in the timeline.
    static func reduce(_ values: [SubjectFocus]) -> [SubjectFocus] {
        guard let first = values.first else { return [] }
        var result = [first]
        for value in values.dropFirst().dropLast() {
            guard let last = result.last,
                  hypot(value.x - last.x, value.y - last.y) >= 0.018
            else { continue }
            result.append(value)
        }
        if let last = values.last, last.time > result.last!.time + 0.01 { result.append(last) }
        return result
    }
}
