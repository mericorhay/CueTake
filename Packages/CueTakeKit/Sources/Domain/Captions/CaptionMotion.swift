import Foundation

/// How a caption arrives on screen.
public enum CaptionEntrance: String, Hashable, Sendable, Codable, CaseIterable {
    /// Already there.
    case none
    case fade
    /// Springs up from smaller.
    case pop
    /// Slides up a little as it fades in.
    case rise
    /// Each word appears as it is said.
    case typewriter
    /// Each word springs in as it is said.
    case bounce
}

/// How the word being said stands out.
public enum CaptionEmphasis: String, Hashable, Sendable, Codable, CaseIterable {
    case none
    /// Said words take the highlight colour, filling the line left to right.
    case color
    /// The word being said grows.
    case scale
    /// The word being said sits on a coloured card.
    case box
}

extension CaptionStyle {
    /// Styles written before entrances existed keep the arrival they always had.
    public var resolvedEntrance: CaptionEntrance {
        entrance ?? (["pop", "bold", "story"].contains(presetID) ? .pop : .fade)
    }

    public var resolvedEmphasis: CaptionEmphasis {
        emphasis ?? (highlightColor == nil ? CaptionEmphasis.none : .color)
    }

    /// The outline, as a fraction of the font size. Plated styles need none.
    public var resolvedStrokeWeight: Double {
        strokeWeight ?? (backgroundColor == nil ? 0.14 : 0)
    }

    public var resolvedStrokeColor: RGBAColor {
        strokeColor ?? .black
    }

    /// What the word being said is marked with.
    public var emphasisColor: RGBAColor {
        highlightColor ?? RGBAColor(red: 0xE8 / 255, green: 1, blue: 0x4F / 255)
    }

    /// The colour of a said word's text, when its card is behind it.
    public var boxedTextColor: RGBAColor {
        let c = emphasisColor
        let light = 0.299 * c.red + 0.587 * c.green + 0.114 * c.blue
        return light > 0.6 ? .black : .white
    }
}

/// One moment of a caption, as both the preview and the export draw it.
public struct CaptionFrame: Hashable, Sendable {
    public struct Word: Hashable, Sendable {
        public var opacity: Double = 1
        public var scale: Double = 1
        /// Up/down, as a fraction of the font size; positive is down.
        public var offset: Double = 0
        /// Said already (for colour filling).
        public var isLit = false
        /// Being said now.
        public var isActive = false
        /// Opacity of the card behind it.
        public var box: Double = 0

        public init() {}
    }

    public var opacity: Double = 1
    public var scale: Double = 1
    public var offset: Double = 0
    public var words: [Word]
}

/// Where each word of a cue is, and how it looks, at any moment.
///
/// A pure function of the cue, the style and the time, so the SwiftUI preview (every frame) and
/// the Core Animation export (sampled into keyframes) cannot disagree.
public enum CaptionAnimator {
    public static let entranceSeconds = 0.24
    public static let exitSeconds = 0.08

    /// When each displayed word starts. Real times when the transcript has them; otherwise spread
    /// evenly over the first two thirds of the cue, so typed captions still animate.
    public static func wordStarts(for cue: PlacedCue, count: Int) -> [Double] {
        let start = cue.range.start.seconds
        if cue.words.count == count, count > 0 {
            return cue.words.map { max(start, $0.range.start.seconds) }
        }
        let span = cue.range.duration.seconds * 0.66
        return (0..<count).map { start + span * Double($0) / Double(max(1, count)) }
    }

