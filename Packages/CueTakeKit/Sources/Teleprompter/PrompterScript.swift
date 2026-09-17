import DesignSystem
import Domain
import SwiftUI

/// The script as the reader sees it: running text that keeps the word being read on one line of
/// the panel.
///
/// A prompter that only highlights is a page the reader has to scroll with their eyes; once the
/// place goes below the panel's edge the highlight is invisible and the reader is lost. Here the
/// text moves instead, so the eyes stay on the reading line, as close to the lens as the panel is.
public struct PrompterScript: View {
    private let words: [TeleprompterModel.WordStyle]
    private let activeIndex: Int?
    private let textSize: Double
    private let isCentered: Bool
    private let readingLine: Double
    private let isMirrored: Bool
    private let notes: String?
    private let upNext: String?
    private let lineColor: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        words: [TeleprompterModel.WordStyle],
        activeIndex: Int?,
        textSize: Double,
        isCentered: Bool = false,
        readingLine: Double = 0.3,
        isMirrored: Bool = false,
        notes: String? = nil,
        upNext: String? = nil,
        lineColor: Color = DS.Palette.accent
    ) {
        self.words = words
        self.activeIndex = activeIndex
        self.textSize = textSize
        self.isCentered = isCentered
        self.readingLine = readingLine
        self.isMirrored = isMirrored
        self.notes = notes
        self.upNext = upNext
        self.lineColor = lineColor
    }

    private var horizontal: HorizontalAlignment { isCentered ? .center : .leading }
    private var frameAlignment: Alignment { isCentered ? .center : .leading }

    public var body: some View {
        GeometryReader { proxy in
            let height = proxy.size.height
            ScrollViewReader { reader in
                ScrollView(.vertical) {
                    VStack(alignment: horizontal, spacing: 8) {
                        if let notes, !notes.isEmpty {
                            HStack(alignment: .firstTextBaseline, spacing: 5) {
                                Image(systemName: "note.text")
                                    .font(.system(size: max(9, textSize * 0.42), weight: .semibold))
                                Text(notes)
                                    .dsFont(.sans, .regular, max(10, textSize * 0.5), lineHeight: 1.3)
                                    .italic()
                            }
                            .foregroundStyle(DS.Palette.lime.opacity(0.8))
                            .frame(maxWidth: .infinity, alignment: frameAlignment)
                        }

                        FlowLayout(horizontalSpacing: 0, verticalSpacing: 0, alignment: horizontal) {
                            ForEach(words) { word in
                                Text(word.text + " ")
                                    .dsFont(.sans, word.isEmphasized ? .bold : .medium, textSize, lineHeight: 1.45)
                                    .underline(word.isEmphasized, color: word.color.opacity(0.5))
                                    .foregroundStyle(word.color)
                                    .padding(.horizontal, 2)
                                    .background(
                                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                                            .fill(word.background)
                                    )
                                    .opacity(word.opacity)
                                    // The word under the voice is the one thing the eye tracks
                                    // continuously, so it is the one thing allowed to move.
                                    .scaleEffect(word.isActive && !reduceMotion ? 1.07 : 1)
                                    .animation(DS.Easing.ease(0.22), value: word.color)
                                    .animation(DS.Easing.ease(0.22), value: word.opacity)
                                    .animation(DS.Motion.bloom, value: word.isActive)
                                    .id(word.id)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: frameAlignment)

                        if let upNext, !upNext.isEmpty {
                            Text(upNext)
                                .dsFont(.sans, .regular, max(11, textSize - 6), lineHeight: 1.4)
                                .foregroundStyle(DS.Palette.ink(0.26))
                                .multilineTextAlignment(isCentered ? .center : .leading)
                                .frame(maxWidth: .infinity, alignment: frameAlignment)
                        }
                    }
                    // Room under the last line, so the end of the script can reach the reading
                    // line too instead of stopping at the bottom edge.
                    .padding(.bottom, height * (1 - readingLine))
                }
                .scrollIndicators(.hidden)
                .onChange(of: activeIndex) { _, index in
                    guard let index else { return }
                    let anchor = UnitPoint(x: 0.5, y: readingLine)
                    if reduceMotion {
                        reader.scrollTo(index, anchor: anchor)
                    } else {
                        withAnimation(.easeInOut(duration: 0.38)) {
                            reader.scrollTo(index, anchor: anchor)
                        }
                    }
                }
                .onAppear {
                    if let activeIndex {
                        reader.scrollTo(activeIndex, anchor: UnitPoint(x: 0.5, y: readingLine))
                    }
                }
            }
            .overlay(alignment: .topLeading) {
                // Where to look: a short tick at the reading line, only once there is a place.
                if activeIndex != nil {
                    Capsule()
                        .fill(lineColor.opacity(0.85))
                        .frame(width: 3, height: textSize * 0.9)
                        .offset(x: -9, y: height * readingLine - textSize * 0.45)
                        .transition(.opacity)
                }
            }
        }
        .scaleEffect(x: isMirrored ? -1 : 1, y: 1)
        .mask(
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black, location: 0.06),
                    .init(color: .black, location: 0.8),
                    .init(color: .clear, location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }
}
