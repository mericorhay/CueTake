import Domain
import SwiftUI

/// The caption on screen right now, drawn over the editor's preview.
///
/// A second implementation of something the exporter already does, which is normally a smell and
/// here is unavoidable: the export burns captions in with Core Animation's layer tool, and
/// `AVPlayer` does not run that tool. The choice is between drawing them again in SwiftUI and
/// having an editor that cannot show you the thing you are editing.
///
/// So the rule is that both sides read the same numbers — `Project.captionCues` places them, and
/// `CaptionStyle` sizes and colours them — and neither invents its own idea of where a cue starts.
struct CaptionOverlay: View {
    let cue: PlacedCue
    let style: CaptionStyle
    let locale: Locale
    /// The playhead, for lighting words as they are said.
    let time: Double
    /// Moves when the AI changes these captions or their look.
    var glowToken: Int = 0

    var body: some View {
        GeometryReader { proxy in
            let size = max(11, proxy.size.height * style.relativeFontSize)

            line(size: size)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                // SwiftUI has no text stroke, and short video is watched over whatever happens to
                // be behind the words. Four offset shadows is the cheap version of an outline and
                // survives white footage, which a single drop shadow does not. A plate does that
                // job by itself, so plated styles skip it.
                .modifier(Outline(enabled: style.backgroundColor == nil, weight: max(0.8, size * 0.06)))
                .padding(.horizontal, style.backgroundColor == nil ? size * 0.3 : size * 0.55)
                .padding(.vertical, style.backgroundColor == nil ? size * 0.2 : size * 0.28)
                .background {
                    if let background = style.backgroundColor {
                        RoundedRectangle(cornerRadius: size * 0.32, style: .continuous)
                            .fill(Self.color(background))
                    }
                }
                .aiGlow(glowToken, in: RoundedRectangle(cornerRadius: max(6, size * 0.32), style: .continuous), inset: 4)
                .frame(maxWidth: proxy.size.width * 0.86)
                .position(
                    x: proxy.size.width * style.position.x,
                    y: proxy.size.height * style.position.y
                )
        }
        .allowsHitTesting(false)
    }

    /// The line itself. With karaoke the words are assembled one by one, each coloured by whether
    /// it has been said yet; otherwise it is the cue's text as written.
    private func line(size: CGFloat) -> Text {
        let font = style.fontName.map { Font.custom($0, fixedSize: size) }
            ?? .system(size: size, weight: .heavy)
        let base = Self.color(style.textColor)

        guard style.highlightsWords, let highlight = style.highlightColor, !cue.words.isEmpty else {
            return Text(style.textCase.apply(to: cue.text, locale: locale))
                .font(font)
                .foregroundStyle(base)
        }

        let lit = cue.wordIndex(at: time) ?? -1
        return cue.words.enumerated().reduce(Text(verbatim: "")) { line, item in
            let (index, word) = item
            let piece = Text(verbatim: (index == 0 ? "" : " ") + style.textCase.apply(to: word.text, locale: locale))
                .font(font)
                .foregroundStyle(index <= lit ? Self.color(highlight) : base)
            return line + piece
        }
    }

    static func color(_ color: RGBAColor) -> Color {
        Color(
            .sRGB,
            red: color.red,
            green: color.green,
            blue: color.blue,
            opacity: color.alpha
        )
    }

    /// How each style arrives. Pop pops, the others fade — the entrance is part of the look.
    static func transition(for style: CaptionStyle) -> AnyTransition {
        style.presetID == "pop" || style.presetID == "bold" || style.presetID == "story"
            ? .scale(scale: 0.82).combined(with: .opacity)
            : .opacity
    }
}

private struct Outline: ViewModifier {
    let enabled: Bool
    let weight: CGFloat

    func body(content: Content) -> some View {
        if enabled {
            content
                .shadow(color: .black.opacity(0.95), radius: 0.4, x: weight, y: 0)
                .shadow(color: .black.opacity(0.95), radius: 0.4, x: -weight, y: 0)
                .shadow(color: .black.opacity(0.95), radius: 0.4, x: 0, y: weight)
                .shadow(color: .black.opacity(0.95), radius: 0.4, x: 0, y: -weight)
                .shadow(color: .black.opacity(0.5), radius: 4, y: 2)
        } else {
            content
        }
    }
}
