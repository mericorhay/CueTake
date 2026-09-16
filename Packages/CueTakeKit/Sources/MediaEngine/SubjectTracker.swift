import AVFoundation
import CoreGraphics
import CoreVideo
import Foundation
import Vision

public enum SubjectFocusState: String, Hashable, Sendable {
    case tracking
    case searching
    case reacquired
}

/// A point in an upright source frame that should remain inside the crop.
public struct SubjectFocus: Hashable, Sendable {
    public var time: Double
    public var x: Double
    public var y: Double
    public var confidence: Double
    public var state: SubjectFocusState

    public init(
        time: Double,
        x: Double,
        y: Double,
        confidence: Double,
        state: SubjectFocusState = .tracking
    ) {
        self.time = time
        self.x = x
        self.y = y
        self.confidence = confidence
        self.state = state
    }
}

public enum SubjectTrackingError: Error, Hashable, Sendable {
    case noFace
    case lostSubject
    case emptyRange
}

/// Pure gates for re-identification. Vision proposes candidates; this policy prevents a visually
/// plausible result on the other side of the frame from silently becoming the selected subject.
enum SubjectRecoveryPolicy {
    static func score(
        candidate: CGRect,
        predicted: CGRect,
        appearanceDistance: Float?,
        missedFrames: Int
    ) -> Double? {
        let candidate = candidate.standardized
        let predicted = predicted.standardized
        guard candidate.width > 0.001, candidate.height > 0.001,
              predicted.width > 0.001, predicted.height > 0.001 else { return nil }

        let distance = Double(hypot(candidate.midX - predicted.midX, candidate.midY - predicted.midY))
        let predictedDiagonal = Double(hypot(predicted.width, predicted.height))
        let searchRadius = min(0.58, max(0.13, predictedDiagonal * 1.35) + Double(missedFrames) * 0.045)
        guard distance <= searchRadius else { return nil }

        let areaRatio = Double((candidate.width * candidate.height) / (predicted.width * predicted.height))
        guard areaRatio >= 0.24, areaRatio <= 4.2 else { return nil }
        let aspectRatio = Double((candidate.width / candidate.height) / (predicted.width / predicted.height))
        guard aspectRatio >= 0.34, aspectRatio <= 2.9 else { return nil }

        if let appearanceDistance {
            guard appearanceDistance.isFinite, appearanceDistance <= 0.48 else { return nil }
        } else {
            // Feature-print generation can fail on a very small or damaged frame. In that case
            // only a nearby candidate is safe enough to offer as an automatic recovery.
            guard distance <= min(searchRadius, 0.2) else { return nil }
        }

        let appearance = Double(appearanceDistance ?? 0.34)
        let spatial = distance / max(searchRadius, 0.001)
        let scale = abs(log(max(areaRatio, 0.001)))
        let aspect = abs(log(max(aspectRatio, 0.001)))
        return appearance * 0.62 + spatial * 0.23 + scale * 0.1 + aspect * 0.05
    }

    static func predictedBounds(last: CGRect, previous: CGRect?) -> CGRect {
        guard let previous else { return last }
        let dx = last.midX - previous.midX
        let dy = last.midY - previous.midY
        return CGRect(
            x: last.minX + dx,
            y: last.minY + dy,
            width: last.width,
            height: last.height
        )
    }
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

    /// Tracks a user-selected object. `initialBounds` uses the upright frame's top-left coordinate
    /// system, matching the editor canvas. Vision uses bottom-left coordinates internally.
    /// Analysis starts at the chosen frame and walks both ways so the user can point at the clearest
    /// view of an object instead of hunting for its first appearance.
    @concurrent
    public func objectFocus(
        in url: URL,
        sourceStart: Double,
        duration: Double,
        referenceTime: Double,
        initialBounds: CGRect,
        progress: @escaping @MainActor @Sendable (Double) -> Void = { _ in }
    ) async throws -> [SubjectFocus] {
        guard duration.isFinite, duration > 0.05 else { throw SubjectTrackingError.emptyRange }
        let bounds = initialBounds.standardized.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        guard bounds.width >= 0.025, bounds.height >= 0.025 else { throw SubjectTrackingError.lostSubject }

        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 960, height: 960)
        let tolerance = CMTime(seconds: 0.035, preferredTimescale: 600)
        generator.requestedTimeToleranceBefore = tolerance
        generator.requestedTimeToleranceAfter = tolerance

        let step = max(0.08, duration / 240)
        let reference = min(max(referenceTime, sourceStart), sourceStart + duration - 0.02)
        let before = stride(from: reference - step, through: sourceStart, by: -step).map { $0 }
        let after = stride(from: reference + step, through: sourceStart + duration - 0.02, by: step).map { $0 }
        let total = max(1, before.count + after.count + 1)
        var completed = 1

