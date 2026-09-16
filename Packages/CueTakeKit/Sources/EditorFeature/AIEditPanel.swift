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
    /// What is being written to the AI. Kept by the editor: typing happens in the bar at the top.
    @Binding var draft: String
    /// Opens the writing bar at the top of the screen, above the keyboard's reach.
    let onCompose: () -> Void
    /// Folds the panel so the studio is in view while the AI works.
    let onStart: () -> Void
    let onShowChanges: () -> Void

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

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !model.isAIDriving
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("editor.ai.drives", bundle: .module)
                .dsFont(.sans, .regular, 11, lineHeight: 1.35)
                .foregroundStyle(DS.Palette.ink(0.5))

            HStack(spacing: 8) {
                // Looks like the field; typing happens at the top of the screen, where the
                // keyboard cannot cover it.
                Button(action: onCompose) {
                    Text(verbatim: draft.isEmpty ? String(localized: "editor.ai.placeholder", bundle: .module) : draft)
                        .dsFont(.sans, .regular, 14)
                        .foregroundStyle(draft.isEmpty ? DS.Palette.ink(0.4) : DS.Palette.ink)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 12)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(DS.Palette.hairline(0.07)))
                }
                .buttonStyle(.dsPress(radius: 14))

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
                    ForEach(Self.suggestions, id: \.self) { suggestion in
                        Button {
                            // Fills the field rather than sending: a second tap on the AI button used
                            // to land on a suggestion as the panel opened and start an edit nobody asked for.
                            draft = suggestion
                            onCompose()
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
        let text = draft
        draft = ""
        onStart()
        model.askAI(text, using: request)
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
