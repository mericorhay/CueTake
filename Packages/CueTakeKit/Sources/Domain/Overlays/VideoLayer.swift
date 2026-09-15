import Foundation

/// A rectangle in the finished frame, independent of the source video's orientation and pixels.
public struct VideoPlacement: Hashable, Sendable, Codable {
    public var x: Double = 0
    public var y: Double = 0
    public var width: Double = 1
    public var height: Double = 1
    public var fillsFrame: Bool = false
    public var isMirrored: Bool = false
    public var opacity: Double = 1
    /// Extra camera magnification inside this placement. Optional keeps projects written before
    /// the Zoom Engine source-compatible; nil is exactly the old 1x geometry.
    public var zoom: Double?
    /// Point in the upright source that stays at the centre when the frame is filled. Nil is the
    /// ordinary centre crop; smart reframe writes these without changing the layer's rectangle.
    public var focusX: Double?
    public var focusY: Double?

    public init(x: Double = 0, y: Double = 0, width: Double = 1, height: Double = 1, fillsFrame: Bool = false, isMirrored: Bool = false, opacity: Double = 1, zoom: Double? = nil, focusX: Double? = nil, focusY: Double? = nil) {
        self.x = x; self.y = y; self.width = width; self.height = height
        self.fillsFrame = fillsFrame; self.isMirrored = isMirrored; self.opacity = opacity
        self.zoom = zoom
        self.focusX = focusX; self.focusY = focusY
    }

    public static let full = VideoPlacement()
    public static let inset = VideoPlacement(x: 0.62, y: 0.08, width: 0.32, height: 0.32, fillsFrame: true)

    public var bounded: VideoPlacement {
        var value = self
        value.width = width.isFinite ? min(max(width, 0.1), 1) : 1
        value.height = height.isFinite ? min(max(height, 0.1), 1) : 1
        value.x = x.isFinite ? min(max(x, 0), 1 - value.width) : 0
        value.y = y.isFinite ? min(max(y, 0), 1 - value.height) : 0
        value.opacity = opacity.isFinite ? min(max(opacity, 0), 1) : 1
        value.zoom = zoom.map { $0.isFinite ? min(max($0, 1), 3) : 1 }
        value.focusX = focusX.map { $0.isFinite ? min(max($0, 0), 1) : 0.5 }
        value.focusY = focusY.map { $0.isFinite ? min(max($0, 0), 1) : 0.5 }
        return value
    }

    public func interpolated(to other: VideoPlacement, fraction: Double) -> VideoPlacement {
        let a = bounded, b = other.bounded
        let t = min(max(fraction.isFinite ? fraction : 0, 0), 1)
        func blend(_ x: Double, _ y: Double) -> Double { x + (y - x) * t }
        return VideoPlacement(
            x: blend(a.x, b.x), y: blend(a.y, b.y),
            width: blend(a.width, b.width), height: blend(a.height, b.height),
            fillsFrame: a.fillsFrame, isMirrored: a.isMirrored,
            opacity: blend(a.opacity, b.opacity),
            zoom: blend(a.zoom ?? 1, b.zoom ?? 1),
            focusX: blend(a.focusX ?? 0.5, b.focusX ?? 0.5),
            focusY: blend(a.focusY ?? 0.5, b.focusY ?? 0.5)
        ).bounded
    }
}

public struct VideoKeyframe: Hashable, Sendable, Codable, Identifiable {
    public var id: UUID = UUID()
    /// Seconds from the start of this layer on the timeline.
    public var time: Double
    public var placement: VideoPlacement
    public init(time: Double, placement: VideoPlacement) { self.time = time; self.placement = placement }
}

/// A crop target inside the source picture. Kept separate from placement animation so tracking a
/// face can never move or resize the rectangle the editor positioned on the canvas.
public struct VideoFocusKeyframe: Hashable, Sendable, Codable, Identifiable {
    public var id: UUID = UUID()
    /// Seconds from the start of the source range.
    public var time: Double
    public var x: Double
    public var y: Double
    /// Optional camera distance at this tracked point. Old face tracks remain exactly 1x.
    public var zoom: Double?
    /// Vision's confidence at this source frame. Nil means the project predates confidence review.
    public var confidence: Double?

    public init(time: Double, x: Double, y: Double, zoom: Double? = nil, confidence: Double? = nil) {
        self.time = time
        self.x = x
        self.y = y
        self.zoom = zoom
        self.confidence = confidence
    }
}

/// Another movie playing at the same time as the primary cut. The original file stays untouched.
public struct VideoLayer: Identifiable, Hashable, Sendable, Codable {
    public static let maximumAdditionalLayers = 3
    public var id: UUID
    public var recordingID: Recording.ID
    public var title: String
    public var start: MediaTime
    public var sourceRange: MediaTimeRange
    public var placement: VideoPlacement
    public var volume: Double = 1
    public var isMuted = false
    public var isHidden = false
    public var isLocked = false
    public var keyframes: [VideoKeyframe] = []
    /// Optional keeps documents written before build 55 source-compatible with synthesized Codable.
    public var focusKeyframes: [VideoFocusKeyframe]? = nil

    public init(id: UUID = UUID(), recordingID: Recording.ID, title: String, start: MediaTime = .zero, sourceRange: MediaTimeRange, placement: VideoPlacement = .inset) {
        self.id = id; self.recordingID = recordingID; self.title = title
        self.start = start; self.sourceRange = sourceRange; self.placement = placement
    }

