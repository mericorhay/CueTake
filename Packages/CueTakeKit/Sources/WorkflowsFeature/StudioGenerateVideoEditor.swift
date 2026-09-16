import DesignSystem
import Domain
import Persistence
import SwiftUI

/// The "Generate video" tool's settings: which model, what to make, and in what shape.
///
/// Only what the chosen model accepts is offered — Veo's lengths are not Seedance's — so a
/// setting on screen is a setting the model will honour.
struct StudioGenerateVideoEditor: View {
    @Bindable var model: WorkflowStudioModel
    let step: WorkflowStep
    let options: GenerateVideoOptions

    @State private var newPrompt = ""
    @State private var keyPresent = true

    private var preset: VideoModelPreset { options.modelPreset }

    private func update(_ change: (inout GenerateVideoOptions) -> Void) {
        var changed = options
        change(&changed)
        // Settings the new model cannot take move to the nearest it can.
        let fitted = changed.modelPreset
        changed.seconds = fitted.duration(nearest: changed.seconds)
        changed.aspect = fitted.aspect(nearest: changed.aspect)
        changed.resolution = fitted.resolution(nearest: changed.resolution)
        model.updateStep(step.id, kind: .generateVideo(changed))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            modelPicker
            if !keyPresent { missingKey }
            if preset.isCustom { customModelField }
            prompts
            styleField
            shape
        }
        .onAppear { keyPresent = ProviderKeyStore().hasKey(for: preset.provider) }
        .onChange(of: options.preset) { keyPresent = ProviderKeyStore().hasKey(for: preset.provider) }
    }

    // MARK: Parts

    private var modelPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            label("studio.param.model")
            FlowLayout(horizontalSpacing: 5, verticalSpacing: 5) {
                ForEach(VideoModelPreset.catalog) { item in
                    let isOn = item.id == options.preset
                    Button {
                        withAnimation(DS.Motion.snap) { update { $0.preset = item.id } }
                    } label: {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(verbatim: item.title)
                                .dsFont(.sans, .semibold, 12)
                            Text(verbatim: item.provider.displayName)
                                .dsFont(.mono, .medium, 8)
                                .opacity(0.6)
                        }
                        .foregroundStyle(isOn ? DS.Palette.inkInverse : DS.Palette.ink(0.75))
                        .padding(.horizontal, 11)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(isOn ? DS.Palette.lime : DS.Palette.hairline(0.07))
                        )
                    }
                    .buttonStyle(.dsPress(radius: 10))
                }
            }
        }
    }

    private var missingKey: some View {
        Label {
            Text("studio.generate.noKey \(preset.provider.displayName)", bundle: .module)
                .dsFont(.sans, .medium, 12, lineHeight: 1.35)
        } icon: {
            Image(systemName: "key.slash")
        }
        .foregroundStyle(DS.Palette.accentWarm)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(DS.Palette.accentWarm.opacity(0.1)))
    }

    private var customModelField: some View {
        VStack(alignment: .leading, spacing: 6) {
            label("studio.param.modelID")
            TextField(
                preset.provider == .fal ? "fal-ai/kling-video/v2.1/master/text-to-video" : "owner/model",
                text: Binding(get: { options.customModel }, set: { value in update { $0.customModel = value } })
            )
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .dsFont(.mono, .medium, 12)
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(DS.Palette.hairline(0.06)))
            Text("studio.generate.modelIDNote", bundle: .module)
                .dsFont(.sans, .regular, 10, lineHeight: 1.35)
                .foregroundStyle(DS.Palette.ink(0.42))
        }
    }

    private var prompts: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                label("studio.param.prompts")
                Spacer(minLength: 0)
                if !options.prompts.isEmpty {
                    Text(verbatim: "\(options.prompts.count)")
                        .dsFont(.mono, .medium, 10)
                        .foregroundStyle(DS.Palette.ink(0.5))
                }
            }

            ForEach(Array(options.prompts.enumerated()), id: \.offset) { index, prompt in
                HStack(alignment: .top, spacing: 8) {
                    Text(verbatim: "\(index + 1)")
                        .dsFont(.mono, .medium, 10)
                        .foregroundStyle(DS.Palette.ink(0.4))
                        .frame(width: 18, alignment: .trailing)
                        .padding(.top, 2)
                    Text(verbatim: prompt)
                        .dsFont(.sans, .regular, 12, lineHeight: 1.35)
                        .foregroundStyle(DS.Palette.ink(0.85))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button {
                        withAnimation(DS.Motion.snap) { update { $0.prompts.remove(at: index) } }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(DS.Palette.ink(0.5))
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.dsPressIcon)
                }
                .padding(.vertical, 4)
                .transition(.opacity)
            }

            if options.prompts.isEmpty {
                Text("studio.generate.promptsFromSections", bundle: .module)
                    .dsFont(.sans, .regular, 11, lineHeight: 1.35)
                    .foregroundStyle(DS.Palette.ink(0.42))
            }

            HStack(alignment: .bottom, spacing: 6) {
                // Pasting several lines adds one video per line: a list of 60 topics goes in at once.
                TextField(String(localized: "studio.param.addPrompt", bundle: .module), text: $newPrompt, axis: .vertical)
                    .lineLimit(1...5)
                    .dsFont(.sans, .regular, 13)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(DS.Palette.hairline(0.06)))

                Button(action: addPrompts) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(DS.Palette.inkInverse)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(DS.Palette.lime))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.dsPressIcon)
                .disabled(newPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private var styleField: some View {
        VStack(alignment: .leading, spacing: 6) {
            label("studio.param.styleNote")
            TextField(
                String(localized: "studio.param.styleNote.placeholder", bundle: .module),
                text: Binding(get: { options.styleNote }, set: { value in update { $0.styleNote = value } }),
                axis: .vertical
            )
            .lineLimit(1...3)
            .dsFont(.sans, .regular, 12)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(DS.Palette.hairline(0.06)))
        }
    }

    @ViewBuilder
    private var shape: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                label("studio.param.length")
                Spacer(minLength: 0)
                Text(verbatim: "\(Int(options.seconds)) s")
                    .dsFont(.mono, .medium, 11)
                    .foregroundStyle(DS.Palette.ink(0.75))
                    .contentTransition(.numericText())
            }
            if preset.durations.count > 6, let low = preset.durations.first, let high = preset.durations.last {
                Slider(
                    value: Binding(get: { options.seconds }, set: { value in update { $0.seconds = value.rounded() } }),
                    in: low...high,
                    step: 1
                )
                .tint(DS.Palette.lime)
            } else {
                chips(preset.durations, selected: options.seconds, text: { "\(Int($0)) s" }) { value in
                    update { $0.seconds = value }
                }
            }
        }

        VStack(alignment: .leading, spacing: 6) {
            label("studio.param.aspect")
            chips(preset.aspects, selected: options.aspect, text: { $0 }) { value in update { $0.aspect = value } }
        }

        if preset.resolutions.count > 1 {
            VStack(alignment: .leading, spacing: 6) {
                label("studio.param.resolution")
                chips(preset.resolutions, selected: options.resolution, text: { $0 }) { value in update { $0.resolution = value } }
            }
        }

        if preset.makesAudio || preset.isCustom {
            Toggle(isOn: Binding(get: { options.audio }, set: { value in update { $0.audio = value } })) {
                Text("studio.param.generateAudio", bundle: .module)
                    .dsFont(.sans, .medium, 13)
                    .foregroundStyle(DS.Palette.ink(0.8))
            }
            .tint(DS.Palette.lime)
        }

        VStack(alignment: .leading, spacing: 6) {
            label("studio.param.parallel")
            chips([1, 2, 3, 4, 5], selected: options.parallel, text: { "\($0)" }) { value in update { $0.parallel = value } }
        }
    }

    // MARK: Controls

    private func addPrompts() {
        let lines = newPrompt
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !lines.isEmpty else { return }
        withAnimation(DS.Motion.snap) { update { $0.prompts.append(contentsOf: lines) } }
        newPrompt = ""
    }

    private func label(_ key: String.LocalizationValue) -> some View {
        Text(String(localized: key, bundle: .module))
            .dsFont(.mono, .medium, 9, letterSpacing: 0.12)
            .foregroundStyle(DS.Palette.ink(0.38))
    }

    private func chips<Value: Hashable>(
        _ options: [Value],
        selected: Value,
        text: @escaping (Value) -> String,
        set: @escaping (Value) -> Void
    ) -> some View {
        FlowLayout(horizontalSpacing: 5, verticalSpacing: 5) {
            ForEach(options, id: \.self) { option in
                let isOn = option == selected
                Button {
                    withAnimation(DS.Motion.snap) { set(option) }
                } label: {
                    Text(verbatim: text(option))
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
            }
        }
    }
}
