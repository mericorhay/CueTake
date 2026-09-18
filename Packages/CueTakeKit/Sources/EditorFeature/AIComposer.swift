import DesignSystem
import Domain
import SwiftUI

/// Telling the AI what to do — or what video to make: one card in the middle of the screen,
/// above the keyboard.
///
/// It replaces the panel in the tool dock and the bar at the top — two places for one sentence.
/// The edit card carries the session the AI is in, the last thing it did, and the way to every
/// change it made; the generate card carries the model, where the video goes, and what is being
/// made. The card measures the room it has and drops its extras before it would run under the
/// keyboard or off the top of a small phone.
struct AIComposer: View {
    enum Purpose {
        /// `request` is nil when cloud AI is off or not in this build.
        case edit(request: AIRequester?, onAllowCloudAI: (() -> Void)?, onShowChanges: () -> Void)
        case generate(onOpenOptions: () -> Void)
    }

    @Bindable var model: EditorModel
    @Binding var text: String
    let purpose: Purpose
    let onClose: () -> Void

    @FocusState private var focused: Bool
    @State private var shown = false
    @State private var sessionPulse = 0
    @State private var sentPulse = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isEdit: Bool {
        if case .edit = purpose { true } else { false }
    }

    private var request: AIRequester? {
        if case .edit(let request, _, _) = purpose { request } else { nil }
    }

    private var tint: Color { isEdit ? AIPalette.blue : DS.Palette.lime }

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var generationBlocker: LocalizedStringKey? {
        let options = model.fittedGenerationOptions(model.generationDefaults)
        if !model.generationHasKey(options.modelPreset.provider) { return "editor.generate.needsKey" }
        if options.resolvedModel.isEmpty { return "editor.generate.needsModel" }
        return nil
    }

    private var canSend: Bool {
        guard !trimmed.isEmpty else { return false }
        switch purpose {
        case .edit: return request != nil && !model.isAIDriving
        case .generate: return generationBlocker == nil
        }
    }

    private var changeCount: Int { model.aiChanges.reduce(0) { $0 + $1.activeCount } }

    var body: some View {
        GeometryReader { box in
            ZStack {
                // The picture stays faintly visible: the sentence is about it.
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .overlay(Color.black.opacity(0.35))
                    .ignoresSafeArea()
                    .opacity(shown ? 1 : 0)
                    .onTapGesture(perform: close)
                    .accessibilityHidden(true)

                card(room: box.size.height)
                    .frame(maxWidth: 520)
                    .padding(.horizontal, 16)
                    .scaleEffect(shown || reduceMotion ? 1 : 0.88)
                    .offset(y: shown || reduceMotion ? 0 : 26)
                    .blur(radius: shown || reduceMotion ? 0 : 10)
                    .opacity(shown ? 1 : 0)
            }
            .frame(width: box.size.width, height: box.size.height)
        }
        .onAppear {
            withAnimation(reduceMotion ? .easeOut(duration: 0.18) : .spring(response: 0.46, dampingFraction: 0.78)) {
                shown = true
            }
            if !isEdit || request != nil { focusSoon() }
        }
        // Cloud AI switched on from the card: the field appears, ready to type in.
        .onChange(of: request != nil) { _, available in
            if available { focusSoon() }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: sentPulse)
    }

    /// Everything, or less of it: the extras go first when the keyboard leaves little room.
    private func card(room: CGFloat) -> some View {
        let roomy = room > 470
        let medium = room > 360
        return VStack(alignment: .leading, spacing: 14) {
            header

            if isEdit, request == nil {
                consent
            } else {
                field
                if !isEdit {
                    generateSummary(compact: !medium)
                }
                if isEdit, roomy {
                    lastTurn
                }
                if medium {
                    suggestions
                }
            }

            footer
        }
        .padding(18)
        .background {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(DS.Palette.glassSheet(0.97))
        }
        .overlay { ShimmerBorder(active: shown && !reduceMotion, tint: tint) }
        .shadow(color: tint.opacity(0.25), radius: 30, y: 12)
        .frame(maxHeight: max(160, room - 24))
        .animation(DS.Motion.settle, value: roomy)
        .animation(DS.Motion.settle, value: medium)
    }