    public var end: Double { start.seconds + sourceRange.duration.seconds }
    public var duration: Double { sourceRange.duration.seconds }
    public var orderedKeyframes: [VideoKeyframe] {
        keyframes.filter { $0.time.isFinite && $0.time >= 0 && $0.time <= duration }
            .sorted { $0.time < $1.time }
    }

    public var orderedFocusKeyframes: [VideoFocusKeyframe] {
        (focusKeyframes ?? []).filter { $0.time.isFinite && $0.time >= 0 && $0.time <= duration }
            .sorted { $0.time < $1.time }
    }

    public func placement(at timelineTime: Double) -> VideoPlacement {
        let time = max(0, timelineTime - start.seconds)
        var previous = VideoKeyframe(time: 0, placement: placement)
        var result = placement
        for frame in orderedKeyframes {
            if time < frame.time {
                result = previous.placement.interpolated(to: frame.placement, fraction: (time - previous.time) / max(0.001, frame.time - previous.time))
                return applyingFocus(to: result, at: time)
            }
            previous = frame
        }
        return applyingFocus(to: previous.placement.bounded, at: time)
    }

    private func applyingFocus(to placement: VideoPlacement, at time: Double) -> VideoPlacement {
        let frames = orderedFocusKeyframes
        guard var previous = frames.first else { return placement }
        var focus = previous
        for frame in frames.dropFirst() {
            if time < frame.time {
                let fraction = min(max((time - previous.time) / max(0.001, frame.time - previous.time), 0), 1)
                focus = VideoFocusKeyframe(
                    time: time,
                    x: previous.x + (frame.x - previous.x) * fraction,
                    y: previous.y + (frame.y - previous.y) * fraction,
                    zoom: previous.zoom == nil && frame.zoom == nil
                        ? nil
                        : (previous.zoom ?? 1) + ((frame.zoom ?? 1) - (previous.zoom ?? 1)) * fraction,
                    confidence: previous.confidence == nil && frame.confidence == nil
                        ? nil
                        : (previous.confidence ?? 1) + ((frame.confidence ?? 1) - (previous.confidence ?? 1)) * fraction
                )
                break
            }
            previous = frame
            focus = frame
        }
        var result = placement
        result.focusX = min(max(focus.x, 0), 1)
        result.focusY = min(max(focus.y, 0), 1)
        if let zoom = focus.zoom { result.zoom = zoom }
        return result.bounded
    }

    /// Build 54 stored tracking points as placement animation. Move those points to their own
    /// channel before the user edits the rectangle, otherwise it springs back during playback.
    public mutating func separateLegacyTracking() {
        guard focusKeyframes == nil, placement.focusX != nil || keyframes.contains(where: { $0.placement.focusX != nil }) else { return }
        let baseFocus = VideoFocusKeyframe(time: 0, x: placement.focusX ?? 0.5, y: placement.focusY ?? 0.5)
        focusKeyframes = [baseFocus] + keyframes.compactMap { frame in
            guard frame.placement.focusX != nil || frame.placement.focusY != nil else { return nil }
            return VideoFocusKeyframe(time: frame.time, x: frame.placement.focusX ?? 0.5, y: frame.placement.focusY ?? 0.5)
        }
        func stripped(_ value: VideoPlacement) -> VideoPlacement {
            var value = value
            value.focusX = nil
            value.focusY = nil
            return value
        }
        placement = stripped(placement)
        keyframes = keyframes.map { frame in
            var frame = frame
            frame.placement = stripped(frame.placement)
            return frame
        }
        // Smart reframe generated identical layout frames. They are crop samples, not intentional
        // motion, so remove them while preserving genuine position/size animation.
        if keyframes.allSatisfy({ stripped($0.placement) == placement }) { keyframes = [] }
    }

    /// Trimming rebases motion too: the first retained frame must not jump to the old position.
    public mutating func trimStart(by delta: Double) {
        let amount = min(max(delta, 0), max(0, duration - 0.2))
        guard amount > 0 else { return }
        let newPlacement = placement(at: start.seconds + amount)
        sourceRange = MediaTimeRange(start: sourceRange.start + MediaTime(seconds: amount), duration: MediaTime(seconds: duration - amount))
        start = start + MediaTime(seconds: amount)
        placement = newPlacement
        keyframes = keyframes.filter { $0.time > amount }.map {
            var frame = $0; frame.time -= amount; return frame
        }
        focusKeyframes = orderedFocusKeyframes.filter { $0.time > amount }.map {
            var frame = $0; frame.time -= amount; return frame
        }
    }
}

public enum VideoLayout: String, CaseIterable, Sendable, Codable {
    case sideBySide, stacked, pictureInPicture, grid

    public func placements(count: Int) -> [VideoPlacement] {
        let count = min(max(count, 1), 4)
        if count == 1 { return [.full] }
        switch self {
        case .pictureInPicture:
            return [.full] + (1..<count).map { VideoPlacement(x: 0.64, y: 0.05 + Double($0 - 1) * 0.31, width: 0.31, height: 0.28, fillsFrame: true) }
        case .sideBySide:
            return (0..<count).map { VideoPlacement(x: Double($0) / Double(count), width: 1 / Double(count), fillsFrame: true) }
        case .stacked:
            return (0..<count).map { VideoPlacement(y: Double($0) / Double(count), height: 1 / Double(count), fillsFrame: true) }
        case .grid:
            return (0..<count).map { VideoPlacement(x: Double($0 % 2) * 0.5, y: Double($0 / 2) * 0.5, width: 0.5, height: 0.5, fillsFrame: true) }
        }
    }
}
