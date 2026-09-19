import DesignSystem
import Domain
import SwiftUI
import UIKit

/// The three steps before the stage.
struct SuflorSetupView: View {
    @Bindable var model: SuflorModel
    let onClose: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            topBar
                .padding(.top, 60)
                .padding(.horizontal, 22)

            ZStack {
                switch model.step {
                case .kind: SuflorKindStep(model: model).transition(stepTransition)
                case .brief: SuflorBriefStep(model: model).transition(stepTransition)
                case .flow: SuflorFlowStep(model: model).transition(stepTransition)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .animation(reduceMotion ? .easeOut(duration: 0.15) : DS.Motion.settle, value: model.step)
        }
        .background(DS.Palette.screen)
    }

    private var stepTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .asymmetric(
                insertion: .offset(x: 40).combined(with: .opacity),
                removal: .offset(x: -40).combined(with: .opacity)
            )
    }

    private var topBar: some View {
        HStack(spacing: 14) {
            DSBackButton {
                if !model.back() { onClose() }
            }
            // Three segments, the current one stretched and lit.
            HStack(spacing: 6) {
                ForEach(SuflorModel.Step.allCases, id: \.self) { step in
                    Capsule()
                        .fill(step.rawValue <= model.step.rawValue ? DS.Palette.lime : DS.Palette.hairline(0.14))
                        .frame(width: step == model.step ? 34 : 14, height: 6)
                }
            }
            .animation(DS.Motion.bloom, value: model.step)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("suflor.step.a11y \(model.step.rawValue + 1)", bundle: .module))
            Spacer(minLength: 0)
            DSKicker(String(localized: "suflor.kicker", bundle: .module), size: 11, tracking: 0.18, color: DS.Palette.ink(0.56))
        }
    }
}

// MARK: - 1. What kind

private struct SuflorKindStep: View {
    @Bindable var model: SuflorModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                FloatingWindowDemo()
                    .frame(height: 250)
                    .padding(.top, 22)
                    .dsEnter(.rise())

                DSHeadline(String(localized: "suflor.kind.title", bundle: .module), size: 32)
                    .padding(.top, 26)
                Text("suflor.kind.subtitle", bundle: .module)
                    .dsFont(.sans, .regular, 15, lineHeight: 1.4)
                    .foregroundStyle(DS.Palette.ink(0.66))
                    .padding(.top, 10)

                HStack(spacing: 12) {
                    kindCard(.live, symbol: "dot.radiowaves.left.and.right", title: "suflor.kind.live", detail: "suflor.kind.live.detail")
                    kindCard(.video, symbol: "video.fill", title: "suflor.kind.video", detail: "suflor.kind.video.detail")
                }
                .padding(.top, 22)
                .dsEnter(.rise(delay: 0.08))

                DSKicker(String(localized: "suflor.platform.title", bundle: .module))
                    .padding(.top, 26)
                FlowLayout(horizontalSpacing: 8, verticalSpacing: 8) {
                    ForEach(SuflorBrief.Platform.allCases, id: \.self) { platform in
                        SuflorChip(title: platform.title, isOn: model.brief.platform == platform) {
                            withAnimation(DS.Motion.snap) { model.brief.platform = platform }
                        }
                    }
                }
                .padding(.top, 10)

                DSPrimaryButton(String(localized: "suflor.next", bundle: .module)) { model.next() }
                    .padding(.top, 30)
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
    }

    private func kindCard(_ kind: SuflorBrief.Kind, symbol: String, title titleKey: String.LocalizationValue, detail detailKey: String.LocalizationValue) -> some View {
        let isOn = model.brief.kind == kind
        let title = String(localized: titleKey, bundle: .module)
        let detail = String(localized: detailKey, bundle: .module)
        return Button {
            withAnimation(DS.Motion.bloom) {
                model.brief.kind = kind
                if kind == .video { model.brief.timing = .none }
                if kind == .live, model.brief.timing == .none { model.brief.timing = .minute(5) }
            }
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                ZStack {
                    Circle().fill(isOn ? DS.Palette.inkInverse(0.12) : DS.Palette.hairline(0.07))
                    Image(systemName: symbol)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(isOn ? DS.Palette.inkInverse : DS.Palette.ink)
                        .symbolEffect(.bounce, value: isOn)
                }
                .frame(width: 44, height: 44)
                Spacer(minLength: 22)
                Text(title)
                    .dsFont(.archivo, .bold, 19)
                    .foregroundStyle(isOn ? DS.Palette.inkInverse : DS.Palette.ink)
                Text(detail)
                    .dsFont(.sans, .regular, 13, lineHeight: 1.3)
                    .foregroundStyle(isOn ? DS.Palette.inkInverse(0.7) : DS.Palette.ink(0.6))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, minHeight: 170, alignment: .topLeading)
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                    .fill(isOn ? DS.Palette.lime : DS.Palette.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                    .stroke(isOn ? .clear : DS.Palette.hairline(0.08), lineWidth: 1)
            )
            .scaleEffect(isOn ? 1 : 0.97)
        }
        .buttonStyle(.dsPressCard)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

