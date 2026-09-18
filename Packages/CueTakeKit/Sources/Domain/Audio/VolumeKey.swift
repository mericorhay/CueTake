import Foundation

/// A point on a sound's volume curve: at this moment of the clip, this loud.
///
/// Fades and ducking already shape the music without anyone asking. Keys are for the times the
/// person wants something the rules cannot know — the music swelling into the last line, a sting
/// pulled back under a laugh. They multiply the automatic curve rather than replace it, so a key
/// never switches the ducking off by accident.
public struct VolumeKey: Identifiable, Hashable, Sendable, Codable {
    public var id: UUID
    /// Seconds from the start of the clip on the timeline.
    public var time: Double
    /// Over the clip's own level: 0 is silent, 1 is as set, 2 is about 6 dB louder.
    public var level: Double

    public init(id: UUID = UUID(), time: Double, level: Double) {
        self.id = id
        self.time = time
        self.level = level
    }

    public static let levelRange: ClosedRange<Double> = 0...2
    /// Two keys closer than this are one key: a finger cannot put them apart on purpose.
    public static let nearest = 0.05
}

extension AudioClip {
    /// The keys that fall inside the clip, in order.
    public var orderedVolumeKeys: [VolumeKey] {
        let length = timelineDuration.seconds
        return (volumeKeys ?? [])
            .filter { $0.time.isFinite && $0.level.isFinite && $0.time >= 0 && $0.time <= length }
            .sorted { $0.time < $1.time }
    }

    /// The level the keys ask for at a moment of the clip. One before the first key and after the
    /// last, so the curve does nothing where nobody drew it.
    public func automation(at time: Double) -> Double {
        let keys = orderedVolumeKeys
        guard let first = keys.first, let last = keys.last else { return 1 }
        if time <= first.time { return Self.bounded(first.level) }
        if time >= last.time { return Self.bounded(last.level) }
        for (previous, next) in zip(keys, keys.dropFirst()) where time < next.time {
            let span = max(next.time - previous.time, 0.0001)
            let t = (time - previous.time) / span
            return Self.bounded(previous.level + (next.level - previous.level) * t)
        }
        return Self.bounded(last.level)
    }

    /// Puts a key at a moment, or moves the one already there.
    public mutating func setVolumeKey(at time: Double, level: Double) {
        let length = timelineDuration.seconds
        let when = min(max(time.isFinite ? time : 0, 0), length)
        var keys = volumeKeys ?? []
        if let index = keys.firstIndex(where: { abs($0.time - when) < VolumeKey.nearest }) {
            keys[index].level = Self.bounded(level)
        } else {
            keys.append(VolumeKey(time: when, level: Self.bounded(level)))
        }
        volumeKeys = keys.sorted { $0.time < $1.time }
    }

    /// Takes away the key nearest a moment. Returns false when there was none close enough.
    @discardableResult
    public mutating func removeVolumeKey(near time: Double, within reach: Double = 0.25) -> Bool {
        guard var keys = volumeKeys, !keys.isEmpty else { return false }
        guard let index = keys.indices.min(by: { abs(keys[$0].time - time) < abs(keys[$1].time - time) }),
              abs(keys[index].time - time) <= reach
        else { return false }
        keys.remove(at: index)
        volumeKeys = keys.isEmpty ? nil : keys
        return true
    }

    /// The key within reach of a moment, for the control that edits "the key here".
    public func volumeKey(near time: Double, within reach: Double = 0.25) -> VolumeKey? {
        orderedVolumeKeys
            .filter { abs($0.time - time) <= reach }
            .min { abs($0.time - time) < abs($1.time - time) }
    }

    /// When the start edge is trimmed the keys stay on the music they were put on, not on the
    /// same distance from an edge that has moved.
    public mutating func shiftVolumeKeys(by seconds: Double) {
        guard let keys = volumeKeys else { return }
        let length = timelineDuration.seconds
        let moved = keys
            .map { key -> VolumeKey in
                var key = key
                key.time += seconds
                return key
            }
            .filter { $0.time >= -0.0001 && $0.time <= length + 0.0001 }
        volumeKeys = moved.isEmpty ? nil : moved
    }

    static func bounded(_ level: Double) -> Double {
        min(max(level.isFinite ? level : 1, VolumeKey.levelRange.lowerBound), VolumeKey.levelRange.upperBound)
    }
}
