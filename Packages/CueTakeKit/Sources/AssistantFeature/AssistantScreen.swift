import DesignSystem
import Domain
import SwiftUI

/// The assistant: a conversation, drawn in glass over a slowly moving light.
///
/// Built around one idea — the user should never be further than one sentence from knowing what
/// to do next. So it opens on the question rather than on an empty chat, suggests the questions
/// people actually get stuck on, and every answer that names a place in the app comes with the
/// button that goes there.
///
/// Liquid Glass is used where it means something: on the things that float above the
/// conversation (the header, the composer, the assistant's own replies) and never on the user's
/// words, which are solid because they are the user's.
public struct AssistantScreen: View {
    @Bindable private var model: AssistantModel
    private let onClose: () -> Void

    @FocusState private var composerFocused: Bool
    @Namespace private var glass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(model: AssistantModel, onClose: @escaping () -> Void) {
        self.model = model
        self.onClose = onClose
    }

    public var body: some View {
        ZStack {
            AssistantAmbience(isThinking: model.isSending)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                header

                if model.messages.isEmpty && !model.isSending {
                    welcome
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                } else {
                    conversation
                        .transition(.opacity)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                composer
            }

            if model.showsSessions {
                AssistantSessionsView(model: model)
                    .transition(.move(edge: .leading).combined(with: .opacity))
                    .zIndex(2)
            }
        }
        .animation(reduceMotion ? nil : DS.Motion.settle, value: model.messages.isEmpty)
        .animation(reduceMotion ? nil : DS.Motion.settle, value: model.showsSessions)
        .preferredColorScheme(.dark)
    }

    // MARK: - Header

