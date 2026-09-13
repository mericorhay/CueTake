import AssistantFeature
import DesignSystem
import Domain
import SwiftUI

/// Where you are, what is next, and the way to ask.
///
/// Opened from the stage name next to every back button. It answers the three questions a lost
/// user actually has, in the order they have them: *where am I*, *what do I do now*, and *can
/// someone just tell me* — the last one being the assistant, one field away.
struct JourneyMapSheet: View {
    @Bindable var model: AppModel

    @State private var question = ""
    @State private var shown = false
    @FocusState private var askFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var context: DSJourneyContext { model.journeyContext }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                stages
                if let next = model.journeyNext {
                    nextStep(next)
                }
                shortcuts
                ask
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 30)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .background(DS.Palette.screen.opacity(0.6))
        .presentationBackground(.ultraThinMaterial)
        .onAppear {
            guard !reduceMotion else {
                shown = true
                return
            }
            withAnimation(DS.Motion.settle) { shown = true }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            DSKicker(String(localized: "journey.kicker"))
            Text(model.project.title)
                .dsFont(.archivo, .bold, 24)
                .foregroundStyle(DS.Palette.ink)
                .lineLimit(2)
        }
    }

    // MARK: - Stages

    /// Four stops on a line. Done ones are filled, the current one glows, and every one is a
    /// button — the map is also the fastest way to get anywhere.
    private var stages: some View {
        VStack(spacing: 0) {
            ForEach(Array(context.stages.enumerated()), id: \.offset) { index, name in
                let isCurrent = context.current == index
                let isDone = context.completed.contains(index)
                let isLast = index == context.stages.count - 1

                Button {
                    model.goToStage(index)
                } label: {
                    HStack(alignment: .top, spacing: 14) {
                        VStack(spacing: 0) {
                            ZStack {
                                Circle()
                                    .fill(isDone ? DS.Palette.lime : DS.Palette.hairline(isCurrent ? 0.2 : 0.08))
                                    .frame(width: 30, height: 30)
                                if isDone {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 12, weight: .black))
                                        .foregroundStyle(DS.Palette.inkInverse)
                                } else {
                                    Text(verbatim: "\(index + 1)")
                                        .dsFont(.mono, .semibold, 12)
                                        .foregroundStyle(DS.Palette.ink(isCurrent ? 1 : 0.5))
                                }
                            }
                            .overlay {
                                if isCurrent {
                                    Circle()
                                        .stroke(DS.Palette.lime, lineWidth: 2)
                                        .frame(width: 38, height: 38)
                                        .dsPulse(duration: 1.4)
                                }
                            }

                            if !isLast {
                                Rectangle()
                                    .fill(isDone ? DS.Palette.lime : DS.Palette.hairline(0.14))
                                    .frame(width: 2, height: 30)
                            }
                        }
                        .frame(width: 38)

                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 8) {
                                Text(name)
                                    .dsFont(.sans, .semibold, 16)
                                    .foregroundStyle(DS.Palette.ink(isCurrent || isDone ? 1 : 0.6))
                                if isCurrent {
                                    Text("journey.here")
                                        .dsFont(.mono, .medium, 9, letterSpacing: 0.1)
                                        .foregroundStyle(DS.Palette.inkInverse)
                                        .padding(.horizontal, 7)
                                        .padding(.vertical, 3)
                                        .background(Capsule().fill(DS.Palette.lime))
                                }
                            }
                            Text(Self.stageNote(index))
                                .dsFont(.sans, .regular, 12)
                                .foregroundStyle(DS.Palette.ink(0.45))
                        }
                        .padding(.top, 5)

                        Spacer(minLength: 0)

                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(DS.Palette.ink(0.25))
                            .padding(.top, 10)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.dsPress(radius: 16))
                .opacity(shown ? 1 : 0)
                .offset(x: shown ? 0 : -16)
                .animation(reduceMotion ? nil : DS.Motion.settle.delay(Double(index) * 0.06), value: shown)
            }
        }
        .padding(16)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    static func stageNote(_ index: Int) -> LocalizedStringResource {
        switch index {
        case 0: "journey.stage.start.note"
        case 1: "journey.stage.edit.note"
        case 2: "journey.stage.captions.note"
        default: "journey.stage.share.note"
        }
    }

    // MARK: - Next

    /// The single most useful sentence on the sheet.
    private func nextStep(_ stage: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(String(localized: "journey.next"), systemImage: "arrow.forward.circle.fill")
                .dsFont(.mono, .medium, 10, letterSpacing: 0.1)
                .foregroundStyle(DS.Palette.lime)

            Text(Self.nextSentence(stage))
                .dsFont(.sans, .medium, 16, lineHeight: 1.4)
                .foregroundStyle(DS.Palette.ink)

            Button {
                if stage == 0 {
                    model.isJourneyOpen = false
                    // After the sheet has gone: the picker is a presentation too.
                    Task {
                        try? await Task.sleep(for: .milliseconds(450))
                        model.isPickingFootage = true
                    }
                } else {
                    model.goToStage(stage)
                }
            } label: {
                HStack(spacing: 8) {
                    Text(Self.nextAction(stage))
                        .dsFont(.sans, .semibold, 15)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 13, weight: .bold))
                }
                .foregroundStyle(DS.Palette.inkInverse)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            }
            .buttonStyle(.dsPress(radius: 18))
            .glassEffect(.regular.tint(DS.Palette.accent).interactive(), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .padding(16)
        .glassEffect(.regular.tint(DS.Palette.lime.opacity(0.08)), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    static func nextSentence(_ stage: Int) -> LocalizedStringResource {
        switch stage {
        case 0: "journey.next.start"
        case 1: "journey.next.edit"
        case 2: "journey.next.captions"
        default: "journey.next.share"
        }
    }

    static func nextAction(_ stage: Int) -> LocalizedStringResource {
        switch stage {
        case 0: "journey.next.start.action"
        case 1: "journey.next.edit.action"
        case 2: "journey.next.captions.action"
        default: "journey.next.share.action"
        }
    }

    // MARK: - Shortcuts

    private var shortcuts: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 8) {
                shortcut("house", "journey.home") { model.isJourneyOpen = false; model.go(to: .home) }
                shortcut("square.grid.2x2", "journey.projects") { model.isJourneyOpen = false; model.go(to: .projects) }
                shortcut("flowchart", "journey.workflows") { model.isJourneyOpen = false; model.go(to: .workflows) }
            }
        }
    }

    private func shortcut(_ symbol: String, _ key: LocalizedStringResource, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .semibold))
                Text(key)
                    .dsFont(.sans, .medium, 11)
            }
            .foregroundStyle(DS.Palette.ink(0.85))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
        }
        .buttonStyle(.dsPress(radius: 18))
        .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    // MARK: - Ask

    /// One field between feeling lost and being told.
    private var ask: some View {
        HStack(spacing: 10) {
            AssistantLauncherOrb()
                .frame(width: 26, height: 26)

            TextField(String(localized: "journey.ask.placeholder"), text: $question, axis: .vertical)
                .dsFont(.sans, .regular, 15)
                .foregroundStyle(DS.Palette.ink)
                .lineLimit(1...3)
                .focused($askFocused)
                .submitLabel(.send)
                .onSubmit(send)

            Button(action: send) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(question.isEmpty ? DS.Palette.ink(0.4) : DS.Palette.inkInverse)
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.dsPressIcon)
            .glassEffect(question.isEmpty ? .regular.interactive() : .regular.tint(DS.Palette.lime).interactive(), in: .circle)
            .animation(DS.Motion.bloom, value: question.isEmpty)
        }
        .padding(.leading, 14)
        .padding(.trailing, 6)
        .padding(.vertical, 6)
        .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    private func send() {
        let text = question.trimmingCharacters(in: .whitespacesAndNewlines)
        question = ""
        model.openAssistant(asking: text.isEmpty ? nil : text)
    }
}
