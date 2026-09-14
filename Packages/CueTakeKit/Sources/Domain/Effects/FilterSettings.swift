import Foundation

/// A colour look laid over a stretch of the picture.
///
/// Built from Core Image's own filters rather than lookup tables: they ship with the system, cost
/// nothing to download, run on the GPU in real time in the preview, and every one of them can be
/// dialled in or out with the intensity instead of being all or nothing.
public struct FilterSettings: Hashable, Sendable, Codable {
    public enum Look: String, Hashable, Sendable, Codable, CaseIterable {
        /// No look: only the adjustments.
        case natural
        case vivid
        case cinematic
        case warm
        case cool
        case vintage
        case fade
        case chrome
        case instant
        case dramatic
        case mono
        case noir
    }

    public var look: Look
    /// 0…1: how much of the look, over the picture as shot.
    public var intensity: Double
    /// −1…1 each; 0 leaves the picture alone.
    public var brightness: Double
    public var contrast: Double
    public var saturation: Double
    public var warmth: Double
    /// 0…1.
    public var vignette: Double
    /// 0…1.
    public var sharpness: Double

    public init(
        look: Look,
        intensity: Double = 1,
        brightness: Double = 0,
        contrast: Double = 0,
        saturation: Double = 0,
        warmth: Double = 0,
        vignette: Double = 0,
        sharpness: Double = 0
    ) {
        self.look = look
        self.intensity = intensity
        self.brightness = brightness
        self.contrast = contrast
        self.saturation = saturation
        self.warmth = warmth
        self.vignette = vignette
        self.sharpness = sharpness
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        look = (try? c.decode(Look.self, forKey: .look)) ?? .natural
        intensity = (try? c.decodeIfPresent(Double.self, forKey: .intensity)) ?? 1
        brightness = (try? c.decodeIfPresent(Double.self, forKey: .brightness)) ?? 0
        contrast = (try? c.decodeIfPresent(Double.self, forKey: .contrast)) ?? 0
        saturation = (try? c.decodeIfPresent(Double.self, forKey: .saturation)) ?? 0
        warmth = (try? c.decodeIfPresent(Double.self, forKey: .warmth)) ?? 0
        vignette = (try? c.decodeIfPresent(Double.self, forKey: .vignette)) ?? 0
        sharpness = (try? c.decodeIfPresent(Double.self, forKey: .sharpness)) ?? 0
    }

    /// Every value inside its range.
    public var clamped: FilterSettings {
        var value = self
        value.intensity = min(max(intensity, 0), 1)
        value.brightness = min(max(brightness, -1), 1)
        value.contrast = min(max(contrast, -1), 1)
        value.saturation = min(max(saturation, -1), 1)
        value.warmth = min(max(warmth, -1), 1)
        value.vignette = min(max(vignette, 0), 1)
        value.sharpness = min(max(sharpness, 0), 1)
        return value
    }
}

/// A treatment of the voice over a stretch of the video.
///
/// Rendered once per recording and setting with the system's audio units — reverb, delay,
/// distortion, EQ and pitch — so nothing is downloaded and the original sound is never touched.
public struct SoundSettings: Hashable, Sendable, Codable {
    public enum Preset: String, Hashable, Sendable, Codable, CaseIterable {
        /// No colour: only pitch and level.
        case clean
        case echo
        case hall
        case room
        case telephone
        case radio
        case megaphone
        case robot
        case underwater
        case deep
        case chipmunk
    }

    public var preset: Preset
    /// 0…1: how strong the effect is against the voice as recorded.
    public var amount: Double
    /// Semitones, −12…12.
    public var pitch: Double
    /// Decibels, −24…12.
    public var volume: Double

    public init(preset: Preset, amount: Double = 0.7, pitch: Double? = nil, volume: Double = 0) {
        self.preset = preset
        self.amount = amount
        self.pitch = pitch ?? Self.defaultPitch(for: preset)
        self.volume = volume
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        preset = (try? c.decode(Preset.self, forKey: .preset)) ?? .clean
        amount = (try? c.decodeIfPresent(Double.self, forKey: .amount)) ?? 0.7
        pitch = (try? c.decodeIfPresent(Double.self, forKey: .pitch)) ?? 0
        volume = (try? c.decodeIfPresent(Double.self, forKey: .volume)) ?? 0
    }

    public static func defaultPitch(for preset: Preset) -> Double {
        switch preset {
        case .deep: -5
        case .chipmunk: 6
        case .robot: -2
        default: 0
        }
    }

    public var clamped: SoundSettings {
        var value = self
        value.amount = min(max(amount, 0), 1)
        value.pitch = min(max(pitch, -12), 12)
        value.volume = min(max(volume, -24), 12)
        return value
    }

    /// Whether anything needs rendering, as opposed to only a change of level.
    public var needsRender: Bool {
        preset != .clean || abs(pitch) > 0.01
    }

    /// Everything that changes the rendered sound, file-name safe.
    public var token: String {
        "\(preset.rawValue)_a\(Int((amount * 100).rounded()))_p\(Int((pitch * 10).rounded()))"
    }

    /// The level change as a linear gain.
    public var gain: Double { pow(10, volume / 20) }
}

/// A stretch of one clip and the sound effect it plays with.
public struct SoundStretch: Hashable, Sendable {
    public var from: Double
    public var to: Double
    public var sound: SoundSettings?

    public init(from: Double, to: Double, sound: SoundSettings?) {
        self.from = from
        self.to = to
        self.sound = sound
    }
}