extension SuflorCue.Role {
    /// What goes on an empty card of this kind.
    var hint: String {
        switch self {
        case .opening: String(localized: "suflor.card.hint.opening", bundle: .module)
        case .topic: String(localized: "suflor.card.hint.topic", bundle: .module)
        case .bridge: String(localized: "suflor.card.hint.bridge", bundle: .module)
        case .ad: String(localized: "suflor.card.hint.ad", bundle: .module)
        case .cta: String(localized: "suflor.card.hint.cta", bundle: .module)
        case .rescue: String(localized: "suflor.card.hint.rescue", bundle: .module)
        case .closing: String(localized: "suflor.card.hint.closing", bundle: .module)
        }
    }
}

extension SuflorBrief.Platform {
    var title: String {
        switch self {
        case .tiktok: "TikTok"
        case .instagram: "Instagram"
        case .youtube: "YouTube"
        case .other: String(localized: "suflor.platform.other", bundle: .module)
        }
    }
}

// MARK: - 2. The brief

private struct SuflorBriefStep: View {
    @Bindable var model: SuflorModel
    @State private var newItem = ""
    @FocusState private var focused: Field?

    private enum Field { case brand, product, details, item, topic }

    private let tones: [String.LocalizationValue] = ["suflor.tone.warm", "suflor.tone.energetic", "suflor.tone.calm", "suflor.tone.funny"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                DSHeadline(String(localized: "suflor.brief.title", bundle: .module), size: 32)
                    .padding(.top, 26)
                Text("suflor.brief.subtitle", bundle: .module)
                    .dsFont(.sans, .regular, 15, lineHeight: 1.4)
                    .foregroundStyle(DS.Palette.ink(0.66))
                    .padding(.top, 10)

                VStack(spacing: 10) {
                    field("suflor.brief.brand", text: $model.brief.brand, field: .brand)
                    field("suflor.brief.product", text: $model.brief.product, field: .product)
                }
                .padding(.top, 22)

                VStack(alignment: .leading, spacing: 8) {
                    DSKicker(String(localized: "suflor.brief.details", bundle: .module))
                    TextField(String(localized: "suflor.brief.details.placeholder", bundle: .module), text: $model.brief.details, axis: .vertical)
                        .lineLimit(3...8)
                        .focused($focused, equals: .details)
                        .dsFont(.sans, .regular, 15)
                        .foregroundStyle(DS.Palette.ink)
                        .frame(maxWidth: .infinity, minHeight: 72, alignment: .topLeading)
                        .padding(14)
                        .contentShape(Rectangle())
                        .onTapGesture { focused = .details }
                        .dsCard(radius: 16, border: focused == .details ? DS.Palette.lime(0.6) : DS.Palette.hairline(0.07))
                    Text("suflor.brief.details.hint", bundle: .module)
                        .dsFont(.sans, .regular, 12)
                        .foregroundStyle(DS.Palette.ink(0.52))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 14)

                mustSay.padding(.top, 22)
                if model.brief.kind == .live { timing.padding(.top, 22) }
                tone.padding(.top, 22)

                VStack(alignment: .leading, spacing: 8) {
                    DSKicker(String(localized: "suflor.brief.topic", bundle: .module))
                    TextField(String(localized: "suflor.brief.topic.placeholder", bundle: .module), text: $model.brief.topic, axis: .vertical)
                        .lineLimit(2...4)
                        .focused($focused, equals: .topic)
                        .dsFont(.sans, .regular, 15)
                        .foregroundStyle(DS.Palette.ink)
                        .frame(maxWidth: .infinity, minHeight: 52, alignment: .topLeading)
                        .padding(14)
                        .contentShape(Rectangle())
                        .onTapGesture { focused = .topic }
                        .dsCard(radius: 16, border: focused == .topic ? DS.Palette.lime(0.6) : DS.Palette.hairline(0.07))
                }
                .padding(.top, 22)

                actions.padding(.top, 26)
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .task { await model.refreshVoice() }
    }