    // MARK: Parts

    private var header: some View {
        HStack(spacing: 10) {
            if isEdit {
                AIOrb(fast: model.isAIDriving)
                    .frame(width: 30, height: 30)
            } else {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(DS.Palette.inkInverse)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(DS.Palette.lime))
                    .symbolEffect(.bounce, value: sentPulse)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(isEdit ? "editor.dock.ai" : "editor.generate.compose", bundle: .module)
                    .dsFont(.sans, .semibold, 15)
                    .foregroundStyle(DS.Palette.ink)
                Group {
                    if isEdit {
                        Text("editor.ai.session \(model.aiSessionNumber) \(model.aiSessionTurns.count)", bundle: .module)
                    } else {
                        Text(verbatim: generationModelLine)
                    }
                }
                .dsFont(.mono, .medium, 10)
                .foregroundStyle(DS.Palette.ink(0.56))
                .lineLimit(1)
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

    private var generationModelLine: String {
        let options = model.fittedGenerationOptions(model.generationDefaults)
        let name = options.modelPreset.isCustom && !options.resolvedModel.isEmpty ? options.resolvedModel : options.modelPreset.title
        return "\(name) · \(Int(options.seconds)) s"
    }

    private var field: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField(
                isEdit ? String(localized: "editor.ai.placeholder", bundle: .module) : String(localized: "editor.generate.placeholder", bundle: .module),
                text: $text,
                axis: .vertical
            )
            .lineLimit(1...6)
            .dsFont(.sans, .regular, 16)
            .foregroundStyle(DS.Palette.ink)
            .tint(tint)
            .focused($focused)
            .submitLabel(.send)
            .onSubmit(send)
            // A field that grows sends on Return instead of starting a new line.
            .onChange(of: text) { _, value in
                guard value.contains("\n") else { return }
                text = value.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
                send()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(DS.Palette.hairline(0.07)))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(tint.opacity(focused ? 0.7 : 0.2), lineWidth: 1)
                    .animation(DS.Motion.snap, value: focused)
            }

            Button(action: send) {
                Image(systemName: isEdit ? "arrow.up" : "wand.and.stars")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(canSend ? (isEdit ? Color.white : DS.Palette.inkInverse) : DS.Palette.ink(0.35))
                    .frame(width: 48, height: 48)
                    .background(Circle().fill(canSend ? tint : DS.Palette.hairline(0.1)))
                    .scaleEffect(canSend ? 1 : 0.92)
                    .animation(.spring(response: 0.3, dampingFraction: 0.6), value: canSend)
            }
            .buttonStyle(.dsPressIcon)
            .disabled(!canSend)
            .accessibilityLabel(Text(isEdit ? "editor.ai.send" : "editor.generate.send", bundle: .module))
        }
    }

    /// Where the video goes, how long it is, and anything that stops it being made.
    @ViewBuilder
    private func generateSummary(compact: Bool) -> some View {
        if case .generate(let onOpenOptions) = purpose {
            VStack(alignment: .leading, spacing: 8) {
                if let blocker = generationBlocker {
                    Label {
                        Text(blocker, bundle: .module)
                            .dsFont(.sans, .medium, 12, lineHeight: 1.3)
                    } icon: {
                        Image(systemName: "key.slash")
                    }
                    .foregroundStyle(DS.Palette.accentWarm)
                }
                HStack(spacing: 6) {
                    ForEach([GenerationPlacement.broll, .clip], id: \.self) { placement in
                        let active = model.generationPlacement == placement
                        Button {
                            withAnimation(DS.Motion.snap) { model.generationPlacement = placement }
                        } label: {
                            Label(
                                String(localized: placement == .broll ? "editor.generate.broll" : "editor.generate.clip", bundle: .module),
                                systemImage: placement == .broll ? "rectangle.on.rectangle" : "film.stack"
                            )
                            .dsFont(.sans, .semibold, 11)
                            .foregroundStyle(active ? DS.Palette.inkInverse : DS.Palette.ink(0.7))
                            .frame(maxWidth: .infinity)
                            .frame(height: 34)
                            .background(Capsule().fill(active ? DS.Palette.lime : DS.Palette.hairline(0.07)))
                        }
                        .buttonStyle(.dsPress(radius: 17))
                        .accessibilityAddTraits(active ? .isSelected : [])
                    }
                    Button {
                        close()
                        onOpenOptions()
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(DS.Palette.ink(0.75))
                            .frame(width: 44, height: 34)
                            .background(Capsule().fill(DS.Palette.hairline(0.07)))
                    }
                    .buttonStyle(.dsPress(radius: 17))
                    .accessibilityLabel(Text("editor.generate.options", bundle: .module))
                }
                if !compact {
                    Text("editor.generate.note \(Int(model.fittedGenerationOptions(model.generationDefaults).seconds))", bundle: .module)
                        .dsFont(.sans, .regular, 10, lineHeight: 1.35)
                        .foregroundStyle(DS.Palette.ink(0.56))
                }
            }
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

    private var suggestionList: [String] {
        isEdit ? AIEditPanel.suggestions : EditorScreen.generateSuggestions
    }

    private var suggestions: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(Array(suggestionList.enumerated()), id: \.offset) { index, suggestion in
                    Button {
                        withAnimation(DS.Motion.snap) { text = suggestion }
                        focused = true
                    } label: {
                        Text(suggestion)
                            .dsFont(.sans, .medium, 11)
                            .foregroundStyle(DS.Palette.ink(0.85))
                            .padding(.horizontal, 10)
                            .frame(minHeight: 32)
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
        let onAllowCloudAI: (() -> Void)? = if case .edit(_, let allow, _) = purpose { allow } else { nil }
        return VStack(alignment: .leading, spacing: 12) {
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

    @ViewBuilder
    private var footer: some View {
        switch purpose {
        case .edit(_, _, let onShowChanges):
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
                        .frame(height: 40)
                        .background(Capsule().fill(DS.Palette.hairline(0.07)))
                    }
                    .buttonStyle(.dsPress(radius: 20))
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
                            .frame(height: 40)
                            .background(Capsule().fill(AIPalette.blue.opacity(0.12)))
                            .symbolEffect(.bounce, value: sessionPulse)
                    }
                    .buttonStyle(.dsPress(radius: 20))
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }
            }
            .sensoryFeedback(.success, trigger: sessionPulse)
        case .generate:
            let working = model.generationJobs.filter { $0.phase == .working }.count
            if working > 0 {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small).tint(DS.Palette.lime)
                    Text("editor.generate.working \(working)", bundle: .module)
                        .dsFont(.sans, .medium, 11)
                        .foregroundStyle(DS.Palette.ink(0.6))
                        .contentTransition(.numericText())
                }
                .transition(.opacity)
            }
        }
    }

    // MARK: Actions

    private func focusSoon() {
        Task {
            try? await Task.sleep(for: .milliseconds(180))
            focused = true
        }
    }

    private func send() {
        guard canSend else { return }
        let sentence = trimmed
        switch purpose {
        case .edit:
            guard let request else { return }
            text = ""
            focused = false
            sentPulse += 1
            model.askAI(sentence, using: request)
            close()
        case .generate:
            guard model.generateClip(prompt: sentence) != nil else { return }
            text = ""
            focused = false
            sentPulse += 1
            close()
        }
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
    var tint: Color = AIPalette.blue

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !active)) { context in
            let angle = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 4) / 4 * 360
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(
                    AngularGradient(
                        colors: [tint.opacity(0.15), AIPalette.sky, tint, tint.opacity(0.15), tint.opacity(0.15)],
                        center: .center,
                        angle: .degrees(angle)
                    ),
                    lineWidth: 1.5
                )
        }
        .allowsHitTesting(false)
    }
}