        guard let (referenceImage, _) = try? await generator.image(
            at: CMTime(seconds: reference, preferredTimescale: 600)
        ) else { throw SubjectTrackingError.lostSubject }

        let selectedVisionBounds = CGRect(
            x: bounds.minX,
            y: 1 - bounds.maxY,
            width: bounds.width,
            height: bounds.height
        )
        let seedBounds = Self.seedBounds(
            selected: selectedVisionBounds,
            candidates: Self.recoveryCandidateBoxes(in: referenceImage)
        ) ?? selectedVisionBounds
        let referenceFeature = Self.featurePrint(in: referenceImage, visionBounds: seedBounds)

        let seed = SubjectFocus(
            time: reference - sourceStart,
            x: Double(seedBounds.midX),
            y: Double(1 - seedBounds.midY),
            confidence: 1
        )
        var result = [seed]
        await progress(Double(completed) / Double(total))

        for times in [before, after] {
            try Task.checkCancellation()
            var visionBounds = seedBounds
            var lastReliableBounds = seedBounds
            var previousReliableBounds: CGRect?
            var missedFrames = 0
            var pending: (time: Double, bounds: CGRect, confidence: Double)?
            var sequence = VNSequenceRequestHandler()

            for sourceTime in times {
                try Task.checkCancellation()
                guard let (image, _) = try? await generator.image(
                    at: CMTime(seconds: sourceTime, preferredTimescale: 600)
                ) else {
                    completed += 1
                    await progress(Double(completed) / Double(total))
                    continue
                }

                let relativeTime = sourceTime - sourceStart
                let predicted = SubjectRecoveryPolicy.predictedBounds(
                    last: lastReliableBounds,
                    previous: previousReliableBounds
                )

                if missedFrames > 0, pending == nil {
                    result.append(Self.searchingFocus(
                        time: relativeTime,
                        lastReliableBounds: lastReliableBounds
                    ))
                    if let candidate = Self.recoveryCandidate(
                        in: image,
                        predicted: predicted,
                        referenceFeature: referenceFeature,
                        missedFrames: missedFrames
                    ) {
                        pending = (relativeTime, candidate.bounds, candidate.confidence)
                        visionBounds = candidate.bounds
                        sequence = VNSequenceRequestHandler()
                    } else {
                        missedFrames += 1
                    }
                    completed += 1
                    await progress(Double(completed) / Double(total))
                    continue
                }

                let observation = VNDetectedObjectObservation(boundingBox: visionBounds)
                let request = VNTrackObjectRequest(detectedObjectObservation: observation)
                request.trackingLevel = .accurate
                try? sequence.perform([request], on: image)
                let tracked = request.results?.first as? VNDetectedObjectObservation

                if let pendingRecovery = pending {
                    let trackedFeature = tracked.flatMap {
                        Self.featurePrint(in: image, visionBounds: $0.boundingBox)
                    }
                    let appearanceDistance = Self.featureDistance(referenceFeature, trackedFeature)
                    let accepted = tracked.flatMap { observation -> CGRect? in
                        guard observation.confidence >= 0.5,
                              SubjectRecoveryPolicy.score(
                                candidate: observation.boundingBox,
                                predicted: predicted,
                                appearanceDistance: appearanceDistance,
                                missedFrames: missedFrames
                              ) != nil else { return nil }
                        return observation.boundingBox
                    }

                    if let accepted {
                        // Two consecutive frames have now agreed on the candidate. Remove the weak
                        // placeholder at its first frame and expose a single reacquisition edge.
                        result.removeAll {
                            abs($0.time - pendingRecovery.time) < 0.0001 && $0.state == .searching
                        }
                        result.append(SubjectFocus(
                            time: pendingRecovery.time,
                            x: Double(pendingRecovery.bounds.midX),
                            y: Double(1 - pendingRecovery.bounds.midY),
                            confidence: pendingRecovery.confidence,
                            state: .reacquired
                        ))
                        result.append(SubjectFocus(
                            time: relativeTime,
                            x: Double(accepted.midX),
                            y: Double(1 - accepted.midY),
                            confidence: Double(tracked?.confidence ?? 0.5),
                            state: .tracking
                        ))
                        previousReliableBounds = pendingRecovery.bounds
                        lastReliableBounds = accepted
                        visionBounds = accepted
                        missedFrames = 0
                        pending = nil
                    } else {
                        result.append(Self.searchingFocus(
                            time: relativeTime,
                            lastReliableBounds: lastReliableBounds
                        ))
                        missedFrames += 1
                        pending = nil
                        sequence = VNSequenceRequestHandler()
                    }
                    completed += 1
                    await progress(Double(completed) / Double(total))
                    continue
                }

                guard let tracked, tracked.confidence >= 0.25,
                      SubjectRecoveryPolicy.score(
                        candidate: tracked.boundingBox,
                        predicted: predicted,
                        appearanceDistance: nil,
                        missedFrames: 0
                      ) != nil else {
                    result.append(Self.searchingFocus(
                        time: relativeTime,
                        lastReliableBounds: lastReliableBounds,
                        confidence: Double(tracked?.confidence ?? 0)
                    ))
                    missedFrames = 1
                    sequence = VNSequenceRequestHandler()
                    completed += 1
                    await progress(Double(completed) / Double(total))
                    continue
                }

                visionBounds = tracked.boundingBox
                result.append(SubjectFocus(
                    time: relativeTime,
                    x: Double(visionBounds.midX),
                    y: Double(1 - visionBounds.midY),
                    confidence: Double(tracked.confidence)
                ))
                previousReliableBounds = lastReliableBounds
                lastReliableBounds = visionBounds
                completed += 1
                await progress(Double(completed) / Double(total))
            }
        }

