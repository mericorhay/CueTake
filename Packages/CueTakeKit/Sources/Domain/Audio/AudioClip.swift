import Foundation

/// A sound laid on the timeline: music, a voiceover, a sting.
///
/// Deliberately *not* a segment. Segments are beats of the script and everything about them is
/// derived from their order; a piece of music is pinned to a moment and keeps its place when the
/// video around it is re-cut. Two different things, so two different types — the alternative is a
/// segment with half its fields meaningless, which is how a timeline model rots.
///
/// Stored relative to the project directory for the same reason recordings are: container paths
/// change between installs, absolute ones stop resolving, and the audio disappears without a word.
public struct AudioClip: Identifiable, Hashable, Sendable, Codable {
    public enum Role: String, Hashable, Sendable, Codable, CaseIterable {
        /// Under everything, and the thing ducking exists for.
        case music
        /// Someone talking, over the footage.
        case voiceover
        /// A whoosh, a click, a riser.
        case effect
    }

    public let id: UUID
    public var name: String
    public var relativePath: String
    public var role: Role
    /// Where on the finished timeline this clip begins.
    public var start: MediaTime
    /// Which part of the file plays. Trimming edits this and never touches the file.
    public var sourceRange: MediaTimeRange
    /// Linear, 1 = as recorded. Linear rather than dB in storage because that is what the mixer
    /// wants; the interface talks in dB, which is what ears want.
    public var gain: Double
    public var fadeIn: MediaTime
    public var fadeOut: MediaTime
    /// 0.5 … 2. Pitch is preserved at export, so a sped-up voiceover does not turn into a chipmunk.
    public var speed: Double
    public var isMuted: Bool
    /// Drops under the speaking segments. The single most requested thing in any editor that has
    /// both music and a voice, and the one people otherwise fake with a dozen keyframes.
    public var ducksUnderVoice: Bool
    public var effects: AudioEffects

    public init(
        id: UUID = UUID(),
        name: String,
        relativePath: String,
        role: Role = .music,
        start: MediaTime = .zero,
        sourceRange: MediaTimeRange,
        gain: Double = 1,
        fadeIn: MediaTime = MediaTime(seconds: 0.4),
        fadeOut: MediaTime = MediaTime(seconds: 0.8),
        speed: Double = 1,
        isMuted: Bool = false,
        ducksUnderVoice: Bool = true,
        effects: AudioEffects = AudioEffects()
    ) {
        self.id = id
        self.name = name
        self.relativePath = relativePath
        self.role = role
        self.start = start
        self.sourceRange = sourceRange
        self.gain = gain
        self.fadeIn = fadeIn
        self.fadeOut = fadeOut
        self.speed = speed
        self.isMuted = isMuted
        self.ducksUnderVoice = ducksUnderVoice
        self.effects = effects
    }

    /// How long it occupies the timeline, which is not how long the source is once speed is in play.
    public var timelineDuration: MediaTime {
        MediaTime(seconds: sourceRange.duration.seconds / max(0.1, speed))
    }

    public var timelineRange: MediaTimeRange {
        MediaTimeRange(start: start, duration: timelineDuration)
    }

    /// Volume in dB, which is the only scale a level control should ever be drawn on: a linear
    /// slider spends three quarters of its travel on the range nobody uses.
    public var decibels: Double {
        gain <= 0.0001 ? -60 : 20 * log10(gain)
    }

    public mutating func setDecibels(_ value: Double) {
        gain = value <= -59.5 ? 0 : pow(10, min(max(value, -60), 6) / 20)
    }

    public func copyWithNewIdentity() -> AudioClip {
        AudioClip(
            name: name,
            relativePath: relativePath,
            role: role,
            start: start,
            sourceRange: sourceRange,
            gain: gain,
            fadeIn: fadeIn,
            fadeOut: fadeOut,
            speed: speed,
            isMuted: isMuted,
            ducksUnderVoice: ducksUnderVoice,
            effects: effects
        )
    }
}

/// What to do to the sound before anybody hears it.
///
/// Flags rather than a chain of parameters on purpose. Someone editing on a phone wants "fix it",
/// not a four-band EQ; the parameters live in the engine where they can be tuned once for
/// everybody instead of guessed at by each user.
public struct AudioEffects: Hashable, Sendable, Codable {
    /// Hiss, fan hum, room. A broad cut where noise lives and speech does not.
    public var noiseReduction: Bool
    /// Presence lift around the consonants, which is what makes a voice legible on a phone speaker.
    public var voiceEnhance: Bool
    /// Handling, traffic, air conditioning: everything under 90 Hz, which no phone speaker can
    /// reproduce anyway and which eats headroom the voice needs.
    public var deRumble: Bool

    public init(noiseReduction: Bool = false, voiceEnhance: Bool = false, deRumble: Bool = false) {
        self.noiseReduction = noiseReduction
        self.voiceEnhance = voiceEnhance
        self.deRumble = deRumble
    }

    public var isActive: Bool { noiseReduction || voiceEnhance || deRumble }
}
