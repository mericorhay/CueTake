import Foundation

public struct CaptionCue: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public var text: String
    /// Relative to the start of the owning segment. The timeline adds the segment's offset.
    public var range: MediaTimeRange
    /// Nil uses the project's caption style.
    public var styleOverride: CaptionStyle?
    /// Nil uses the style's position.
    public var position: CaptionPosition?
    /// Set when the user edits the cue by hand.
    public var isUserEdited: Bool

    public init(
        id: UUID = UUID(),
        text: String,
        range: MediaTimeRange,
        styleOverride: CaptionStyle? = nil,
        position: CaptionPosition? = nil,
        isUserEdited: Bool = false
    ) {
        self.id = id
        self.text = text
        self.range = range
        self.styleOverride = styleOverride
        self.position = position
        self.isUserEdited = isUserEdited
    }
}

public struct CaptionStyle: Hashable, Sendable, Codable {
    /// Identifies the preset the style came from, e.g. "bold-pop".
    public var presetID: String
    /// PostScript name. Nil means the system font.
    public var fontName: String?
    /// Font size as a fraction of the video height, so one style works at 1080p and 4K.
    public var relativeFontSize: Double
    public var textCase: CaptionTextCase
    public var textColor: RGBAColor
    /// Color for the word currently being spoken. Nil disables word highlighting.
    public var highlightColor: RGBAColor?
    public var backgroundColor: RGBAColor?
    public var maxWordsPerCue: Int
    public var position: CaptionPosition

    public init(
        presetID: String,
        fontName: String? = nil,
        relativeFontSize: Double,
        textCase: CaptionTextCase,
        textColor: RGBAColor,
        highlightColor: RGBAColor? = nil,
        backgroundColor: RGBAColor? = nil,
        maxWordsPerCue: Int,
        position: CaptionPosition
    ) {
        self.presetID = presetID
        self.fontName = fontName
        self.relativeFontSize = relativeFontSize
        self.textCase = textCase
        self.textColor = textColor
        self.highlightColor = highlightColor
        self.backgroundColor = backgroundColor
        self.maxWordsPerCue = maxWordsPerCue
        self.position = position
    }

    public static let standard = CaptionStyle(
        presetID: "standard",
        relativeFontSize: 0.035,
        textCase: .natural,
        textColor: .white,
        highlightColor: RGBAColor(red: 1, green: 0.84, blue: 0.2),
        maxWordsPerCue: 4,
        position: .lowerThird
    )
}

public enum CaptionTextCase: String, Hashable, Sendable, Codable {
    case natural
    case uppercase
    case lowercase

    /// Must be locale-aware: "istanbul" is "İSTANBUL" in Turkish, not "ISTANBUL".
    public func apply(to text: String, locale: Locale) -> String {
        switch self {
        case .natural: text
        case .uppercase: text.uppercased(with: locale)
        case .lowercase: text.lowercased(with: locale)
        }
    }
}

/// Normalized position of the caption's center; (0, 0) is top-left, (1, 1) bottom-right.
public struct CaptionPosition: Hashable, Sendable, Codable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    public static let lowerThird = CaptionPosition(x: 0.5, y: 0.72)
    public static let center = CaptionPosition(x: 0.5, y: 0.5)
}

public struct RGBAColor: Hashable, Sendable, Codable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    public static let white = RGBAColor(red: 1, green: 1, blue: 1)
    public static let black = RGBAColor(red: 0, green: 0, blue: 0)
}
