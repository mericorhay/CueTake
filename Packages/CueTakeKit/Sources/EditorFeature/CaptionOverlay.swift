import DesignSystem
import Domain
import SwiftUI

/// The caption on screen right now, drawn over the editor's preview.
///
/// A second implementation of something the exporter already does, which is normally a smell and
/// here is unavoidable: the export burns captions in with Core Animation's layer tool, and
/// `AVPlayer` does not run that tool. The choice is between drawing them again in SwiftUI and
/// having an editor that cannot show you the thing you are editing.
///
/// So both sides read the same numbers: `Project.captionCues` places the cues, `CaptionWords`
/// decides what each word says, `CaptionLineBreaker` breaks the lines and `CaptionAnimator` moves
/// every word. Neither side invents its own.
struct CaptionOverlay: View {
    let cue: PlacedCue
    let style: CaptionStyle
    let locale: Locale
    /// The playhead, for lighting and moving words as they are said.
    let time: Double
    /// Where the cue sits. Nil uses the style's place.
    var position: CaptionPosition? = nil
    /// Moves when the AI changes these captions or their look.
    var glowToken: Int = 0
    /// Set in the editor: the caption can be tapped to edit and dragged up or down.
    var isEditing: Bool = false
    var onTap: (() -> Void)? = nil
    /// The new height of the caption, 0 top … 1 bottom, while it is dragged.
    var onMove: ((Double) -> Void)? = nil

    @State private var dragging = false

    var body: some View {
        GeometryReader { proxy in
            let size = max(11, proxy.size.height * style.relativeFontSize)
            let place = position ?? style.position
            let display = CaptionWords(cue: cue, style: style, locale: locale)
            let frame = CaptionAnimator.frame(for: cue, wordCount: display.words.count, style: style, at: time)
            let plated = style.backgroundColor != nil

            CaptionFlow(spacing: CGFloat(style.wordSpacing(fontSize: Double(size))), lineSpacing: CGFloat(style.lineSpacing(fontSize: Double(size)))) {
                ForEach(Array(display.words.enumerated()), id: \.offset) { index, word in
                    wordView(word, index: index, display: display, frame: frame, size: size)
                }
            }
            .padding(.horizontal, plated ? size * 0.55 : size * 0.3)
            .padding(.vertical, plated ? size * 0.28 : size * 0.2)
            .background {
                if let background = style.backgroundColor {
                    RoundedRectangle(cornerRadius: size * 0.32, style: .continuous)
                        .fill(Self.color(background))
                }
            }
            .scaleEffect(frame.scale)
            .offset(y: frame.offset * size)
            .opacity(frame.opacity)
            .aiGlow(glowToken, in: RoundedRectangle(cornerRadius: max(6, size * 0.32), style: .continuous), inset: 4)
            .overlay {
                if isEditing {
                    RoundedRectangle(cornerRadius: max(6, size * 0.32), style: .continuous)
                        .strokeBorder(DS.Palette.lime, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                        .padding(-6)
                        .allowsHitTesting(false)
                }
            }
            .scaleEffect(dragging ? 1.04 : 1)
            .animation(DS.Motion.snap, value: dragging)
            .contentShape(Rectangle().inset(by: -10))
            .onTapGesture { onTap?() }
            .gesture(
                DragGesture(minimumDistance: 4, coordinateSpace: .named("captionFrame"))
                    .onChanged { value in
                        dragging = true
                        onMove?(Double(value.location.y / max(1, proxy.size.height)))
                    }
                    .onEnded { _ in dragging = false },
                including: isEditing ? .all : .none
            )
            .frame(maxWidth: proxy.size.width * 0.86)
            .position(x: proxy.size.width * place.x, y: proxy.size.height * place.y)
            // The height the caption sits at, while it is moved.
            .overlay(alignment: .topLeading) {
                if dragging {
                    Rectangle()
                        .fill(DS.Palette.lime.opacity(0.7))
                        .frame(width: proxy.size.width, height: 1)
                        .offset(y: proxy.size.height * place.y)
                        .allowsHitTesting(false)
                }
            }
        }
        .coordinateSpace(.named("captionFrame"))
        .allowsHitTesting(onTap != nil)
    }

    private func wordView(_ word: String, index: Int, display: CaptionWords, frame: CaptionFrame, size: CGFloat) -> some View {
        let state = index < frame.words.count ? frame.words[index] : CaptionFrame.Word()
        let font = style.fontName.map { Font.custom($0, fixedSize: size) } ?? .system(size: size, weight: .heavy)
        let emphasis = style.resolvedEmphasis
        let lit: Bool = switch emphasis {
        case .color: state.isLit
        case .box: state.box > 0.5
        case .scale: state.isActive && style.highlightColor != nil
        case .none: false
        }
        let base = display.keywords.contains(index) ? (style.keywordColor ?? style.textColor) : style.textColor
        let colour: RGBAColor = lit ? (emphasis == .box ? style.boxedTextColor : style.emphasisColor) : base
        let outlined = style.resolvedStrokeWeight > 0.001 && !(emphasis == .box && lit)

        return Text(verbatim: word)
            .font(font)
            .foregroundStyle(Self.color(colour))
            .fixedSize()
            .modifier(Outline(
                enabled: outlined,
                weight: max(0.8, size * style.resolvedStrokeWeight * 0.45),
                color: Self.color(style.resolvedStrokeColor)
            ))
            .shadow(color: .black.opacity(style.shadow == true ? 0.55 : 0), radius: size * 0.1, y: size * 0.04)
            .padding(.horizontal, emphasis == .box ? size * 0.12 : 0)
            .background {
                if emphasis == .box {
                    RoundedRectangle(cornerRadius: size * 0.18, style: .continuous)
                        .fill(Self.color(style.emphasisColor))
                        .opacity(state.box)
                }
            }
            .scaleEffect(state.scale)
            .offset(y: state.offset * size)
            .opacity(state.opacity)
    }

    static func color(_ color: RGBAColor) -> Color {
        Color(.sRGB, red: color.red, green: color.green, blue: color.blue, opacity: color.alpha)
    }

    /// The arrival and the exit are drawn by `CaptionAnimator`. A view transition on top of it kept
    /// the old caption fading out while the new one came in, two captions stacked on each other.
    static func transition(for style: CaptionStyle) -> AnyTransition {
        .identity
    }
}

/// Words in centred lines, broken the way the export breaks them.
struct CaptionFlow: Layout {
    var spacing: CGFloat
    var lineSpacing: CGFloat

