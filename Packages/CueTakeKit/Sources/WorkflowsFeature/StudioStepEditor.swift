import DesignSystem
import Domain
import SwiftUI
import UIKit

/// The details of one tool, opened in place under its card.
///
/// Each tool shows only the controls it has, with its real units — seconds, dB, × — because a
/// parameter someone cannot read is a parameter someone will leave at its default forever.
struct StudioStepEditor: View {
    @Bindable var model: WorkflowStudioModel
    let step: WorkflowStep

    @State private var newWord = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch step.kind {
            case .trimSilences(let options):
                slider(
                    "studio.param.minPause",
                    value: options.minPause,
                    range: 0.2...2,
                    step: 0.05,
                    format: "%.2f s"
                ) { value in
                    var changed = options
                    changed.minPause = value
                    model.updateStep(step.id, kind: .trimSilences(changed))
                }
                slider(
                    "studio.param.padding",
                    value: options.padding,
                    range: 0...0.5,
                    step: 0.01,
                    format: "%.2f s"
                ) { value in
                    var changed = options
                    changed.padding = value
                    model.updateStep(step.id, kind: .trimSilences(changed))
                }

            case .cutWords(let options):
                words(options)

            case .setSpeed(let options):
                chips(
                    "studio.param.target",
                    options: ["all"] + WorkflowSection.standardRoles,
                    selected: options.target,
                    label: { $0 == "all" ? AppLocalization.string("studio.param.all", bundle: .module) : StudioCatalog.roleLabel($0) }
                ) { value in
                    var changed = options
                    changed.target = value
                    model.updateStep(step.id, kind: .setSpeed(changed))
                }
                chips(
                    "studio.param.speed",
                    options: [0.5, 0.75, 1.1, 1.25, 1.5, 2.0],
                    selected: options.speed,
                    label: { String(format: "%g×", $0) }
                ) { value in
                    var changed = options
                    changed.speed = value
                    model.updateStep(step.id, kind: .setSpeed(changed))
                }

            case .cleanAudio(let options):
                toggle("studio.param.denoise", isOn: options.denoise) {
                    var changed = options
                    changed.denoise.toggle()
                    model.updateStep(step.id, kind: .cleanAudio(changed))
                }
                toggle("studio.param.enhance", isOn: options.enhanceVoice) {
                    var changed = options
                    changed.enhanceVoice.toggle()
                    model.updateStep(step.id, kind: .cleanAudio(changed))
                }
                toggle("studio.param.rumble", isOn: options.removeRumble) {
                    var changed = options
                    changed.removeRumble.toggle()
                    model.updateStep(step.id, kind: .cleanAudio(changed))
                }

            case .musicBed(let options):
                slider("studio.param.level", value: options.levelDB, range: -40...0, step: 1, format: "%.0f dB") { value in
                    var changed = options
                    changed.levelDB = value
                    model.updateStep(step.id, kind: .musicBed(changed))
                }
                toggle("studio.param.ducking", isOn: options.ducking) {
                    var changed = options
                    changed.ducking.toggle()
                    model.updateStep(step.id, kind: .musicBed(changed))
                }
                slider("studio.param.fadeIn", value: options.fadeIn, range: 0...5, step: 0.1, format: "%.1f s") { value in
                    var changed = options
                    changed.fadeIn = value
                    model.updateStep(step.id, kind: .musicBed(changed))
                }
                slider("studio.param.fadeOut", value: options.fadeOut, range: 0...5, step: 0.1, format: "%.1f s") { value in
                    var changed = options
                    changed.fadeOut = value
                    model.updateStep(step.id, kind: .musicBed(changed))
                }

            case .applyCaptionStyle(let preset):
                chips(
                    "studio.param.preset",
                    options: CaptionStyle.presetIDs,
                    selected: preset,
                    label: { StudioStyleCard.presetLabel($0) }
                ) { value in
                    model.updateStep(step.id, kind: .applyCaptionStyle(presetID: value))
                }

            case .export(let preset):
                StudioExportEditor(model: model, preset: preset)

            case .generateVideo(let options):
                StudioGenerateVideoEditor(model: model, step: step, options: options)

            case .cleanup, .bestTakes, .brandKit, .addTitle, .brandTemplate, .filter, .background, .autoZoom,
                 .trackFace, .transitions, .voiceEffect, .videoLayout, .aiEdit:
                StudioToolEditor(model: model, step: step)

            default:
                Text(AppLocalization.string(StudioCatalog.tool(for: step.kind.typeName).note, bundle: .module))
                    .dsFont(.sans, .regular, 12, lineHeight: 1.4)
                    .foregroundStyle(DS.Palette.ink(0.5))
            }
        }
        .padding(.top, 2)
    }

    // MARK: - Controls

    private func label(_ key: String.LocalizationValue) -> some View {
        Text(AppLocalization.string(key, bundle: .module))
            .dsFont(.mono, .medium, 10, letterSpacing: 0.12)
            .foregroundStyle(DS.Palette.ink(0.52))
    }

    private func slider(
        _ key: String.LocalizationValue,
        value: Double,
        range: ClosedRange<Double>,
        step: Double,
        format: String,
        set: @escaping (Double) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                label(key)
                Spacer(minLength: 0)
                Text(String(format: format, value))
                    .dsFont(.mono, .medium, 11)
                    .foregroundStyle(DS.Palette.ink(0.75))
                    .contentTransition(.numericText())
            }
            Slider(value: Binding(get: { value }, set: set), in: range, step: step)
                .tint(DS.Palette.lime)
        }
    }

    private func chips<Value: Hashable>(
        _ key: String.LocalizationValue,
        options: [Value],
        selected: Value,
        label text: @escaping (Value) -> String,
        set: @escaping (Value) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            label(key)
            FlowLayout(horizontalSpacing: 5, verticalSpacing: 5) {
                ForEach(options, id: \.self) { option in
                    let isOn = option == selected
                    Button {
                        set(option)
                    } label: {
                        Text(text(option))
                            .dsFont(.mono, .medium, 11)
                            .foregroundStyle(isOn ? DS.Palette.inkInverse : DS.Palette.ink(0.6))
                            .padding(.horizontal, 11)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(isOn ? DS.Palette.ink : DS.Palette.hairline(0.07))
                            )
                    }
                    .buttonStyle(.dsPress(radius: 10))
                    .animation(DS.Motion.snap, value: isOn)
                }
            }
        }
    }

    private func toggle(_ key: String.LocalizationValue, isOn: Bool, flip: @escaping () -> Void) -> some View {
        Toggle(isOn: Binding(get: { isOn }, set: { _ in flip() })) {
            Text(AppLocalization.string(key, bundle: .module))
                .dsFont(.sans, .medium, 13)
                .foregroundStyle(DS.Palette.ink(0.8))
        }
        .tint(DS.Palette.lime)
    }

    /// The filler-word list, as removable chips and a field to add more.
    private func words(_ options: CutWordsOptions) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            label("studio.param.words")

            FlowLayout(horizontalSpacing: 5, verticalSpacing: 5) {
                ForEach(options.words, id: \.self) { word in
                    Button {
                        var changed = options
                        changed.words.removeAll { $0 == word }
                        withAnimation(DS.Motion.snap) { model.updateStep(step.id, kind: .cutWords(changed)) }
                    } label: {
                        HStack(spacing: 4) {
                            Text(word)
                                .dsFont(.sans, .medium, 12)
                            Image(systemName: "xmark")
                                .font(.system(size: 8, weight: .bold))
                        }
                        .foregroundStyle(DS.Palette.ink(0.8))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(DS.Palette.accent(0.14)))
                    }
                    .buttonStyle(.dsPress(radius: 20))
                    .transition(.scale.combined(with: .opacity))
                }
            }

            HStack(spacing: 6) {
                TextField(AppLocalization.string("studio.param.addWord", bundle: .module), text: $newWord)
                    .dsFont(.sans, .regular, 13)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit { add(to: options) }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(DS.Palette.hairline(0.06)))

                Button { add(to: options) } label: {
                    Image(systemName: "plus")
                        .dsActionName("plus")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(DS.Palette.inkInverse)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(DS.Palette.lime))
                }
                .buttonStyle(.dsPressIcon)
            }
        }
    }

    private func add(to options: CutWordsOptions) {
        let word = newWord.trimmingCharacters(in: .whitespaces).lowercased()
        guard !word.isEmpty, !options.words.contains(word) else { return }
        var changed = options
        changed.words.append(word)
        withAnimation(DS.Motion.snap) { model.updateStep(step.id, kind: .cutWords(changed)) }
        newWord = ""
    }
}

