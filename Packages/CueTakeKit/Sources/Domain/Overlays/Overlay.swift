import Foundation

/// A picture or a line of text laid over the video for a stretch of time.
///
/// Times are on the finished video, like music: an overlay belongs to a moment of the edit, not to
/// a clip, and a title that should appear at 29 seconds is at 29 seconds whichever clip is there.
/// Geometry is relative to the frame, so one overlay looks the same at 1080p and 8K and in the
/// preview.
public struct Overlay: Identifiable, Hashable, Sendable, Codable {
    public enum Content: Hashable, Sendable, Codable {
        /// An image file in the project's media folder. `aspect` is its width over its height.
        case image(relativePath: String, aspect: Double)
        case text(OverlayText)
    }

    public var id: UUID
    public var content: Content
    public var start: MediaTime
    public var duration: MediaTime
    public var transform: OverlayTransform
    public var animation: OverlayAnimation
    /// Drawn behind the people in the picture rather than over them: a title a person stands in
    /// front of. The picture is cut around them on every frame as it plays.
    public var isBehindPerson: Bool = false
    /// Set on a picture drawn from a brand template, so its words can be changed and the picture
    /// drawn again.
    public var template: OverlayTemplate? = nil

    public init(
        id: UUID = UUID(),
        content: Content,
        start: MediaTime,
        duration: MediaTime = MediaTime(seconds: 3),
        transform: OverlayTransform = OverlayTransform(),
        animation: OverlayAnimation = .fade
    ) {
        self.id = id
        self.content = content
        self.start = start
        self.duration = duration
        self.transform = transform
        self.animation = animation
    }

    public var range: MediaTimeRange { MediaTimeRange(start: start, duration: duration) }

    public func isVisible(at seconds: Double) -> Bool {
        seconds >= start.seconds && seconds < start.seconds + duration.seconds
    }

    public var isText: Bool {
        if case .text = content { return true }
        return false
    }

    /// The shortest an overlay can be. Below this it is a flash.
    public static let shortest = 0.2

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        content = try c.decode(Content.self, forKey: .content)
        start = (try? c.decode(MediaTime.self, forKey: .start)) ?? .zero
        duration = (try? c.decode(MediaTime.self, forKey: .duration)) ?? MediaTime(seconds: 3)
        transform = (try? c.decode(OverlayTransform.self, forKey: .transform)) ?? OverlayTransform()
        animation = (try? c.decode(OverlayAnimation.self, forKey: .animation)) ?? .fade
        isBehindPerson = (try? c.decodeIfPresent(Bool.self, forKey: .isBehindPerson)) ?? false
        template = try? c.decodeIfPresent(OverlayTemplate.self, forKey: .template)
    }

    /// How much of it shows at a moment, fades included. Pop and slide are not motion that can
    /// be drawn behind a person, so behind one they simply appear.
    public func visibility(at seconds: Double) -> Double {
        guard isVisible(at: seconds) else { return 0 }
        var level = min(max(transform.opacity, 0), 1)
        if animation == .fade {
            let length = max(0.05, duration.seconds)
            let edge = min(0.25, length * 0.3)
            let into = seconds - start.seconds
            level *= min(1, into / edge, (length - into) / edge)
        }
        return max(0, level)
    }
}

/// What a template picture was drawn from: which template, every line of it, its colour, its
/// look and its face.
public struct OverlayTemplate: Hashable, Sendable, Codable {
    public var id: String
    /// Each line by its slot's name.
    public var texts: [String: String]
    public var accent: RGBAColor
    public var isLight: Bool
    public var font: String

    public init(id: String, texts: [String: String], accent: RGBAColor, isLight: Bool, font: String) {
        self.id = id
        self.texts = texts
        self.accent = accent
        self.isLight = isLight
        self.font = font
    }
}

public struct OverlayText: Hashable, Sendable, Codable {
    public var text: String
    /// PostScript name of a bundled face.
    public var fontName: String
    public var color: RGBAColor
    /// A plate behind the text, or nil for an outlined text over the picture.
    public var background: RGBAColor?

    public init(
        text: String,
        fontName: String = "Archivo-ExtraBold",
        color: RGBAColor = .white,
        background: RGBAColor? = nil
    ) {
        self.text = text
        self.fontName = fontName
        self.color = color
        self.background = background
    }

    /// The faces offered for text overlays.
    public static let fonts = ["Archivo-ExtraBold", "Archivo-Bold", "InstrumentSans-SemiBold", "InstrumentSans-Regular", "JetBrainsMono-Medium"]
}

/// Where an overlay sits and how it is turned. All relative to the video frame.
public struct OverlayTransform: Hashable, Sendable, Codable {
    /// Centre, 0…1 from the left and from the top.
    public var x: Double
    public var y: Double
    /// 1 is the default size: an image half the frame's width, text at a readable title size.
    public var scale: Double
    /// Degrees, clockwise.
    public var rotation: Double
    public var flipX: Bool
    public var flipY: Bool
    public var opacity: Double

    public init(x: Double = 0.5, y: Double = 0.5, scale: Double = 1, rotation: Double = 0, flipX: Bool = false, flipY: Bool = false, opacity: Double = 1) {
        self.x = x
        self.y = y
        self.scale = scale
        self.rotation = rotation
        self.flipX = flipX
        self.flipY = flipY
        self.opacity = opacity
    }

    public static let scaleRange: ClosedRange<Double> = 0.1...4

    /// An image's width as a fraction of the frame's width.
    public var imageWidthFraction: Double { 0.5 * scale }
    /// Text size as a fraction of the frame's height.
    public var textSizeFraction: Double { 0.05 * scale }
}

public enum OverlayAnimation: String, Hashable, Sendable, Codable, CaseIterable {
    case none
    case fade
    case pop
    case slideUp
}

extension Project {
    /// Overlays on screen at a moment, bottom to top.
    public func overlays(at seconds: Double) -> [Overlay] {
        overlays.filter { $0.isVisible(at: seconds) }
    }
}