    public static func frame(for cue: PlacedCue, wordCount: Int, style: CaptionStyle, at time: Double) -> CaptionFrame {
        let start = cue.range.start.seconds
        let end = cue.range.end.seconds
        let t = time - start
        var frame = CaptionFrame(words: Array(repeating: CaptionFrame.Word(), count: wordCount))
        guard time >= start - 0.0001, time <= end + 0.0001 else {
            frame.opacity = 0
            return frame
        }

        // Leaving: a short fade, whatever the entrance.
        let remaining = end - time
        let exit = remaining < exitSeconds ? max(0, remaining / exitSeconds) : 1

        let p = min(max(t / entranceSeconds, 0), 1)
        switch style.resolvedEntrance {
        case .none, .typewriter, .bounce:
            frame.opacity = exit
        case .fade:
            frame.opacity = min(1, t / 0.12) * exit
        case .pop:
            frame.opacity = min(1, t / 0.08) * exit
            frame.scale = 0.72 + 0.28 * easeOutBack(p)
        case .rise:
            frame.opacity = min(1, t / 0.14) * exit
            frame.offset = (1 - easeOut(p)) * 0.55
        }

        let starts = wordStarts(for: cue, count: wordCount)
        let timed = cue.words.count == wordCount && wordCount > 0
        let active: Int? = timed ? starts.lastIndex(where: { $0 <= time }) : nil
        for index in 0..<wordCount {
            let since = time - starts[index]
            var word = CaptionFrame.Word()
            switch style.resolvedEntrance {
            case .typewriter:
                word.opacity = since < 0 ? 0 : min(1, since / 0.06)
            case .bounce:
                let q = min(max(since / 0.2, 0), 1)
                word.opacity = since < 0 ? 0 : min(1, since / 0.06)
                word.scale = since < 0 ? 0.6 : 0.6 + 0.4 * easeOutBack(q)
                word.offset = since < 0 ? 0.3 : (1 - easeOut(q)) * 0.3
            default:
                break
            }
            if let active {
                word.isLit = index <= active
                word.isActive = index == active
                switch style.resolvedEmphasis {
                case .scale where index == active:
                    word.scale *= 1 + 0.18 * min(1, since / 0.08)
                case .box where index == active:
                    word.box = min(1, since / 0.05)
                default:
                    break
                }
            }
            if style.backgroundColor != nil {
                // The plate is drawn around the words at rest; a word that jumps or grows past it
                // spills over its top and bottom edge. On a plate words fade and light, and grow
                // only a little.
                word.offset = 0
                word.scale = min(max(word.scale, 0.92), 1.06)
            }
            frame.words[index] = word
        }
        return frame
    }

    static func easeOut(_ t: Double) -> Double {
        1 - pow(1 - t, 3)
    }

    /// Overshoots a little, then settles: the spring every short-video caption has.
    static func easeOutBack(_ t: Double) -> Double {
        let c1 = 1.70158, c3 = c1 + 1
        return 1 + c3 * pow(t - 1, 3) + c1 * pow(t - 1, 2)
    }
}

/// The words of a cue as they are shown: case applied, keywords found, an emoji after the first.
public struct CaptionWords: Hashable, Sendable {
    public var words: [String]
    public var keywords: Set<Int>

    public init(cue: PlacedCue, style: CaptionStyle, locale projectLocale: Locale) {
        let locale = cue.localeIdentifier.map(Locale.init(identifier:)) ?? projectLocale
        let raw = cue.words.isEmpty
            ? cue.text.split(whereSeparator: \.isWhitespace).map(String.init)
            : cue.words.map(\.text)
        var words: [String] = []
        var keywords: Set<Int> = []
        for (index, word) in raw.enumerated() {
            let marked = word.count > 2 && word.hasPrefix("*") && word.hasSuffix("*")
            let plain = marked ? String(word.dropFirst().dropLast()) : word
            if marked || CaptionKeywords.isKeyword(plain, locale: locale) { keywords.insert(index) }
            words.append(style.textCase.apply(to: plain, locale: locale))
        }
        if style.emoji == true, let first = keywords.min(),
           let emoji = CaptionKeywords.emoji(for: raw[first], locale: locale) {
            words[first] += " " + emoji
        }
        self.words = words
        self.keywords = style.keywordColor == nil ? [] : keywords
    }
}

/// Words worth colouring: numbers, money, and the words short video leans on.
public enum CaptionKeywords {
    static let power: Set<String> = [
        // English
        "free", "secret", "never", "always", "now", "money", "best", "worst", "mistake", "stop",
        "new", "fast", "easy", "win", "love", "hate", "why", "how", "truth", "only",
        // Turkish
        "ücretsiz", "bedava", "sır", "asla", "hemen", "şimdi", "para", "en", "hata", "dur",
        "yeni", "hızlı", "kolay", "kazan", "aşk", "neden", "nasıl", "gerçek", "sadece", "dikkat",
        // Spanish
        "gratis", "secreto", "nunca", "siempre", "ahora", "dinero", "mejor", "peor", "error",
        "nuevo", "rápido", "fácil", "gana", "amor", "odio", "cómo", "verdad", "solo", "cuidado",
    ]

