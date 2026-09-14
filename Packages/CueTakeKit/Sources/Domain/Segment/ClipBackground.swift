import Foundation

/// What replaces everything behind the person in a clip.
///
/// The person is cut out of every frame on the device; what was behind them becomes one of these.
/// A decision about the footage like speed or reverse, never baked into the recording.
public enum ClipBackground: String, Hashable, Sendable, Codable, CaseIterable {
    /// The real background, softly out of focus: a portrait look that keeps the room.
    case blur
    case black
    case white
    /// A flat green, for keying in another app.
    case green
    /// A dark studio gradient.
    case studio
    /// The real background, darkened, so the person stands out and the room stays.
    case dim
    /// Any flat colour.
    case color

    public var token: String { rawValue }
}