    /// Write like me: the creator's own speech from their videos as the model's example.
    private var voiceCard: some View {
        let words = model.voiceWords ?? 0
        let available = words > 0
        return Button {
            guard available else { return }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(DS.Motion.bloom) { model.useMyVoice.toggle() }
        } label: {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    Circle().fill(model.useMyVoice ? DS.Palette.lime : DS.Palette.hairline(0.08))
                    Image(systemName: "waveform")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(model.useMyVoice ? DS.Palette.inkInverse : DS.Palette.ink(0.8))
                        .symbolEffect(.bounce, value: model.useMyVoice)
                }
                .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 4) {
                    Text("suflor.voice.title", bundle: .module)
                        .dsFont(.sans, .semibold, 16)
                        .foregroundStyle(DS.Palette.ink)
                    Group {
                        if model.voiceWords == nil {
                            Text("suflor.voice.looking", bundle: .module)
                        } else if available {
                            Text("suflor.voice.found \(words)", bundle: .module)
                        } else {
                            Text("suflor.voice.none", bundle: .module)
                        }
                    }
                    .dsFont(.sans, .regular, 13, lineHeight: 1.3)
                    .foregroundStyle(DS.Palette.ink(0.6))
                    .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Capsule()
                    .fill(model.useMyVoice ? DS.Palette.lime : DS.Palette.hairline(0.14))
                    .frame(width: 46, height: 28)
                    .overlay(alignment: model.useMyVoice ? .trailing : .leading) {
                        Circle().fill(model.useMyVoice ? DS.Palette.inkInverse : DS.Palette.ink(0.8)).padding(3)
                    }
                    .padding(.top, 8)
            }
            .padding(16)
            .dsCard(fill: model.useMyVoice ? DS.Palette.lime(0.08) : DS.Palette.surface, radius: 20, border: model.useMyVoice ? DS.Palette.lime(0.45) : DS.Palette.hairline(0.07))
            .opacity(available || model.voiceWords == nil ? 1 : 0.55)
        }
        .buttonStyle(.dsPressCard)
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(voiceState)
    }

    private var voiceState: Text {
        if model.useMyVoice { return Text("suflor.voice.on", bundle: .module) }
        return Text("suflor.voice.off", bundle: .module)
    }

    private func field(_ key: String.LocalizationValue, text: Binding<String>, field: Field) -> some View {
        let title = String(localized: key, bundle: .module)
        return HStack(spacing: 12) {
            Text(title)
                .dsFont(.mono, .medium, 11, letterSpacing: 0.14)
                .foregroundStyle(DS.Palette.ink(0.56))
                .frame(width: 70, alignment: .leading)
            TextField("", text: text)
                .focused($focused, equals: field)
                .dsFont(.sans, .semibold, 16)
                .foregroundStyle(DS.Palette.ink)
                .submitLabel(.next)
                .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                .accessibilityLabel(Text(title))
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 56)
        // The whole card takes the tap, not just the line of text inside it.
        .contentShape(Rectangle())
        .onTapGesture { focused = field }
        .dsCard(radius: 16, border: focused == field ? DS.Palette.lime(0.6) : DS.Palette.hairline(0.07))
        .animation(DS.Motion.snap, value: focused)
    }

    private var mustSay: some View {
        VStack(alignment: .leading, spacing: 10) {
            DSKicker(String(localized: "suflor.brief.mustSay", bundle: .module))
            FlowLayout(horizontalSpacing: 8, verticalSpacing: 8) {
                ForEach(model.brief.mustSay, id: \.self) { item in
                    Button {
                        withAnimation(DS.Motion.snap) { model.brief.mustSay.removeAll { $0 == item } }
                    } label: {
                        HStack(spacing: 6) {
                            Text(item).dsFont(.sans, .semibold, 14)
                            Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
                        }
                        .foregroundStyle(DS.Palette.inkInverse)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 44)
                        .background(Capsule().fill(DS.Palette.lime))
                    }
                    .buttonStyle(.dsPress)
                    .accessibilityLabel(Text("suflor.brief.mustSay.remove \(item)", bundle: .module))
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
                }
                HStack(spacing: 6) {
                    Image(systemName: "plus").font(.system(size: 12, weight: .bold)).foregroundStyle(DS.Palette.ink(0.6))
                    TextField(String(localized: "suflor.brief.mustSay.placeholder", bundle: .module), text: $newItem)
                        .focused($focused, equals: .item)
                        .dsFont(.sans, .medium, 14)
                        .foregroundStyle(DS.Palette.ink)
                        .submitLabel(.done)
                        .onSubmit(addItem)
                        .frame(minWidth: 150)
                }
                .padding(.horizontal, 14)
                .frame(minHeight: 44)
                .background(Capsule().stroke(DS.Palette.hairline(0.16), style: StrokeStyle(lineWidth: 1, dash: [4, 4])))
            }
            Text("suflor.brief.mustSay.hint", bundle: .module)
                .dsFont(.sans, .regular, 12)
                .foregroundStyle(DS.Palette.ink(0.52))
        }
    }

    private func addItem() {
        let item = newItem.trimmingCharacters(in: .whitespacesAndNewlines)
        newItem = ""
        guard !item.isEmpty, !model.brief.mustSay.contains(item) else { return }
        withAnimation(DS.Motion.bloom) { model.brief.mustSay.append(item) }
        focused = .item
    }

    private var minute: Int {
        if case .minute(let value) = model.brief.timing { return value }
        return 10
    }

    private var timing: some View {
        VStack(alignment: .leading, spacing: 10) {
            DSKicker(String(localized: "suflor.brief.when", bundle: .module))
            HStack(spacing: 8) {
                SuflorChip(title: String(localized: "suflor.brief.when.minute", bundle: .module), isOn: isMinute) {
                    withAnimation(DS.Motion.snap) { model.brief.timing = .minute(minute) }
                }
                SuflorChip(title: String(localized: "suflor.brief.when.manual", bundle: .module), isOn: model.brief.timing == .manual) {
                    withAnimation(DS.Motion.snap) { model.brief.timing = .manual }
                }
                SuflorChip(title: String(localized: "suflor.brief.when.none", bundle: .module), isOn: model.brief.timing == .none) {
                    withAnimation(DS.Motion.snap) { model.brief.timing = .none }
                }
            }
            Text(timingExplanation)
                .dsFont(.sans, .regular, 13, lineHeight: 1.35)
                .foregroundStyle(DS.Palette.ink(0.62))
                .fixedSize(horizontal: false, vertical: true)
                .contentTransition(.opacity)
            if isMinute {
                // One value, centred, with its buttons either side: the number and its unit share a
                // baseline, the note sits under them, nothing else competes for the row.
                HStack(spacing: 0) {
                    minuteButton("minus", label: "suflor.brief.when.earlier") { max(1, minute - 1) }
                    Spacer(minLength: 8)
                    VStack(spacing: 2) {
                        HStack(alignment: .firstTextBaseline, spacing: 5) {
                            Text(verbatim: "\(minute)")
                                .dsFont(.archivo, .extrabold, 40)
                                .foregroundStyle(DS.Palette.amber)
                                .contentTransition(.numericText(value: Double(minute)))
                                .monospacedDigit()
                            Text("suflor.brief.when.min", bundle: .module)
                                .dsFont(.sans, .semibold, 16)
                                .foregroundStyle(DS.Palette.amber)
                        }
                        Text("suflor.brief.when.minuteUnit", bundle: .module)
                            .dsFont(.sans, .regular, 12)
                            .foregroundStyle(DS.Palette.ink(0.6))
                            .multilineTextAlignment(.center)
                    }
                    .accessibilityElement(children: .combine)
                    Spacer(minLength: 8)
                    minuteButton("plus", label: "suflor.brief.when.later") { min(180, minute + 1) }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 10)
                .dsCard(radius: 18)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    private func minuteButton(_ symbol: String, label: LocalizedStringKey, next: @escaping () -> Int) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(DS.Motion.snap) { model.brief.timing = .minute(next()) }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(DS.Palette.ink)
                .frame(width: 48, height: 48)
                .background(Circle().fill(DS.Palette.hairline(0.08)))
        }
        .buttonStyle(.dsPressIcon)
        .accessibilityLabel(Text(label, bundle: .module))
    }

    private var timingExplanation: String {
        switch model.brief.timing {
        case .minute(let value): String(localized: "suflor.brief.when.minute.explain \(value)", bundle: .module)
        case .manual: String(localized: "suflor.brief.when.manual.explain", bundle: .module)
        case .none: String(localized: "suflor.brief.when.none.explain", bundle: .module)
        }
    }

    private var isMinute: Bool {
        if case .minute = model.brief.timing { return true }
        return false
    }

    private var tone: some View {
        VStack(alignment: .leading, spacing: 10) {
            DSKicker(String(localized: "suflor.brief.tone", bundle: .module))
            FlowLayout(horizontalSpacing: 8, verticalSpacing: 8) {
                ForEach(tones.indices, id: \.self) { index in
                    let title = String(localized: tones[index], bundle: .module)
                    SuflorChip(title: title, isOn: model.brief.tone == title, tint: DS.Palette.accentWarm) {
                        withAnimation(DS.Motion.snap) { model.brief.tone = model.brief.tone == title ? "" : title }
                    }
                }
            }
        }
    }

    private var templateTitle: String {
        if model.writer == nil { return String(localized: "suflor.brief.template.only", bundle: .module) }
        return String(localized: "suflor.brief.template", bundle: .module)
    }

    private var actions: some View {
        VStack(spacing: 12) {
            DSPrimaryButton(templateTitle) {
                focused = nil
                model.writeMyself()
            }
            if !model.aiCues.isEmpty || !model.ownCues.isEmpty {
                Button {
                    model.next()
                } label: {
                    Text("suflor.brief.keep", bundle: .module)
                        .dsFont(.sans, .medium, 14)
                        .foregroundStyle(DS.Palette.ink(0.66))
                        .frame(minHeight: 44)
                }
                .buttonStyle(.dsPress)
            }
            if model.writer != nil {
                aiDraft.padding(.top, 14)
            }
        }
    }

    /// The AI, set back: a draft to write over, not the way in.
    private var aiDraft: some View {
        VStack(alignment: .leading, spacing: 12) {
            DSKicker(String(localized: "suflor.brief.ai.title", bundle: .module), size: 10, color: DS.Palette.ink(0.5))
            Text("suflor.brief.ai.hint", bundle: .module)
                .dsFont(.sans, .regular, 13, lineHeight: 1.3)
                .foregroundStyle(DS.Palette.ink(0.56))
                .fixedSize(horizontal: false, vertical: true)
            voiceCard
            WriteButton(isWriting: model.isWriting, isEnabled: model.brief.isUsable) {
                focused = nil
                Task { await model.write() }
            }
            if let error = model.writeError {
                VStack(alignment: .leading, spacing: 10) {
                    Text(error)
                        .dsFont(.sans, .medium, 13, lineHeight: 1.35)
                        .foregroundStyle(DS.Palette.accent)
                        .fixedSize(horizontal: false, vertical: true)
                    if model.writeNeedsCloud {
                        Button {
                            Task { await model.allowCloudAndWrite() }
                        } label: {
                            Text("suflor.write.allowCloud", bundle: .module)
                                .dsFont(.sans, .semibold, 14)
                                .foregroundStyle(DS.Palette.inkInverse)
                                .padding(.horizontal, 16)
                                .frame(minHeight: 44)
                                .background(Capsule().fill(DS.Palette.lime))
                        }
                        .buttonStyle(.dsPress)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .dsCard(fill: DS.Palette.accent(0.08), radius: 16, border: DS.Palette.accent(0.3))
                .transition(.opacity)
            }
        }
        .padding(16)
        .dsCard(radius: 22, border: DS.Palette.hairline(0.07))
    }
}

/// The server writes the flow: a lit button with light running through it while it works.
private struct WriteButton: View {
    let isWriting: Bool
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.system(size: 16, weight: .semibold))
                    .symbolEffect(.variableColor.iterative, isActive: isWriting)
                Group {
                    if isWriting {
                        Text("suflor.brief.writing", bundle: .module)
                    } else {
                        Text("suflor.brief.write", bundle: .module)
                    }
                }
                .dsFont(.sans, .semibold, 15)
            }
            .foregroundStyle(DS.Palette.lime)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background {
                ZStack {
                    DS.Palette.lime(0.08)
                    if isWriting { SweepShine() }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous).stroke(DS.Palette.lime(0.4), lineWidth: 1))
        }
        .buttonStyle(.dsPress(radius: DS.Radius.card))
        .disabled(!isEnabled || isWriting)
        .opacity(isEnabled ? 1 : 0.45)
    }
}