    static let emojis: [String: String] = [
        "money": "💰", "para": "💰", "free": "🎁", "ücretsiz": "🎁", "bedava": "🎁",
        "secret": "🤫", "sır": "🤫", "love": "❤️", "aşk": "❤️", "fast": "⚡️", "hızlı": "⚡️",
        "mistake": "⚠️", "hata": "⚠️", "dikkat": "⚠️", "stop": "✋", "dur": "✋",
        "win": "🏆", "kazan": "🏆", "why": "🤔", "neden": "🤔", "new": "✨", "yeni": "✨",
        "truth": "💯", "gerçek": "💯", "time": "⏰", "zaman": "⏰", "idea": "💡", "fikir": "💡",
        "dinero": "💰", "gratis": "🎁", "secreto": "🤫", "amor": "❤️", "rápido": "⚡️", "error": "⚠️",
        "cuidado": "⚠️", "gana": "🏆", "nuevo": "✨", "verdad": "💯", "tiempo": "⏰",
    ]

    static func normalized(_ word: String, locale: Locale) -> String {
        word.lowercased(with: locale).trimmingCharacters(in: .punctuationCharacters.union(.symbols))
    }

    public static func isKeyword(_ word: String, locale: Locale) -> Bool {
        if word.contains(where: \.isNumber) || word.contains("%") || word.contains("$") || word.contains("₺") || word.contains("€") {
            return true
        }
        let key = normalized(word, locale: locale)
        return key.count > 1 && power.contains(key)
    }

    public static func emoji(for word: String, locale: Locale) -> String? {
        let key = normalized(word, locale: locale)
        if word.contains(where: \.isNumber) { return nil }
        return emojis[key]
    }
}

/// Greedy line breaking shared by both renderers, so the preview and the file break alike.
public enum CaptionLineBreaker {
    /// Word indices per line.
    public static func lines(widths: [Double], space: Double, maxWidth: Double) -> [[Int]] {
        var lines: [[Int]] = []
        var current: [Int] = []
        var width = 0.0
        for (index, w) in widths.enumerated() {
            let added = current.isEmpty ? w : width + space + w
            if !current.isEmpty, added > maxWidth {
                lines.append(current)
                current = [index]
                width = w
            } else {
                current.append(index)
                width = added
            }
        }
        if !current.isEmpty { lines.append(current) }
        return lines
    }
}

/// Captions shown too fast to read.
public enum CaptionReadability {
    /// Characters a second above which most viewers miss words.
    public static let maximumCharactersPerSecond = 20.0

    public static func tooFast(_ cues: [PlacedCue]) -> [PlacedCue.ID] {
        cues.filter { cue in
            let seconds = max(0.05, cue.range.duration.seconds)
            let characters = Double(cue.text.filter { !$0.isWhitespace }.count)
            return characters / seconds > maximumCharactersPerSecond
        }.map(\.id)
    }
}

extension Project {
    /// Where a cue sits: its own position, or the style's — kept inside the part of the frame no
    /// app covers, and moved off the face when the camera is following one.
    public func captionPosition(for cue: PlacedCue) -> CaptionPosition {
        var position = cue.position ?? captionStyle.position
        position.y = min(max(position.y, 0.08), 0.84)
        guard cue.position == nil, abs(position.y - 0.42) < 0.17, followsFace(during: cue.range) else {
            return position
        }
        position.y = 0.74
        return position
    }

    /// Whether the footage under a stretch of the video has a face being followed.
    func followsFace(during range: MediaTimeRange) -> Bool {
        var cursor = 0.0
        for segment in segments {
            let length = segment.barWeight
            defer { cursor += length }
            guard cursor < range.end.seconds, cursor + length > range.start.seconds,
                  let take = segment.selectedTake,
                  let points = recording(id: take.recordingID)?.reframe, !points.isEmpty
            else { continue }
            let from = take.sourceRange.start.seconds
            let to = take.sourceRange.end.seconds
            if points.contains(where: { $0.time >= from && $0.time <= to }) { return true }
        }
        return false
    }
}
