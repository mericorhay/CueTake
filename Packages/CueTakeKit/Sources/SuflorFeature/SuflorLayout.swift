import CoreGraphics
import CoreText
import Domain
import Foundation
import UIKit

/// The faces the prompter draws with, made on the main actor where the design system's fonts are
/// registered and handed to the drawing code, which runs off it.
nonisolated struct SuflorFonts: @unchecked Sendable {
    var body: CTFont
    var label: CTFont
    var chrome: CTFont
    var chromeBold: CTFont
    var display: CTFont
}

/// The cards laid out once as lines at a fixed width, so the stage on the phone and the floating
/// window draw exactly the same text in exactly the same place — one scaled, one small.
///
/// Positions are in points from the top of the first line: the prompter's offset is the point of
/// the text sitting on the reading line.
nonisolated final class SuflorLayout: @unchecked Sendable {
    nonisolated struct Line {
        let line: CTLine
        /// Baseline, from the top of the text.
        let baseline: CGFloat
        let ascent: CGFloat
        let descent: CGFloat
        let cue: Int
        let isLabel: Bool
        let role: SuflorCue.Role

        var center: CGFloat { baseline - (ascent - descent) / 2 }
    }

    /// The width everything is drawn at. The floating window is 360 wide at 2x; the stage scales it.
    static let width: CGFloat = 360
    static let inset: CGFloat = 26

    let lines: [Line]
    /// Each card's label line, where a skip lands.
    let cueStarts: [CGFloat]
    /// The top of the ad section, where the flow waits for the minute; nil without an ad.
    let adTop: CGFloat?
    /// The last line of the ad section.
    let adBottom: CGFloat?
    /// Where the last line sits on the reading line.
    let end: CGFloat
    let pointsPerWord: Double
    let fontSize: CGFloat
    let roles: [SuflorCue.Role]

    init(cues: [SuflorCue], fontSize: CGFloat, fonts: SuflorFonts, labels: [SuflorCue.Role: String], highlights: [String]) {
        self.fontSize = fontSize
        roles = cues.map(\.role)
        var lines: [Line] = []
        var starts: [CGFloat] = []
        var cursor: CGFloat = 0
        let textWidth = Self.width - Self.inset * 2
        let words = max(1, cues.reduce(0) { $0 + $1.text.split(whereSeparator: \.isWhitespace).count })

        for (index, cue) in cues.enumerated() {
            // The card's label: small, spaced, in the role's colour.
            let label = NSAttributedString(string: (labels[cue.role] ?? cue.role.rawValue).uppercased(), attributes: [
                .font: fonts.label,
                .kern: 1.6,
                Self.ink: Self.color(for: cue.role),
            ])
            let labelLine = CTLineCreateWithAttributedString(label)
            var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
            CTLineGetTypographicBounds(labelLine, &ascent, &descent, &leading)
            starts.append(cursor)
            lines.append(Line(line: labelLine, baseline: cursor + ascent, ascent: ascent, descent: descent, cue: index, isLabel: true, role: cue.role))
            cursor += ascent + descent + fontSize * 0.34

            let text = Self.attributed(cue.text, role: cue.role, font: fonts.body, highlights: highlights)
            let setter = CTFramesetterCreateWithAttributedString(text)
            let tall: CGFloat = 20_000
            let frame = CTFramesetterCreateFrame(setter, CFRange(location: 0, length: 0), CGPath(rect: CGRect(x: 0, y: 0, width: textWidth, height: tall), transform: nil), nil)
            let frameLines = CTFrameGetLines(frame) as? [CTLine] ?? []
            var origins = [CGPoint](repeating: .zero, count: frameLines.count)
            CTFrameGetLineOrigins(frame, CFRange(location: 0, length: 0), &origins)
            var bottom = cursor
            for (line, origin) in zip(frameLines, origins) {
                CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
                let baseline = cursor + (tall - origin.y)
                lines.append(Line(line: line, baseline: baseline, ascent: ascent, descent: descent, cue: index, isLabel: false, role: cue.role))
                bottom = baseline + descent
            }
            cursor = bottom + fontSize * 1.05
        }

        // The first line of text, not the first label, starts on the reading line.
        let firstText = lines.first { !$0.isLabel }?.center ?? 0
        let placed = lines.map {
            Line(line: $0.line, baseline: $0.baseline - firstText, ascent: $0.ascent, descent: $0.descent, cue: $0.cue, isLabel: $0.isLabel, role: $0.role)
        }
        let shiftedStarts = starts.map { $0 - firstText }
        let lastText = placed.last { !$0.isLabel }?.center ?? 0
        let finish = max(1, lastText)
        let firstAd = cues.firstIndex { $0.role.isAd }
        let lastAd = cues.lastIndex { $0.role.isAd }
        let size = fontSize
        self.lines = placed
        cueStarts = shiftedStarts
        end = finish
        adTop = firstAd.map { max(0, shiftedStarts[$0] - size * 0.6) }
        adBottom = lastAd.flatMap { index in placed.last { $0.cue == index }?.center }
        pointsPerWord = Double(finish) / Double(words)
    }

    /// Scroll speed for a reading pace.
    func speed(wordsPerMinute: Double) -> Double { wordsPerMinute / 60 * pointsPerWord }

    /// The card on the reading line.
    func cue(at offset: CGFloat) -> Int {
        max(0, (cueStarts.lastIndex { $0 <= offset + fontSize * 0.8 }) ?? 0)
    }

    /// Where to land for the card before or after the one being read: its first line of text on
    /// the reading line. Back from the middle of a card returns to its start first.
    func skip(from offset: CGFloat, forward: Bool) -> CGFloat {
        guard !cueStarts.isEmpty else { return offset }
        let current = cue(at: offset)
        if forward {
            return current + 1 < cueStarts.count ? firstLine(of: current + 1) : end
        }
        let start = firstLine(of: current)
        if offset > start + fontSize { return start }
        return firstLine(of: max(0, current - 1))
    }

    private func firstLine(of cue: Int) -> CGFloat {
        lines.first { $0.cue == cue && !$0.isLabel }?.center ?? cueStarts[cue]
    }

    /// The same position in another layout of the same cards: same card, same share of it.
    func position(_ offset: CGFloat, in other: SuflorLayout) -> CGFloat {
        guard !cueStarts.isEmpty, cueStarts.count == other.cueStarts.count else { return 0 }
        let index = cue(at: offset)
        let start = cueStarts[index]
        let next = index + 1 < cueStarts.count ? cueStarts[index + 1] : end
        let share = next > start ? (offset - start) / (next - start) : 0
        let otherStart = other.cueStarts[index]
        let otherNext = index + 1 < other.cueStarts.count ? other.cueStarts[index + 1] : other.end
        return otherStart + share * (otherNext - otherStart)
    }

    /// Core Text's own colour key, which takes a CGColor; UIKit's takes a UIColor.
    static let ink = NSAttributedString.Key(kCTForegroundColorAttributeName as String)

    static func color(for role: SuflorCue.Role) -> CGColor {
        switch role {
        case .opening: SuflorInk.warm
        case .topic: SuflorInk.lime
        case .bridge: SuflorInk.warm
        case .ad: SuflorInk.accent
        case .cta: SuflorInk.accent
        case .rescue: SuflorInk.white(0.6)
        case .closing: SuflorInk.lime
        }
    }

    /// The words, with anything the brand insists on marked in lime so the eye finds the code.
    private static func attributed(_ text: String, role: SuflorCue.Role, font: CTFont, highlights: [String]) -> NSAttributedString {
        let string = NSMutableAttributedString(string: text, attributes: [
            .font: font,
            Self.ink: role == .rescue ? SuflorInk.white(0.78) : SuflorInk.white(1),
        ])
        let whole = text as NSString
        for item in highlights where !item.trimmingCharacters(in: .whitespaces).isEmpty {
            var search = NSRange(location: 0, length: whole.length)
            while true {
                let found = whole.range(of: item, options: [.caseInsensitive, .diacriticInsensitive], range: search)
                guard found.location != NSNotFound else { break }
                string.addAttribute(Self.ink, value: SuflorInk.lime, range: found)
                let next = found.location + found.length
                search = NSRange(location: next, length: whole.length - next)
            }
        }
        return string
    }
}