// MARK: - JSON

/// The document itself, editable.
///
/// This panel is what makes "an AI can write workflows" concrete rather than a promise: paste what
/// any model produced, or copy this one into a conversation and ask for changes. Applying never
/// half-works — a document that does not read leaves the workflow exactly as it was.
struct StudioJSONSheet: View {
    @Bindable var model: WorkflowStudioModel
    let onClose: () -> Void

    @State private var text = ""
    @State private var failed = false
    @State private var shakes = 0
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    DSKicker(AppLocalization.string("studio.json", bundle: .module))
                    Text("studio.json.note", bundle: .module)
                        .dsFont(.sans, .regular, 11)
                        .foregroundStyle(DS.Palette.ink(0.56))
                }
                Spacer(minLength: 0)
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .dsActionName("xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(DS.Palette.ink(0.6))
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(DS.Palette.hairline(0.08)))
                }
                .buttonStyle(.dsPressIcon)
            }

            TextEditor(text: $text)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(DS.Palette.ink(0.85))
                .scrollContentBackground(.hidden)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(DS.Palette.hairline(0.05)))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(failed ? DS.Palette.accent : DS.Palette.hairline(0.08), lineWidth: failed ? 1.5 : 1)
                }
                .modifier(Shake(trigger: shakes))

            if failed {
                Text("studio.json.invalid", bundle: .module)
                    .dsFont(.sans, .regular, 11)
                    .foregroundStyle(DS.Palette.accent)
            }

            HStack(spacing: 8) {
                Button {
                    UIPasteboard.general.string = text
                    copied = true
                } label: {
                    Label(
                        copied ? AppLocalization.string("studio.json.copied", bundle: .module) : AppLocalization.string("studio.json.copy", bundle: .module),
                        systemImage: copied ? "checkmark" : "doc.on.doc"
                    )
                    .contentTransition(.symbolEffect(.replace))
                    .dsFont(.sans, .semibold, 13)
                    .foregroundStyle(DS.Palette.ink(0.85))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(DS.Palette.hairline(0.08)))
                }
                .buttonStyle(.dsPress(radius: 14))

                ShareLink(item: text) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(DS.Palette.ink(0.85))
                        .frame(width: 48, height: 46)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(DS.Palette.hairline(0.08)))
                }

                Button {
                    if model.apply(json: text) {
                        onClose()
                    } else {
                        failed = true
                        shakes += 1
                    }
                } label: {
                    Text("studio.json.apply", bundle: .module)
                        .dsFont(.sans, .semibold, 13)
                        .foregroundStyle(DS.Palette.inkInverse)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(DS.Palette.lime))
                }
                .buttonStyle(.dsPress(radius: 14))
            }
        }
        .padding(20)
        .background(DS.Palette.screen)
        .onAppear { text = model.json }
        .onChange(of: text) { failed = false; copied = false }
    }
}

/// A short horizontal shake, for a document that did not read. The same gesture a password field
/// makes, and for the same reason: it says "no" without a dialog.
private struct Shake: ViewModifier {
    let trigger: Int

    func body(content: Content) -> some View {
        content.keyframeAnimator(initialValue: 0.0, trigger: trigger) { view, offset in
            view.offset(x: offset)
        } keyframes: { _ in
            KeyframeTrack {
                CubicKeyframe(-8, duration: 0.06)
                CubicKeyframe(8, duration: 0.08)
                CubicKeyframe(-5, duration: 0.08)
                CubicKeyframe(0, duration: 0.1)
            }
        }
    }
}
