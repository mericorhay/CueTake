import Foundation

/// A colour look over a stretch, as the model asked for it. With `effect` it changes that filter;
/// without, it lays a new one over `from`–`to` of the finished video, else the clip, else the video.
public struct FilterRequest: Hashable, Sendable {
    public var effect: String?
    public var clip: String?
    public var from: Double?
    public var to: Double?
    public var look: String?
    public var intensity: Double?
    public var brightness: Double?
    public var contrast: Double?
    public var saturation: Double?
    public var warmth: Double?
    public var vignette: Double?
    public var sharpness: Double?

    public init(
        effect: String? = nil, clip: String? = nil, from: Double? = nil, to: Double? = nil, look: String? = nil,
        intensity: Double? = nil, brightness: Double? = nil, contrast: Double? = nil, saturation: Double? = nil,
        warmth: Double? = nil, vignette: Double? = nil, sharpness: Double? = nil
    ) {
        self.effect = effect; self.clip = clip; self.from = from; self.to = to; self.look = look
        self.intensity = intensity; self.brightness = brightness; self.contrast = contrast
        self.saturation = saturation; self.warmth = warmth; self.vignette = vignette; self.sharpness = sharpness
    }

    func resolving(effect: (String) -> String, clip: (String) -> String) -> FilterRequest {
        var copy = self
        copy.effect = self.effect.map(effect)
        copy.clip = self.clip.map(clip)
        return copy
    }

    /// The settings with every field the model sent laid over `base`.
    public func applied(to base: FilterSettings) -> FilterSettings {
        var value = base
        if let look, let parsed = FilterSettings.Look(rawValue: look) { value.look = parsed }
        if let intensity { value.intensity = Self.unit(intensity) }
        if let brightness { value.brightness = Self.signed(brightness) }
        if let contrast { value.contrast = Self.signed(contrast) }
        if let saturation { value.saturation = Self.signed(saturation) }
        if let warmth { value.warmth = Self.signed(warmth) }
        if let vignette { value.vignette = Self.unit(vignette) }
        if let sharpness { value.sharpness = Self.unit(sharpness) }
        return value.clamped
    }

    /// Models write 0.4 and 40 for the same thing.
    static func unit(_ value: Double) -> Double { abs(value) > 1 ? value / 100 : value }
    static func signed(_ value: Double) -> Double { abs(value) > 1 ? value / 100 : value }
}

/// A sound effect on the voice over a stretch, as the model asked for it.
public struct SoundRequest: Hashable, Sendable {
    public var effect: String?
    public var clip: String?
    public var from: Double?
    public var to: Double?
    public var preset: String?
    public var amount: Double?
    public var pitch: Double?
    public var volume: Double?

    public init(
        effect: String? = nil, clip: String? = nil, from: Double? = nil, to: Double? = nil,
        preset: String? = nil, amount: Double? = nil, pitch: Double? = nil, volume: Double? = nil
    ) {
        self.effect = effect; self.clip = clip; self.from = from; self.to = to
        self.preset = preset; self.amount = amount; self.pitch = pitch; self.volume = volume
    }

    func resolving(effect: (String) -> String, clip: (String) -> String) -> SoundRequest {
        var copy = self
        copy.effect = self.effect.map(effect)
        copy.clip = self.clip.map(clip)
        return copy
    }

    public func applied(to base: SoundSettings) -> SoundSettings {
        var value = base
        if let preset, let parsed = SoundSettings.Preset(rawValue: preset) {
            value.preset = parsed
            if pitch == nil { value.pitch = SoundSettings.defaultPitch(for: parsed) }
        }
        if let amount { value.amount = FilterRequest.unit(amount) }
        if let pitch { value.pitch = pitch }
        if let volume { value.volume = volume }
        return value.clamped
    }
}

/// Parts of an added video to change. Times are seconds of the finished video, except
/// `sourceStart`, which is where in its own file it starts; geometry is a fraction of the frame.
public struct VideoPatch: Hashable, Sendable {
    public var start: Double?
    public var end: Double?
    public var sourceStart: Double?
    public var x: Double?
    public var y: Double?
    public var width: Double?
    public var height: Double?
    public var opacity: Double?
    public var volume: Double?
    public var muted: Bool?
    public var hidden: Bool?
    public var mirrored: Bool?

    public init(
        start: Double? = nil, end: Double? = nil, sourceStart: Double? = nil, x: Double? = nil, y: Double? = nil,
        width: Double? = nil, height: Double? = nil, opacity: Double? = nil, volume: Double? = nil,
        muted: Bool? = nil, hidden: Bool? = nil, mirrored: Bool? = nil
    ) {
        self.start = start; self.end = end; self.sourceStart = sourceStart; self.x = x; self.y = y
        self.width = width; self.height = height; self.opacity = opacity; self.volume = volume
        self.muted = muted; self.hidden = hidden; self.mirrored = mirrored
    }

    public var isEmpty: Bool { self == VideoPatch() }

    /// A place in the frame with every geometry field the model sent laid over `base`.
    public func placement(over base: VideoPlacement) -> VideoPlacement {
        var value = base
        if let x { value.x = x }
        if let y { value.y = y }
        if let width { value.width = width }
        if let height { value.height = height }
        if let opacity { value.opacity = FilterRequest.unit(opacity) }
        if let mirrored { value.isMirrored = mirrored }
        return value.bounded
    }

    public var movesPlacement: Bool {
        x != nil || y != nil || width != nil || height != nil || opacity != nil || mirrored != nil
    }
}