/// The design's colours as Core Graphics colours, for drawing off the main actor.
nonisolated enum SuflorInk {
    static let screen = CGColor(srgbRed: 11 / 255, green: 11 / 255, blue: 13 / 255, alpha: 1)
    static let surface = CGColor(srgbRed: 19 / 255, green: 19 / 255, blue: 23 / 255, alpha: 1)
    static let accent = CGColor(srgbRed: 1, green: 90 / 255, blue: 79 / 255, alpha: 1)
    static let warm = CGColor(srgbRed: 1, green: 112 / 255, blue: 67 / 255, alpha: 1)
    static let lime = CGColor(srgbRed: 232 / 255, green: 1, blue: 79 / 255, alpha: 1)
    static let amber = CGColor(srgbRed: 1, green: 184 / 255, blue: 64 / 255, alpha: 1)
    static func white(_ alpha: CGFloat) -> CGColor { CGColor(srgbRed: 245 / 255, green: 245 / 255, blue: 247 / 255, alpha: alpha) }
    static func accent(_ alpha: CGFloat) -> CGColor { accent.copy(alpha: alpha) ?? accent }
    static func amber(_ alpha: CGFloat) -> CGColor { amber.copy(alpha: alpha) ?? amber }
    static func lime(_ alpha: CGFloat) -> CGColor { lime.copy(alpha: alpha) ?? lime }
}