    private var header: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 10) {
                glassIcon("sidebar.left") {
                    composerFocused = false
                    model.showsSessions = true
                }
                .glassEffectID("sessions", in: glass)

                VStack(spacing: 1) {
                    Text(model.current?.title.isEmpty == false ? model.current!.title : String(localized: "assistant.title", bundle: .module))
                        .dsFont(.sans, .semibold, 14)
                        .foregroundStyle(DS.Palette.ink)
                        .lineLimit(1)
                        .contentTransition(.opacity)

                    HStack(spacing: 5) {
                        Circle()
                            .fill(model.isConnected ? DS.Palette.lime : DS.Palette.accentWarm)
                            .frame(width: 5, height: 5)
                        Text(
                            model.isSending
                                ? String(localized: "assistant.status.thinking", bundle: .module)
                                : (model.isConnected
                                    ? String(localized: "assistant.status.ready", bundle: .module)
                                    : String(localized: "assistant.status.offline", bundle: .module))
                        )
                        .dsFont(.mono, .medium, 10, letterSpacing: 0.08)
                        .foregroundStyle(DS.Palette.ink(0.56))
                        .contentTransition(.opacity)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .padding(.horizontal, 14)
                .glassEffect(.regular, in: .capsule)

                glassIcon("square.and.pencil") {
                    withAnimation(DS.Motion.settle) { model.newSession() }
                }
                .disabled(model.messages.isEmpty)
                .glassEffectID("new", in: glass)

                glassIcon("xmark", action: onClose)
                    .glassEffectID("close", in: glass)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 6)
    }

    private func glassIcon(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .dsActionName(symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(DS.Palette.ink(0.9))
                .frame(width: 42, height: 42)
        }
        .buttonStyle(.dsPressIcon)
        .glassEffect(.regular.interactive(), in: .circle)
    }

    // MARK: - Welcome

    /// What an empty conversation looks like: a question, and the questions people really ask.
    private var welcome: some View {
        ScrollView {
            VStack(spacing: 22) {
                AssistantOrb(isThinking: false)
                    .frame(width: 96, height: 96)
                    .padding(.top, 36)

                VStack(spacing: 8) {
                    Text("assistant.welcome.title", bundle: .module)
                        .dsFont(.archivo, .bold, 26)
                        .foregroundStyle(DS.Palette.ink)
                        .multilineTextAlignment(.center)
                    Text("assistant.welcome.note", bundle: .module)
                        .dsFont(.sans, .regular, 14, lineHeight: 1.45)
                        .foregroundStyle(DS.Palette.ink(0.5))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 30)
                }

                if !model.isConnected {
                    Label(String(localized: "assistant.notConnected", bundle: .module), systemImage: "bolt.horizontal.circle")
                        .dsFont(.sans, .regular, 12)
                        .foregroundStyle(DS.Palette.accentWarm)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .glassEffect(.regular.tint(DS.Palette.accentWarm.opacity(0.15)), in: .capsule)
                }

                VStack(spacing: 9) {
                    ForEach(Array(Self.suggestions.enumerated()), id: \.offset) { index, key in
                        let text = String(localized: key, bundle: .module)
                        Button {
                            model.draft = text
                            Task { await model.submit() }
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: Self.suggestionSymbols[index])
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(DS.Palette.lime)
                                    .frame(width: 22)
                                Text(text)
                                    .dsFont(.sans, .medium, 14)
                                    .foregroundStyle(DS.Palette.ink(0.9))
                                    .multilineTextAlignment(.leading)
                                Spacer(minLength: 0)
                                Image(systemName: "arrow.up.right")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(DS.Palette.ink(0.52))
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        }
                        .buttonStyle(.dsPress(radius: 20))
                        .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .disabled(!model.isConnected)
                        .dsEnter(.rise(duration: 0.5, delay: 0.1 + Double(index) * 0.07))
                    }
                }
                .padding(.horizontal, 20)
            }
            .padding(.bottom, 30)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
    }

    static let suggestions: [String.LocalizationValue] = [
        "assistant.suggest.start",
        "assistant.suggest.pauses",
        "assistant.suggest.hook",
        "assistant.suggest.workflow",
    ]

    static let suggestionSymbols = ["map", "waveform.path", "bolt", "flowchart"]

    // MARK: - Conversation

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(model.messages) { message in
                        AssistantBubble(
                            message: message,
                            onDestination: { destination in model.onDestination?(destination) },
                            onWorkflow: { workflow, run in model.onWorkflow?(workflow, run) }
                        )
                        .id(message.id)
                        .transition(
                            reduceMotion
                                ? .opacity
                                : .asymmetric(
                                    insertion: .opacity
                                        .combined(with: .offset(y: 18))
                                        .combined(with: .scale(scale: 0.94, anchor: message.role == .user ? .bottomTrailing : .bottomLeading)),
                                    removal: .opacity
                                )
                        )
                    }

                    if model.isSending {
                        TypingIndicator()
                            .id("typing")
                            .transition(.opacity.combined(with: .scale(scale: 0.8, anchor: .leading)))
                    }

                    if let failure = model.failure {
                        failureCard(failure)
                            .id("failure")
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 16)
                .animation(reduceMotion ? nil : DS.Motion.bloom, value: model.messages.count)
                .animation(reduceMotion ? nil : DS.Motion.settle, value: model.isSending)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .defaultScrollAnchor(.bottom)
            .onChange(of: model.messages.count) {
                withAnimation(DS.Motion.settle) { proxy.scrollTo(model.messages.last?.id, anchor: .bottom) }
            }
            .onChange(of: model.isSending) {
                if model.isSending {
                    withAnimation(DS.Motion.settle) { proxy.scrollTo("typing", anchor: .bottom) }
                }
            }
        }
    }

    private func failureCard(_ text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(DS.Palette.accent)
            Text(text)
                .dsFont(.sans, .regular, 13)
                .foregroundStyle(DS.Palette.ink(0.8))
            Spacer(minLength: 0)
            Button {
                Task { await model.retry() }
            } label: {
                Text("assistant.retry", bundle: .module)
                    .dsFont(.sans, .semibold, 12)
                    .foregroundStyle(DS.Palette.ink)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
            }
            .buttonStyle(.dsPress(radius: 20))
            .glassEffect(.regular.interactive(), in: .capsule)
        }
        .padding(12)
        .glassEffect(.regular.tint(DS.Palette.accent.opacity(0.12)), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    // MARK: - Composer

    /// The composer: a glass capsule that grows with what is typed, and a send button that becomes
    /// a pulse while the answer is on its way.
    private var composer: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(alignment: .bottom, spacing: 10) {
                TextField(
                    String(localized: "assistant.placeholder", bundle: .module),
                    text: $model.draft,
                    axis: .vertical
                )
                .dsFont(.sans, .regular, 16)
                .foregroundStyle(DS.Palette.ink)
                .lineLimit(1...6)
                .focused($composerFocused)
                .submitLabel(.send)
                .onSubmit { Task { await model.submit() } }
                .padding(.horizontal, 18)
                .padding(.vertical, 13)
                .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .disabled(!model.isConnected)

                let canSend = !model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    && !model.isSending && model.isConnected

                Button {
                    Task { await model.submit() }
                } label: {
                    ZStack {
                        if model.isSending {
                            AssistantOrb(isThinking: true)
                                .frame(width: 26, height: 26)
                                .transition(.scale.combined(with: .opacity))
                        } else {
                            Image(systemName: "arrow.up")
                                .dsActionName("arrow.up")
                                .font(.system(size: 17, weight: .bold))
                                .foregroundStyle(canSend ? DS.Palette.inkInverse : DS.Palette.ink(0.4))
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .frame(width: 48, height: 48)
                }
                .buttonStyle(.dsPressIcon)
                .glassEffect(
                    canSend ? .regular.tint(DS.Palette.lime).interactive() : .regular.interactive(),
                    in: .circle
                )
                .glassEffectID("send", in: glass)
                .disabled(!canSend)
                .animation(DS.Motion.bloom, value: canSend)
                .animation(DS.Motion.bloom, value: model.isSending)
                .sensoryFeedback(.impact(weight: .medium), trigger: model.messages.count)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }
}
