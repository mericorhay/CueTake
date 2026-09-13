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

    var body: some View {
        GeometryReader { proxy in
            let size = max(11, proxy.size.height * style.relativeFontSize)
            let text = style.textCase.apply(to: cue.text, locale: locale)

            Text(text)
                .font(.system(size: size, weight: .heavy))
                .foregroundStyle(Self.color(style.textColor))
                .multilineTextAlignment(.center)
                .lineLimit(3)
                // SwiftUI has no text stroke, and short video is watched over whatever happens to
                // be behind the words. Four offset shadows is the cheap version of an outline and
                // survives white footage, which a single drop shadow does not.
                .shadow(color: .black.opacity(0.9), radius: 0.6, x: 1, y: 0)
                .shadow(color: .black.opacity(0.9), radius: 0.6, x: -1, y: 0)
                .shadow(color: .black.opacity(0.9), radius: 0.6, x: 0, y: 1)
                .shadow(color: .black.opacity(0.9), radius: 0.6, x: 0, y: -1)
                .shadow(color: .black.opacity(0.5), radius: 4, y: 2)
                .padding(.horizontal, size * 0.5)
                .padding(.vertical, size * 0.22)
                .background {
                    if let background = style.backgroundColor {
                        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                            .fill(Self.color(background))
                    }
                }
                .frame(maxWidth: proxy.size.width * 0.86)
                .position(
                    x: proxy.size.width * style.position.x,
                    y: proxy.size.height * style.position.y
                )
        }
        .allowsHitTesting(false)
        .transition(.opacity)
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
}
