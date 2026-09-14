import DesignSystem
import Domain
import SwiftUI

/// Where you tell the AI what to do with the video.
///
/// It does not show a plan to approve any more. The panel folds away as soon as you send, the AI
/// takes the studio and makes its changes in front of you — each one lighting up where it lands —
/// and every one of them is listed and reversible in AI changes. Watching it happen is the review.
struct AIEditPanel: View {
    @Bindable var model: EditorModel
    let request: AIRequester
    /// Folds the panel so the studio is in view while the AI works.
    let onStart: () -> Void
    let onShowChanges: () -> Void

    @State private var instruction = ""
    @FocusState private var focused: Bool

    private var suggestions: [String] {
        [
            String(localized: "editor.ai.suggest.tighten", bundle: .module),
            String(localized: "editor.ai.suggest.captions", bundle: .module),
            String(localized: "editor.ai.suggest.hook", bundle: .module),
            String(localized: "editor.ai.suggest.title", bundle: .module),
            String(localized: "editor.ai.suggest.look", bundle: .module),
            String(localized: "editor.ai.suggest.energy", bundle: .module),
        ]
    }

    private var canSend: Bool {
        !instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !model.isAIDriving
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("editor.ai.drives", bundle: .module)
                .dsFont(.sans, .regular, 11, lineHeight: 1.35)
                .foregroundStyle(DS.Palette.ink(0.5))

            HStack(spacing: 8) {
                TextField(String(localized: "editor.ai.placeholder", bundle: .module), text: $instruction, axis: .vertical)
                    .lineLimit(1...4)
                    .dsFont(.sans, .regular, 14)
                    .foregroundStyle(DS.Palette.ink)
                    .tint(AIPalette.blue)
                    .focused($focused)
                    .submitLabel(.send)
                    .onSubmit(send)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(DS.Palette.hairline(0.07)))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(AIPalette.blue.opacity(focused ? 0.7 : 0), lineWidth: 1)
                    }

                Button(action: send) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(canSend ? Color.white : DS.Palette.ink(0.35))
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(canSend ? AIPalette.blue : DS.Palette.hairline(0.1)))
                        .animation(.easeOut(duration: 0.15), value: canSend)
                }
                .buttonStyle(.dsPressIcon)
                .disabled(!canSend)
            }

            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(suggestions, id: \.self) { suggestion in
                        Button {
                            // Fills the field rather than sending: a second tap on the AI button used
                            // to land on a suggestion as the panel opened and start an edit nobody asked for.
                            instruction = suggestion
                            focused = true
                        } label: {
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
                .padding(.vertical, 1)
            }
            .scrollIndicators(.hidden)
            .scrollClipDisabled()

            if !model.aiChanges.isEmpty {
                Button(action: onShowChanges) {
                    HStack(spacing: 8) {
                        AISparkle(size: 11)
                        Text("editor.ai.history", bundle: .module)
                            .dsFont(.sans, .semibold, 12)
                            .foregroundStyle(DS.Palette.ink(0.9))
                        Text(verbatim: "\(model.aiChanges.reduce(0) { $0 + $1.activeCount })")
                            .dsFont(.mono, .medium, 10)
                            .foregroundStyle(DS.Palette.inkInverse)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(AIPalette.blue))
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(DS.Palette.ink(0.4))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(DS.Palette.hairline(0.05)))
                }
                .buttonStyle(.dsPress(radius: 12))
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
    }

    private func send() {
        guard canSend else { return }
        let text = instruction
        focused = false
        instruction = ""
        onStart()
        model.askAI(text, using: request)
    }
}
