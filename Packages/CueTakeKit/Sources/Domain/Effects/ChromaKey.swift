import Foundation

/// A colour taken out of the picture: a green or blue screen, or any flat backdrop.
///
/// The picture is compared with the key colour by hue and colourfulness only (the Cb/Cr of
/// YCbCr), never brightness, so the shadow a person throws on the screen goes with the screen.
/// What is left of the colour on hair and shoulders — the green glow a screen casts — is taken
/// down by `spill`.
public struct ChromaKey: Hashable, Sendable, Codable {
    public var color: RGBAColor
    /// 0…1. How far from the key colour a pixel can be and still go.
    public var tolerance: Double
    /// 0…1. How wide the half-see-through edge between gone and kept is.
    public var softness: Double
    /// 0…1. How much of the key colour's cast is taken off what stays.
    public var spill: Double

    public init(color: RGBAColor, tolerance: Double = 0.4, softness: Double = 0.3, spill: Double = 0.6) {
        self.color = color
        self.tolerance = min(max(tolerance, 0), 1)
        self.softness = min(max(softness, 0), 1)
        self.spill = min(max(spill, 0), 1)
    }

    /// The green of a studio screen.
    public static let green = ChromaKey(color: RGBAColor(red: 0.0, green: 0.78, blue: 0.25))
    /// The blue of a studio screen.
    public static let blue = ChromaKey(color: RGBAColor(red: 0.05, green: 0.25, blue: 0.9))

    public var clamped: ChromaKey {
        ChromaKey(color: color, tolerance: tolerance, softness: softness, spill: spill)
    }

    /// Everything that changes the picture, as a file-name-safe string.
    public var token: String {
        func percent(_ value: Double) -> Int { Int((min(max(value, 0), 1) * 100).rounded()) }
        return "k\(String(color.hex.dropFirst()))t\(percent(tolerance))s\(percent(softness))p\(percent(spill))"
    }

    /// Distance in Cb/Cr under which a pixel is fully gone.
    var inner: Double { 0.06 + 0.32 * tolerance }
    /// Distance over which a pixel is fully kept.
    var outer: Double { inner + 0.015 + 0.2 * softness }

    /// One sRGB pixel keyed: its colour with the spill taken off, and how much of it stays
    /// (0 gone, 1 kept). Not premultiplied. The colour cube is filled with exactly this.
    public func keyed(red: Double, green: Double, blue: Double) -> (red: Double, green: Double, blue: Double, alpha: Double) {
        let pixel = Self.chroma(red, green, blue)
        let key = Self.chroma(color.red, color.green, color.blue)
        let distance = hypot(pixel.cb - key.cb, pixel.cr - key.cr)
        let edge = min(max((distance - inner) / max(outer - inner, 0.0001), 0), 1)
        let alpha = edge * edge * (3 - 2 * edge)

        var channels = [red, green, blue]
        let keyChannels = [color.red, color.green, color.blue]
        // The screen's own channel, held down to the brightest of the other two: a green cast
        // on skin goes, a green shirt that is really green mostly stays.
        if spill > 0.001, let dominant = keyChannels.indices.max(by: { keyChannels[$0] < keyChannels[$1] }) {
            let others = channels.indices.filter { $0 != dominant }.map { channels[$0] }
            let limit = others.max() ?? channels[dominant]
            if channels[dominant] > limit {
                channels[dominant] -= (channels[dominant] - limit) * spill
            }
        }
        return (channels[0], channels[1], channels[2], alpha)
    }

    /// BT.601 colour difference of a gamma-encoded pixel.
    static func chroma(_ red: Double, _ green: Double, _ blue: Double) -> (cb: Double, cr: Double) {
        (
            -0.168736 * red - 0.331264 * green + 0.5 * blue,
            0.5 * red - 0.418688 * green - 0.081312 * blue
        )
    }
}
