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

    /// What a new project starts with: the Pop look, the one the captions screen opens on.
    public static var standard: CaptionStyle { .preset("pop") }
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
    /// The cue's words with the times they were said, in finished-video time. Empty when the cue
    /// did not come from a transcript — typed by hand, or built from a script — in which case
    /// nothing is highlighted rather than highlighted at invented times.
    public var words: [PlacedWord]

    public init(id: UUID, text: String, range: MediaTimeRange, words: [PlacedWord] = []) {
        self.id = id
        self.text = text
        self.range = range
        self.words = words
    }

    /// The index of the word being said at `seconds`, or of the last word already said. Nil
    /// before the first word starts.
    public func wordIndex(at seconds: Double) -> Int? {
        words.lastIndex { $0.range.start.seconds <= seconds }
    }
}

public struct PlacedWord: Hashable, Sendable {
    public var text: String
    public var range: MediaTimeRange

    public init(text: String, range: MediaTimeRange) {
        self.text = text
        self.range = range
    }
}

extension CaptionStyle {
    /// The three looks the app offers, as complete styles.
    ///
    /// They used to be names only: choosing Karaoke stored the word "karaoke" and every caption
    /// was drawn exactly as before. A preset is now the whole decision — face, size, case, colour,
    /// plate, how many words at once — so what the captions screen shows is what the preview draws
    /// and what the export burns in.
    /// Every look, in the order the captions screen offers them.
    public static let presetIDs = ["pop", "clean", "karaoke", "bold", "boxed", "minimal", "neon", "story"]

    public static func preset(_ id: String, position: CaptionPosition = .lowerThird) -> CaptionStyle {
        switch id {
        case "bold":
            // Two huge words at a time in capitals, the one being said turning yellow.
            CaptionStyle(
                presetID: "bold",
                fontName: "Archivo-ExtraBold",
                relativeFontSize: 0.05,
                textCase: .uppercase,
                textColor: .white,
                highlightColor: RGBAColor(red: 1, green: 0.84, blue: 0.04),
                maxWordsPerCue: 2,
                position: position
            )
        case "boxed":
            // Black on a white card: readable over anything, looks like a sticker.
            CaptionStyle(
                presetID: "boxed",
                fontName: "Archivo-Bold",
                relativeFontSize: 0.034,
                textCase: .natural,
                textColor: .black,
                backgroundColor: RGBAColor(red: 1, green: 1, blue: 1, alpha: 0.96),
                maxWordsPerCue: 4,
                position: position
            )
        case "minimal":
            // Small, lower case, many words: subtitles that stay out of the way.
            CaptionStyle(
                presetID: "minimal",
                fontName: "InstrumentSans-Regular",
                relativeFontSize: 0.027,
                textCase: .lowercase,
                textColor: .white,
                maxWordsPerCue: 7,
                position: position
            )
        case "neon":
            // The brand lime, outlined, three words at a time.
            CaptionStyle(
                presetID: "neon",
                fontName: "Archivo-Bold",
                relativeFontSize: 0.04,
                textCase: .uppercase,
                textColor: RGBAColor(red: 0xE8 / 255, green: 1, blue: 0x4F / 255),
                maxWordsPerCue: 3,
                position: position
            )
        case "story":
            // White on the coral plate, like a story sticker.
            CaptionStyle(
                presetID: "story",
                fontName: "Archivo-Bold",
                relativeFontSize: 0.036,
                textCase: .natural,
                textColor: .white,
                backgroundColor: RGBAColor(red: 1, green: 0x5A / 255, blue: 0x4F / 255, alpha: 0.95),
                maxWordsPerCue: 3,
                position: position
            )
        case "clean":
            // Quiet: medium weight on a dark plate, more words at once, reads like subtitles.
            CaptionStyle(
                presetID: "clean",
                fontName: "InstrumentSans-Medium",
                relativeFontSize: 0.03,
                textCase: .natural,
                textColor: .white,
                backgroundColor: RGBAColor(red: 0.04, green: 0.04, blue: 0.05, alpha: 0.62),
                maxWordsPerCue: 6,
                position: position
            )
        case "karaoke":
            // Words light up as they are said. Fewer at once, so the eye can follow the fill.
            CaptionStyle(
                presetID: "karaoke",
                fontName: "Archivo-Bold",
                relativeFontSize: 0.038,
                textCase: .natural,
                textColor: .white,
                highlightColor: RGBAColor(red: 0xE8 / 255, green: 1, blue: 0x4F / 255),
                maxWordsPerCue: 4,
                position: position
            )
        default:
            // Loud: extra-bold, outlined, three words at a time — the look short video is known for.
            CaptionStyle(
                presetID: "pop",
                fontName: "Archivo-ExtraBold",
                relativeFontSize: 0.042,
                textCase: .natural,
                textColor: .white,
                maxWordsPerCue: 3,
                position: position
            )
        }
    }

    /// Whether words are lit one after another as they are said.
    public var highlightsWords: Bool {
        highlightColor != nil
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

            let spoken = segment.selectedTake?.transcript?.words ?? []

            for (cueIndex, cue) in segment.captions.enumerated() {
                let nextCueStart = cueIndex + 1 < segment.captions.count
                    ? segment.captions[cueIndex + 1].range.start.seconds
                    : nil
                let adaptive = CaptionTimingEngine.range(
                    for: cue,
                    transcript: Transcript(localeIdentifier: project.localeIdentifier, words: spoken),
                    nextStart: nextCueStart
                )
                let relativeRange = adaptive ?? cue.range
                let start = cursor + relativeRange.start.seconds * stretch
                let duration = max(0.2, relativeRange.duration.seconds * stretch)
                guard start < cursor + length + 0.01 else { continue }

                // The words inside this cue's time, from the transcript. A cue the user retyped
                // no longer matches what was said word for word, so it is shown without them.
                let words: [PlacedWord] = cue.isUserEdited ? [] : spoken
                    .filter {
                            $0.range.start.seconds >= relativeRange.start.seconds - 0.02
                            && $0.range.start.seconds < relativeRange.end.seconds - 0.01
                    }
                    .map { word in
                        PlacedWord(
                            text: word.text,
                            range: MediaTimeRange(
                                start: MediaTime(seconds: cursor + word.range.start.seconds * stretch),
                                duration: MediaTime(seconds: max(0.05, word.range.duration.seconds * stretch))
                            )
                        )
                    }

                cues.append(
                    PlacedCue(
                        id: cue.id,
                        text: cue.text,
                        range: MediaTimeRange(
                            start: MediaTime(seconds: start),
                            // Never past the end of its own clip: a cue outstaying its footage is
                            // how a caption ends up over the next person's face.
                            duration: MediaTime(seconds: min(duration, cursor + length - start))
                        ),
                        words: words
                    )
                )
            }
            cursor += length
        }
        // Only inside the window the user chose, cut to its edges.
        guard let window = captionWindow else { return cues }
        return cues.compactMap { cue in
            let start = max(cue.range.start.seconds, window.start.seconds)
            let end = min(cue.range.end.seconds, window.end.seconds)
            guard end - start > 0.05 else { return nil }
            var clipped = cue
            clipped.range = MediaTimeRange(start: MediaTime(seconds: start), duration: MediaTime(seconds: end - start))
            clipped.words = cue.words.filter { $0.range.start.seconds >= start - 0.01 && $0.range.start.seconds < end }
            return clipped
        }
    }

    /// The cue on screen at a given moment, if any.
    public func caption(at seconds: Double) -> PlacedCue? {
        captionCues.first { $0.range.contains(MediaTime(seconds: seconds)) }
    }
}