        guard result.count > 1 else { throw SubjectTrackingError.lostSubject }
        result.sort { $0.time < $1.time }
        // Keep the camera calm without erasing deliberate motion.
        var smoothed: [SubjectFocus] = []
        for var value in result {
            if let previous = smoothed.last,
               value.state == .tracking,
               previous.state == .tracking {
                let distance = hypot(value.x - previous.x, value.y - previous.y)
                let response = min(max(distance * 5, 0.28), 0.72)
                value.x = previous.x + (value.x - previous.x) * response
                value.y = previous.y + (value.y - previous.y) * response
            }
            smoothed.append(value)
        }
        await progress(1)
        return Self.reduce(smoothed)
    }

    private struct RecoveryCandidate {
        var bounds: CGRect
        var confidence: Double
        var score: Double
    }

    private static func searchingFocus(
        time: Double,
        lastReliableBounds: CGRect,
        confidence: Double = 0
    ) -> SubjectFocus {
        SubjectFocus(
            time: time,
            x: Double(lastReliableBounds.midX),
            y: Double(1 - lastReliableBounds.midY),
            confidence: min(max(confidence, 0), 0.24),
            state: .searching
        )
    }

    private static func recoveryCandidate(
        in image: CGImage,
        predicted: CGRect,
        referenceFeature: VNFeaturePrintObservation?,
        missedFrames: Int
    ) -> RecoveryCandidate? {
        recoveryCandidateBoxes(in: image).compactMap { bounds in
            let feature = featurePrint(in: image, visionBounds: bounds)
            let distance = featureDistance(referenceFeature, feature)
            guard let score = SubjectRecoveryPolicy.score(
                candidate: bounds,
                predicted: predicted,
                appearanceDistance: distance,
                missedFrames: missedFrames
            ) else { return nil }
            let appearanceConfidence = distance.map { max(0.5, 1 - Double($0)) } ?? 0.5
            return RecoveryCandidate(bounds: bounds, confidence: appearanceConfidence, score: score)
        }.min { $0.score < $1.score }
    }

    private static func featurePrint(in image: CGImage, visionBounds: CGRect) -> VNFeaturePrintObservation? {
        guard let crop = crop(image, toVisionBounds: visionBounds) else { return nil }
        let request = VNGenerateImageFeaturePrintRequest()
        let handler = VNImageRequestHandler(cgImage: crop, options: [:])
        guard (try? handler.perform([request])) != nil else { return nil }
        return request.results?.first as? VNFeaturePrintObservation
    }

    private static func featureDistance(
        _ reference: VNFeaturePrintObservation?,
        _ candidate: VNFeaturePrintObservation?
    ) -> Float? {
        guard let reference, let candidate else { return nil }
        var distance: Float = 0
        guard (try? reference.computeDistance(&distance, to: candidate)) != nil else { return nil }
        return distance
    }

    private static func crop(_ image: CGImage, toVisionBounds bounds: CGRect) -> CGImage? {
        let bounds = bounds.standardized.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        guard bounds.width >= 0.01, bounds.height >= 0.01 else { return nil }
        let pixels = CGRect(
            x: bounds.minX * CGFloat(image.width),
            y: (1 - bounds.maxY) * CGFloat(image.height),
            width: bounds.width * CGFloat(image.width),
            height: bounds.height * CGFloat(image.height)
        ).integral.intersection(CGRect(
            x: 0,
            y: 0,
            width: CGFloat(image.width),
            height: CGFloat(image.height)
        ))
        guard pixels.width >= 8, pixels.height >= 8 else { return nil }
        return image.cropping(to: pixels)
    }

    private static func seedBounds(selected: CGRect, candidates: [CGRect]) -> CGRect? {
        let selectedArea = max(selected.width * selected.height, 0.0001)
        return candidates.compactMap { candidate -> (CGRect, Double)? in
            let intersection = selected.intersection(candidate)
            guard !intersection.isNull, !intersection.isEmpty else { return nil }
            let coverage = Double((intersection.width * intersection.height) / selectedArea)
            guard coverage >= 0.18 || candidate.contains(CGPoint(x: selected.midX, y: selected.midY)) else { return nil }
            let expansion = Double((candidate.width * candidate.height) / selectedArea)
            let score = coverage - abs(log(max(expansion, 0.001))) * 0.08
            return (candidate, score)
        }.max { $0.1 < $1.1 }?.0
    }

    private static func recoveryCandidateBoxes(in image: CGImage) -> [CGRect] {
        var boxes: [CGRect] = []

        let faceRequest = VNDetectFaceRectanglesRequest()
        let humanRequest = VNDetectHumanRectanglesRequest()
        humanRequest.upperBodyOnly = false
        let basicHandler = VNImageRequestHandler(cgImage: image, options: [:])
        if (try? basicHandler.perform([faceRequest, humanRequest])) != nil {
            boxes.append(contentsOf: faceRequest.results?.map(\.boundingBox) ?? [])
            boxes.append(contentsOf: humanRequest.results?.map(\.boundingBox) ?? [])
        }

        let foregroundRequest = VNGenerateForegroundInstanceMaskRequest()
        let foregroundHandler = VNImageRequestHandler(cgImage: image, options: [:])
        if (try? foregroundHandler.perform([foregroundRequest])) != nil,
           let observation = foregroundRequest.results?.first {
            for index in observation.allInstances.prefix(8) {
                guard let mask = try? observation.generateMask(forInstances: IndexSet(integer: index)),
                      let bounds = normalizedBounds(of: mask) else { continue }
                boxes.append(bounds)
            }
        }

        var unique: [CGRect] = []
        for box in boxes {
            let box = box.standardized.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
            let area = box.width * box.height
            guard area >= 0.001, area <= 0.96 else { continue }
            if unique.contains(where: { intersectionOverUnion($0, box) >= 0.74 }) { continue }
            unique.append(box)
        }
        return unique
    }

    /// Converts Vision's labelled foreground mask into a normalized Vision-coordinate rectangle.
    private static func normalizedBounds(of mask: CVPixelBuffer) -> CGRect? {
        CVPixelBufferLockBaseAddress(mask, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(mask, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(mask) else { return nil }
        let width = CVPixelBufferGetWidth(mask)
        let height = CVPixelBufferGetHeight(mask)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(mask)
        let format = CVPixelBufferGetPixelFormatType(mask)
        var minX = width, minY = height, maxX = -1, maxY = -1

        for y in 0..<height {
            let row = base.advanced(by: y * bytesPerRow)
            for x in 0..<width {
                let active: Bool
                switch format {
                case kCVPixelFormatType_OneComponent8:
                    active = row.load(fromByteOffset: x, as: UInt8.self) != 0
                case kCVPixelFormatType_OneComponent16Half:
                    active = row.load(fromByteOffset: x * 2, as: UInt16.self) != 0
                case kCVPixelFormatType_OneComponent32Float:
                    active = row.load(fromByteOffset: x * 4, as: Float.self) > 0.01
                default:
                    active = false
                }
                guard active else { continue }
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        return CGRect(
            x: CGFloat(minX) / CGFloat(width),
            y: 1 - CGFloat(maxY + 1) / CGFloat(height),
            width: CGFloat(maxX - minX + 1) / CGFloat(width),
            height: CGFloat(maxY - minY + 1) / CGFloat(height)
        )
    }

    private static func intersectionOverUnion(_ left: CGRect, _ right: CGRect) -> CGFloat {
        let intersection = left.intersection(right)
        guard !intersection.isNull, !intersection.isEmpty else { return 0 }
        let intersectionArea = intersection.width * intersection.height
        let union = left.width * left.height + right.width * right.height - intersectionArea
        return union > 0 ? intersectionArea / union : 0
    }

    private static func principalFace(in image: CGImage, near previous: CGPoint?) -> VNFaceObservation? {
        let request = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        guard (try? handler.perform([request])) != nil else { return nil }
        return request.results?.max { left, right in
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
            // A decoded frame is one decision. Keep malformed or legacy duplicate timestamps from
            // becoming two review warnings, especially while Vision is searching.
            if let last = result.last, abs(value.time - last.time) < 0.0001 {
                if value.confidence < last.confidence || value.state == .searching {
                    result[result.count - 1] = value
                }
                continue
            }
            guard let last = result.last,
                  hypot(value.x - last.x, value.y - last.y) >= 0.018
                    || value.confidence < 0.6
                    || abs(value.confidence - last.confidence) >= 0.15
                    || value.state != .tracking
                    || value.state != last.state
            else { continue }
            result.append(value)
        }
        if let last = values.last, last.time > result.last!.time + 0.01 { result.append(last) }
        return result
    }
}
