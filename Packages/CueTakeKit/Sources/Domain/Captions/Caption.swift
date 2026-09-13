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

/// A cue placed in finished-video time.
///
/// Derived, never stored, like every other absolute time in this app. Cues live on their segment
/// with times relative to it; the moment a clip ahead of them is trimmed, split or slowed, their
/// place in the video changes and nothing about the cue itself does.
public struct PlacedCue: Identifiable, Hashable, Sendable {
    public let id: UUID
    public var text: String
    public var range: MediaTimeRange

    public init(id: UUID, text: String, range: MediaTimeRange) {
        self.id = id
        self.text = text
        self.range = range
    }
}

extension Project {
    /// Every cue in the project, in the order and at the times they will appear in the export.
    ///
    /// Laid out against `barWeight` — the same number the timeline, the composer and the editor
    /// all use — so what the preview draws, what the export burns in and what the timeline shows
    /// cannot drift apart. A caption system that computes its own idea of where a clip starts is
    /// a caption system that will one day be a frame out and no one will know why.
    public var captionCues: [PlacedCue] {
        var cues: [PlacedCue] = []
        var cursor = 0.0

        for segment in segments {
            let length = segment.barWeight
            // Speed and freeze change how long a clip lasts, so the cues inside it have to move
            // with it: a cue at three seconds into a half-speed clip is at six.
            let stretch = segment.sourceSeconds > 0.01 ? length / segment.sourceSeconds : 1

            for cue in segment.captions {
                let start = cursor + cue.range.start.seconds * stretch
                let duration = max(0.2, cue.range.duration.seconds * stretch)
                guard start < cursor + length + 0.01 else { continue }
                cues.append(
                    PlacedCue(
                        id: cue.id,
                        text: cue.text,
                        range: MediaTimeRange(
                            start: MediaTime(seconds: start),
                            // Never past the end of its own clip: a cue outstaying its footage is
                            // how a caption ends up over the next person's face.
                            duration: MediaTime(seconds: min(duration, cursor + length - start))
                        )
                    )
                )
            }
            cursor += length
        }
        return cues
    }

    /// The cue on screen at a given moment, if any.
    public func caption(at seconds: Double) -> PlacedCue? {
        captionCues.first { $0.range.contains(MediaTime(seconds: seconds)) }
    }
}