    private func lines(_ sizes: [CGSize], maxWidth: CGFloat) -> [[Int]] {
        CaptionLineBreaker.lines(
            widths: sizes.map { Double($0.width) },
            space: Double(spacing),
            maxWidth: maxWidth.isFinite ? Double(maxWidth) : .greatestFiniteMagnitude
        )
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let maxWidth = proposal.width ?? .infinity
        let rows = lines(sizes, maxWidth: maxWidth)
        var width: CGFloat = 0
        var height: CGFloat = 0
        for (index, row) in rows.enumerated() {
            let rowWidth = row.map { sizes[$0].width }.reduce(0, +) + spacing * CGFloat(max(0, row.count - 1))
            width = max(width, rowWidth)
            height += (row.map { sizes[$0].height }.max() ?? 0) + (index > 0 ? lineSpacing : 0)
        }
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let rows = lines(sizes, maxWidth: bounds.width)
        var y = bounds.minY
        for row in rows {
            let rowWidth = row.map { sizes[$0].width }.reduce(0, +) + spacing * CGFloat(max(0, row.count - 1))
            let rowHeight = row.map { sizes[$0].height }.max() ?? 0
            var x = bounds.midX - rowWidth / 2
            for index in row {
                subviews[index].place(
                    at: CGPoint(x: x, y: y + (rowHeight - sizes[index].height) / 2),
                    proposal: ProposedViewSize(sizes[index])
                )
                x += sizes[index].width + spacing
            }
            y += rowHeight + lineSpacing
        }
    }
}

private struct Outline: ViewModifier {
    let enabled: Bool
    let weight: CGFloat
    var color: Color = .black

    func body(content: Content) -> some View {
        if enabled {
            // SwiftUI has no text stroke. Four offset shadows is the cheap version of an outline
            // and survives white footage, which a single drop shadow does not.
            content
                .shadow(color: color.opacity(0.95), radius: 0.4, x: weight, y: 0)
                .shadow(color: color.opacity(0.95), radius: 0.4, x: -weight, y: 0)
                .shadow(color: color.opacity(0.95), radius: 0.4, x: 0, y: weight)
                .shadow(color: color.opacity(0.95), radius: 0.4, x: 0, y: -weight)
        } else {
            content
        }
    }
}