// MARK: - 3. The flow

private struct SuflorFlowStep: View {
    @Bindable var model: SuflorModel
    @FocusState private var editing: UUID?
    @Namespace private var pageSpace

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    DSHeadline(String(localized: "suflor.flow.title", bundle: .module), size: 32)
                        .padding(.top, 26)
                    pages.padding(.top, 14)

                    preview.padding(.top, 18)
                    controls.padding(.top, 12)

                    VStack(spacing: 10) {
                        ForEach(model.cues) { cue in
                            card(cue)
                                .transition(.asymmetric(
                                    insertion: .offset(y: 24).combined(with: .opacity).combined(with: .scale(scale: 0.96)),
                                    removal: .opacity.combined(with: .scale(scale: 0.9))
                                ))
                        }
                    }
                    .animation(DS.Motion.bloom, value: model.cues.map(\.id))
                    .padding(.top, 22)

                    addMenu.padding(.top, 12)
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 130)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
        }
        .overlay(alignment: .bottom) { stageButton }
    }

    /// Two pages, the AI's flow and the creator's own; the other one waits untouched.
    private var pages: some View {
        HStack(spacing: 4) {
            pageTab(.own, title: String(localized: "suflor.flow.page.own", bundle: .module), symbol: "pencil", count: model.ownCues.count)
            pageTab(.ai, title: String(localized: "suflor.flow.page.ai", bundle: .module), symbol: "sparkles", count: model.aiCues.count)
        }
        .padding(4)
        .background(Capsule().fill(DS.Palette.hairline(0.06)))
    }

    private func pageTab(_ source: SuflorModel.CueSource, title: String, symbol: String, count: Int) -> some View {
        let isOn = model.cueSource == source
        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(DS.Motion.settle) {
                if source == .own, model.ownCues.isEmpty { model.writeMyself() } else { model.show(source) }
            }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: symbol).font(.system(size: 12, weight: .semibold))
                Text(title).dsFont(.sans, .semibold, 14)
                if count > 0 {
                    Text(verbatim: "\(count)")
                        .dsFont(.mono, .medium, 10)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(isOn ? DS.Palette.inkInverse(0.14) : DS.Palette.hairline(0.1)))
                }
            }
            .foregroundStyle(isOn ? DS.Palette.inkInverse : DS.Palette.ink(0.7))
            .frame(maxWidth: .infinity, minHeight: 44)
            .background {
                if isOn { Capsule().fill(DS.Palette.lime).matchedGeometryEffect(id: "page", in: pageSpace) }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.dsPress)
        .disabled(source == .ai && model.aiCues.isEmpty)
        .opacity(source == .ai && model.aiCues.isEmpty ? 0.45 : 1)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private var preview: some View {
        let (layout, fonts) = model.previewLayout()
        return ZStack(alignment: .topLeading) {
            SuflorLivePreview(layout: layout, wordsPerMinute: model.wordsPerMinute, fonts: fonts)
            HStack(spacing: 6) {
                Image(systemName: "pip").font(.system(size: 11, weight: .semibold))
                Text("suflor.flow.preview", bundle: .module).dsFont(.mono, .medium, 10, letterSpacing: 0.12)
            }
            .foregroundStyle(DS.Palette.ink(0.66))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(DS.Palette.hairline(0.08)))
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(height: 230)
        .background(DS.Palette.camera)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(DS.Palette.hairline(0.1), lineWidth: 1))
        .animation(DS.Motion.settle, value: model.textSize)
    }

    private var controls: some View {
        HStack(spacing: 10) {
            SuflorStepper(
                value: "\(Int(model.wordsPerMinute))",
                caption: String(localized: "suflor.pace.unit", bundle: .module),
                minusLabel: String(localized: "suflor.pace.slower", bundle: .module),
                plusLabel: String(localized: "suflor.pace.faster", bundle: .module),
                onMinus: { withAnimation(DS.Motion.snap) { model.nudgePace(-10) } },
                onPlus: { withAnimation(DS.Motion.snap) { model.nudgePace(10) } }
            )
            SuflorStepper(
                value: "\(Int(model.textSize))",
                caption: String(localized: "suflor.size.unit", bundle: .module),
                minusLabel: String(localized: "suflor.size.smaller", bundle: .module),
                plusLabel: String(localized: "suflor.size.larger", bundle: .module),
                onMinus: { withAnimation(DS.Motion.snap) { model.nudgeSize(-2) } },
                onPlus: { withAnimation(DS.Motion.snap) { model.nudgeSize(2) } }
            )
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 1) {
                Text(SuflorSession.clock(model.flowSeconds))
                    .dsFont(.archivo, .bold, 17)
                    .foregroundStyle(DS.Palette.ink)
                    .contentTransition(.numericText())
                Text("suflor.flow.duration", bundle: .module)
                    .dsFont(.mono, .medium, 10, letterSpacing: 0.1)
                    .foregroundStyle(DS.Palette.ink(0.56))
            }
            .accessibilityElement(children: .combine)
        }
    }

    private func card(_ cue: SuflorCue) -> some View {
        let binding = Binding(
            get: { model.cues.first { $0.id == cue.id }?.text ?? "" },
            set: { text in
                if let index = model.cues.firstIndex(where: { $0.id == cue.id }) { model.cues[index].text = text }
            }
        )
        let fresh = model.freshCues.contains(cue.id)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle().fill(cue.role.color).frame(width: 8, height: 8)
                Text(cue.role.title.uppercased())
                    .dsFont(.mono, .medium, 10, letterSpacing: 0.16)
                    .foregroundStyle(cue.role.color)
                Spacer(minLength: 0)
                Menu {
                    Button { model.move(cue, by: -1) } label: { Label(String(localized: "suflor.card.up", bundle: .module), systemImage: "arrow.up") }
                    Button { model.move(cue, by: 1) } label: { Label(String(localized: "suflor.card.down", bundle: .module), systemImage: "arrow.down") }
                    Button(role: .destructive) { model.remove(cue) } label: { Label(String(localized: "suflor.card.delete", bundle: .module), systemImage: "trash") }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(DS.Palette.ink(0.6))
                        .frame(width: 44, height: 32)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(Text("suflor.card.more", bundle: .module))
            }
            TextField(cue.role.hint, text: binding, axis: .vertical)
                .focused($editing, equals: cue.id)
                .dsFont(.sans, .medium, 16, lineHeight: 1.35)
                .foregroundStyle(DS.Palette.ink)
        }
        .padding(16)
        .dsCard(
            fill: editing == cue.id ? DS.Palette.surfaceActive : DS.Palette.surface,
            radius: 18,
            border: fresh ? DS.Palette.lime(0.7) : DS.Palette.hairline(0.07)
        )
        .animation(DS.Motion.settle, value: fresh)
    }

    private var addMenu: some View {
        Menu {
            ForEach(SuflorCue.Role.allCases, id: \.self) { role in
                Button(role.title) { withAnimation(DS.Motion.bloom) { model.add(role) } }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus").font(.system(size: 13, weight: .bold))
                Text("suflor.card.add", bundle: .module).dsFont(.sans, .semibold, 14)
            }
            .foregroundStyle(DS.Palette.ink(0.8))
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(DS.Palette.hairline(0.16), style: StrokeStyle(lineWidth: 1, dash: [5, 5]))
            )
        }
    }

    private var stageButton: some View {
        Button {
            editing = nil
            model.goOnStage()
        } label: {
            HStack(spacing: 10) {
                LiveDot(size: 7, color: DS.Palette.inkInverse)
                Text("suflor.flow.stage", bundle: .module).dsFont(.archivo, .bold, 18)
            }
            .foregroundStyle(DS.Palette.inkInverse)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 19)
            .background {
                ZStack {
                    DS.gradient(150, [DS.Palette.accent, DS.Palette.accentWarm])
                    SweepShine()
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.cardLarge, style: .continuous))
            .shadow(color: DS.Palette.accent(0.4), radius: 26, y: 16)
        }
        .buttonStyle(.dsPress(radius: DS.Radius.cardLarge))
        .disabled(!model.isReady)
        .opacity(model.isReady ? 1 : 0.4)
        .padding(.horizontal, 22)
        .padding(.bottom, 30)
        .background(
            LinearGradient(colors: [DS.Palette.screen.opacity(0), DS.Palette.screen], startPoint: .top, endPoint: .center)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        )
    }
}
