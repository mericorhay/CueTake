import Foundation

/// Frame-accurate rational time.
///
/// Domain deliberately does not import CoreMedia, so it keeps its own `CMTime`-shaped value.
/// Engines convert to and from `CMTime` at their boundary.
public struct MediaTime: Sendable, Codable {
    public static let defaultTimescale: Int32 = 600

    public var value: Int64
    public var timescale: Int32

    public init(value: Int64, timescale: Int32 = MediaTime.defaultTimescale) {
        precondition(timescale > 0, "MediaTime timescale must be positive")
        self.value = value
        self.timescale = timescale
    }

    public init(seconds: Double, timescale: Int32 = MediaTime.defaultTimescale) {
        self.init(value: Int64((seconds * Double(timescale)).rounded()), timescale: timescale)
    }

    public var seconds: Double { Double(value) / Double(timescale) }

    public func converted(to timescale: Int32) -> MediaTime {
        guard timescale != self.timescale else { return self }
        let scaled = (Double(value) * Double(timescale) / Double(self.timescale)).rounded()
        return MediaTime(value: Int64(scaled), timescale: timescale)
    }
}

// Equality compares the rational value, so 1/2 == 300/600.
extension MediaTime: Hashable, Comparable {
    public static func == (lhs: MediaTime, rhs: MediaTime) -> Bool {
        lhs.value * Int64(rhs.timescale) == rhs.value * Int64(lhs.timescale)
    }

    public static func < (lhs: MediaTime, rhs: MediaTime) -> Bool {
        lhs.value * Int64(rhs.timescale) < rhs.value * Int64(lhs.timescale)
    }

    public func hash(into hasher: inout Hasher) {
        let divisor = Self.gcd(Swift.abs(value), Int64(timescale))
        hasher.combine(value / divisor)
        hasher.combine(Int64(timescale) / divisor)
    }

    private static func gcd(_ a: Int64, _ b: Int64) -> Int64 {
        b == 0 ? Swift.max(a, 1) : gcd(b, a % b)
    }
}

extension MediaTime: AdditiveArithmetic {
    public static let zero = MediaTime(value: 0)

    public static func + (lhs: MediaTime, rhs: MediaTime) -> MediaTime {
        let timescale = Swift.max(lhs.timescale, rhs.timescale)
        return MediaTime(value: lhs.converted(to: timescale).value + rhs.converted(to: timescale).value, timescale: timescale)
    }

    public static func - (lhs: MediaTime, rhs: MediaTime) -> MediaTime {
        let timescale = Swift.max(lhs.timescale, rhs.timescale)
        return MediaTime(value: lhs.converted(to: timescale).value - rhs.converted(to: timescale).value, timescale: timescale)
    }
}

public struct MediaTimeRange: Hashable, Sendable, Codable {
    public var start: MediaTime
    public var duration: MediaTime

    public init(start: MediaTime, duration: MediaTime) {
        self.start = start
        self.duration = duration
    }

    public var end: MediaTime { start + duration }

    public func contains(_ time: MediaTime) -> Bool {
        time >= start && time < end
    }

    public func offset(by delta: MediaTime) -> MediaTimeRange {
        MediaTimeRange(start: start + delta, duration: duration)
    }
}
