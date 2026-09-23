import DesignSystem
import Domain
import SwiftUI

/// The six styles, each a finished look in one tap. A style runs many tools at once — cleanup,
/// captions, colour, camera, titles, sound — so the card says what the video will feel like, not
/// which tools run. Everything it does is one undo step.
struct StyleSheet: View {
    @Bindable var model: EditorModel
    let onClose: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    DSKicker(AppLocalization.string("editor.style.kicker", bundle: .module))
                    Text("editor.style.title", bundle: .module)
                        .dsFont(.archivo, .bold, 22)
                        .foregroundStyle(DS.Palette.ink)
                    Text("editor.style.note", bundle: .module)
                        .dsFont(.sans, .regular, 12, lineHeight: 1.35)
                        .foregroundStyle(DS.Palette.ink(0.58))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(DS.Palette.ink(0.6))
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(DS.Palette.hairline(0.08)))
                }
                .buttonStyle(.dsPressIcon)
                .accessibilityLabel(Text("editor.panel.close", bundle: .module))
                .disabled(model.applyingStyle != nil)
            }
            .padding(.horizontal, 20)
            .padding(.top, 22)
            .padding(.bottom, 16)

            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    ForEach(Array(VideoStyle.allCases.enumerated()), id: \.element) { order, style in
                        card(style)
                            .opacity(shown ? 1 : 0)
                            .offset(y: shown ? 0 : 14)
                            .animation(reduceMotion ? nil : DS.Motion.settle.delay(Double(order) * 0.04), value: shown)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
            .scrollIndicators(.hidden)
        }
        .background(DS.Palette.screen)
        .interactiveDismissDisabled(model.applyingStyle != nil)
        .onAppear { shown = true }
    }

    private func card(_ style: VideoStyle) -> some View {
        let running = model.applyingStyle == style
        let busy = model.applyingStyle != nil
        return Button {
            guard !busy, let apply = model.styleApplier else { return }
            model.pause()
            Task {
                await apply(style)
                onClose()
            }
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                preview(style, running: running)
                    .frame(height: 118)
                    .clipShape(UnevenRoundedRectangle(topLeadingRadius: 18, topTrailingRadius: 18, style: .continuous))

                VStack(alignment: .leading, spacing: 5) {
                    Text(AppLocalization.string(String.LocalizationValue(stringLiteral: "style." + style.rawValue), bundle: .module))
                        .dsFont(.archivo, .bold, 15)
                        .foregroundStyle(DS.Palette.ink)
                    Text(AppLocalization.string(String.LocalizationValue(stringLiteral: "style." + style.rawValue + ".note"), bundle: .module))
                        .dsFont(.sans, .regular, 11, lineHeight: 1.3)
                        .foregroundStyle(DS.Palette.ink(0.6))
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(12)
                .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
            }
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(DS.Palette.hairline(0.05)))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(running ? DS.Palette.lime : DS.Palette.hairline(0.08), lineWidth: running ? 2 : 1)
            }
            .opacity(busy && !running ? 0.45 : 1)
        }
        .buttonStyle(.dsPress(radius: 18))
        .disabled(busy)
        .animation(DS.Motion.snap, value: busy)
    }

    /// A caption as the style would draw it, on the style's own colours.
    private func preview(_ style: VideoStyle, running: Bool) -> some View {
        let (top, bottom) = style.swatch
        let loud = style == .boldBusiness || style == .energetic || style == .ugcAd
        return ZStack {
            LinearGradient(colors: [Self.color(top), Self.color(bottom)], startPoint: .topLeading, endPoint: .bottomTrailing)

            if running {
                VStack(spacing: 8) {
                    ProgressView(value: model.styleProgress)
                        .tint(.white)
                        .frame(width: 96)
                    Text("editor.style.applying", bundle: .module)
                        .dsFont(.mono, .medium, 10)
                        .foregroundStyle(.white)
                }
                .transition(.opacity)
            } else {
                HStack(spacing: 5) {
                    Text("editor.style.sampleA", bundle: .module)
                        .foregroundStyle(.white)
                    Text("editor.style.sampleB", bundle: .module)
                        .foregroundStyle(loud ? Self.color(style == .boldBusiness ? "#FFD400" : top) : .white.opacity(0.85))
                }
                .font(.system(size: loud ? 19 : 14, weight: loud ? .black : .medium))
                .textCase(loud ? .uppercase : nil)
                .shadow(color: .black.opacity(0.45), radius: 3, y: 1)
                .padding(.horizontal, 10)
                .padding(.vertical, loud ? 0 : 5)
                .background {
                    if style == .podcast || style == .minimal {
                        Capsule().fill(.black.opacity(0.35))
                    }
                }
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .frame(maxHeight: .infinity, alignment: style.captionPosition == "middle" ? .center : .bottom)
                .padding(.bottom, style.captionPosition == "middle" ? 0 : 14)
            }
        }
    }

    static func color(_ hex: String) -> Color {
        let digits = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let value = UInt32(digits, radix: 16) ?? 0
        return Color(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}
