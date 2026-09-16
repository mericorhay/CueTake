import DesignSystem
import Domain
import SwiftUI

/// Telling the AI what to do: one card in the middle of the screen, above the keyboard.
///
/// It replaces the panel in the tool dock and the bar at the top — two places for one sentence.
/// The card carries the session the AI is in, the last thing it did, and the way to every change
/// it made.
struct AIComposer: View {
    @Bindable var model: EditorModel
    @Binding var text: String
    /// Nil when cloud AI is off or not in this build.
    let request: AIRequester?
    let onAllowCloudAI: (() -> Void)?
    let onShowChanges: () -> Void
    let onClose: () -> Void

    @FocusState private var focused: Bool
    @State private var shown = false
    @State private var sessionPulse = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var canSend: Bool {
        request != nil && !model.isAIDriving && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var changeCount: Int { model.aiChanges.reduce(0) { $0 + $1.activeCount } }

    var body: some View {
        ZStack {
            // The picture stays faintly visible: the sentence is about it.
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(Color.black.opacity(0.35))
                .ignoresSafeArea()
                .opacity(shown ? 1 : 0)
                .onTapGesture(perform: close)

            card
                .frame(maxWidth: 520)
                .padding(.horizontal, 16)
                .scaleEffect(shown || reduceMotion ? 1 : 0.88)
                .offset(y: shown || reduceMotion ? 0 : 26)
                .blur(radius: shown || reduceMotion ? 0 : 10)
                .opacity(shown ? 1 : 0)
        }
        .onAppear {
            withAnimation(reduceMotion ? .easeOut(duration: 0.18) : .spring(response: 0.46, dampingFraction: 0.78)) {
                shown = true
            }
            if request != nil {
                Task {
                    try? await Task.sleep(for: .milliseconds(180))
                    focused = true
                }
            }
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if request == nil {
                consent
            } else {
                field
                lastTurn
                suggestions
            }

            footer
        }
        .padding(18)
        .background {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(DS.Palette.glassSheet(0.97))
        }
        .overlay { ShimmerBorder(active: shown && !reduceMotion) }
        .shadow(color: AIPalette.blue.opacity(0.25), radius: 30, y: 12)
    }

    // MARK: Parts

    private var header: some View {
        HStack(spacing: 10) {
            AIOrb(fast: model.isAIDriving)
                .frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text("editor.dock.ai", bundle: .module)
                    .dsFont(.sans, .semibold, 15)
                    .foregroundStyle(DS.Palette.ink)
                Text("editor.ai.session \(model.aiSessionNumber) \(model.aiSessionTurns.count)", bundle: .module)
                    .dsFont(.mono, .medium, 10)
                    .foregroundStyle(DS.Palette.ink(0.45))
                    .contentTransition(.numericText())
                    .id(sessionPulse)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
            Spacer(minLength: 0)
            Button(action: close) {
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
    }

    private var field: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField(String(localized: "editor.ai.placeholder", bundle: .module), text: $text, axis: .vertical)
                .lineLimit(1...6)
                .dsFont(.sans, .regular, 16)
                .foregroundStyle(DS.Palette.ink)
                .tint(AIPalette.blue)
                .focused($focused)
                .submitLabel(.send)
                .onSubmit(send)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(DS.Palette.hairline(0.07)))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(AIPalette.blue.opacity(focused ? 0.7 : 0.2), lineWidth: 1)
                        .animation(DS.Motion.snap, value: focused)
                }

            Button(action: send) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(canSend ? Color.white : DS.Palette.ink(0.35))
                    .frame(width: 48, height: 48)
                    .background(Circle().fill(canSend ? AIPalette.blue : DS.Palette.hairline(0.1)))
                    .scaleEffect(canSend ? 1 : 0.92)
                    .animation(.spring(response: 0.3, dampingFraction: 0.6), value: canSend)
            }
            .buttonStyle(.dsPressIcon)
            .disabled(!canSend)
            .accessibilityLabel(Text("editor.ai.send", bundle: .module))
        }
    }

    @ViewBuilder
    private var lastTurn: some View {
        if let turn = model.aiSessionTurns.last {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AIPalette.blue)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: turn.instruction)
                        .dsFont(.sans, .semibold, 11)
                        .foregroundStyle(DS.Palette.ink(0.75))
                        .lineLimit(1)
                    Text(verbatim: turn.summary)
                        .dsFont(.sans, .regular, 11, lineHeight: 1.3)
                        .foregroundStyle(DS.Palette.ink(0.5))
                        .lineLimit(2)
                }
            }
            .transition(.opacity)
        }
    }

    private var suggestions: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(Array(AIEditPanel.suggestions.enumerated()), id: \.offset) { index, suggestion in
                    Button {
                        withAnimation(DS.Motion.snap) { text = suggestion }
                        focused = true
                    } label: {
                        Text(suggestion)
                            .dsFont(.sans, .medium, 11)
                            .foregroundStyle(DS.Palette.ink(0.85))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(Capsule().fill(DS.Palette.hairline(0.07)))
                    }
                    .buttonStyle(.dsPress(radius: 20))
                    // The chips arrive one after another.
                    .opacity(shown ? 1 : 0)
                    .offset(x: shown || reduceMotion ? 0 : 16)
                    .animation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.8).delay(0.08 + Double(index) * 0.035), value: shown)
                }
            }
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
    }

    private var consent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label {
                Text(onAllowCloudAI == nil ? "editor.ai.unavailable" : "editor.ai.consent", bundle: .module)
                    .dsFont(.sans, .regular, 13, lineHeight: 1.4)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "lock.shield")
                    .foregroundStyle(DS.Palette.accentWarm)
            }
            .foregroundStyle(DS.Palette.ink(0.7))
            if let onAllowCloudAI {
                Button {
                    withAnimation(DS.Motion.settle) { onAllowCloudAI() }
                } label: {
                    Label {
                        Text("editor.ai.consent.allow", bundle: .module)
                    } icon: {
                        Image(systemName: "sparkles")
                    }
                    .dsFont(.sans, .semibold, 14)
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(Capsule().fill(AIPalette.blue))
                }
                .buttonStyle(.dsPress(radius: 24))
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if changeCount > 0 {
                Button {
                    onShowChanges()
                } label: {
                    HStack(spacing: 6) {
                        AISparkle(size: 10)
                        Text("editor.ai.history", bundle: .module)
                            .dsFont(.sans, .semibold, 12)
                            .foregroundStyle(DS.Palette.ink(0.85))
                        Text(verbatim: "\(changeCount)")
                            .dsFont(.mono, .semibold, 10)
                            .foregroundStyle(Color.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(AIPalette.blue))
                            .contentTransition(.numericText(value: Double(changeCount)))
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 38)
                    .background(Capsule().fill(DS.Palette.hairline(0.07)))
                }
                .buttonStyle(.dsPress(radius: 19))
            }

            Spacer(minLength: 0)

            if !model.aiSessionTurns.isEmpty {
                Button {
                    withAnimation(DS.Motion.settle) {
                        model.startNewAISession()
                        sessionPulse += 1
                    }
                } label: {
                    Label(String(localized: "editor.ai.newSession", bundle: .module), systemImage: "plus.bubble")
                        .dsFont(.sans, .semibold, 12)
                        .foregroundStyle(AIPalette.blue)
                        .padding(.horizontal, 12)
                        .frame(height: 38)
                        .background(Capsule().fill(AIPalette.blue.opacity(0.12)))
                        .symbolEffect(.bounce, value: sessionPulse)
                }
                .buttonStyle(.dsPress(radius: 19))
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        }
        .sensoryFeedback(.success, trigger: sessionPulse)
    }

    // MARK: Actions

    private func send() {
        guard canSend, let request else { return }
        let sentence = text
        text = ""
        focused = false
        model.askAI(sentence, using: request)
        close()
    }

    private func close() {
        focused = false
        withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.34, dampingFraction: 0.9)) {
            shown = false
        }
        Task {
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 150 : 260))
            onClose()
        }
    }
}

/// Light travelling round the card's edge while it is open.
private struct ShimmerBorder: View {
    let active: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !active)) { context in
            let angle = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 4) / 4 * 360
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(
                    AngularGradient(
                        colors: [AIPalette.blue.opacity(0.15), AIPalette.sky, AIPalette.blue, AIPalette.blue.opacity(0.15), AIPalette.blue.opacity(0.15)],
                        center: .center,
                        angle: .degrees(angle)
                    ),
                    lineWidth: 1.5
                )
        }
        .allowsHitTesting(false)
    }
}
