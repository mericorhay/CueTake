import DesignSystem
import Domain
import SwiftUI

/// Where you tell the AI what to do with the video.
///
/// It does not show a plan to approve any more. The panel folds away as soon as you send, the AI
/// takes the studio and makes its changes in front of you — each one lighting up where it lands —
/// and every one of them is listed and reversible in AI changes. Watching it happen is the review.
/// Starting points for a request, shared by the composer and the prompt bar.
enum AIEditPanel {
    static var suggestions: [String] {
        [
            String(localized: "editor.ai.suggest.tighten", bundle: .module),
            String(localized: "editor.ai.suggest.captions", bundle: .module),
            String(localized: "editor.ai.suggest.structure", bundle: .module),
            String(localized: "editor.ai.suggest.hook", bundle: .module),
            String(localized: "editor.ai.suggest.title", bundle: .module),
            String(localized: "editor.ai.suggest.look", bundle: .module),
            String(localized: "editor.ai.suggest.energy", bundle: .module),
            String(localized: "editor.ai.suggest.camera", bundle: .module),
        ]
    }
}

/// Writing to the AI, at the top of the screen. The panel it opens from sits where the keyboard
/// comes up; here the words stay in view, and sending closes it.
struct AIPromptBar: View {
    @Binding var text: String
    var title: LocalizedStringKey = "editor.ai.compose"
    var placeholder: String = String(localized: "editor.ai.placeholder", bundle: .module)
    var suggestions: [String] = AIEditPanel.suggestions
    var sendSymbol = "arrow.up"
    var tint: Color = AIPalette.blue
    let onSend: () -> Void
    let onCancel: () -> Void

    @FocusState private var focused: Bool

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                AISparkle(size: 12)
                Text(title, bundle: .module)
                    .dsFont(.sans, .semibold, 12)
                    .foregroundStyle(DS.Palette.ink(0.7))
                Spacer(minLength: 0)
                Button(action: onCancel) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(DS.Palette.ink(0.7))
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(DS.Palette.hairline(0.08)))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.dsPressIcon)
                .accessibilityLabel(Text("editor.panel.close", bundle: .module))
            }

            HStack(alignment: .bottom, spacing: 8) {
                TextField(placeholder, text: $text, axis: .vertical)
                    .lineLimit(1...5)
                    .dsFont(.sans, .regular, 15)
                    .foregroundStyle(DS.Palette.ink)
                    .tint(tint)
                    .focused($focused)
                    .submitLabel(.send)
                    .onSubmit { if canSend { onSend() } }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 11)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(DS.Palette.hairline(0.08)))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(tint.opacity(0.6), lineWidth: 1)
                    }

                Button(action: onSend) {
                    Image(systemName: sendSymbol)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(canSend ? Color.white : DS.Palette.ink(0.35))
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(canSend ? tint : DS.Palette.hairline(0.1)))
                }
                .buttonStyle(.dsPressIcon)
                .disabled(!canSend)
            }

            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(suggestions, id: \.self) { suggestion in
                        Button { text = suggestion } label: {
                            Text(suggestion)
                                .dsFont(.sans, .medium, 11)
                                .foregroundStyle(DS.Palette.ink(0.9))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(Capsule().fill(DS.Palette.hairline(0.07)))
                        }
                        .buttonStyle(.dsPress(radius: 20))
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 14)
        .padding(.top, 6)
        .background {
            UnevenRoundedRectangle(bottomLeadingRadius: DS.Radius.sheet, bottomTrailingRadius: DS.Radius.sheet, style: .continuous)
                .fill(DS.Palette.glassSheet(0.98))
                .ignoresSafeArea(edges: .top)
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(tint.opacity(0.35)).frame(height: 1)
        }
        .onAppear { focused = true }
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}
