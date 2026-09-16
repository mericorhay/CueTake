import DesignSystem
import Domain
import SwiftUI

/// Making a video from inside the editor: what, with which model, and where it goes.
///
/// The prompt is written in the bar at the top of the screen, like the AI's, because this panel
/// sits where the keyboard comes up. Everything else is a tap.
struct GeneratePanel: View {
    @Bindable var model: EditorModel
    @Binding var draft: String
    let onCompose: () -> Void

    @Namespace private var selection
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var options: GenerateVideoOptions { model.fittedGenerationOptions(model.generationDefaults) }
    private var preset: VideoModelPreset { options.modelPreset }
    private var hasKey: Bool { model.generationHasKey(preset.provider) }
    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && hasKey && !options.resolvedModel.isEmpty
    }

    /// The lengths worth offering as chips, from what the model accepts.
    private var lengths: [Double] {
        let all = preset.durations
        guard all.count > 6 else { return all }
        return [4, 5, 6, 8, 10, 15].filter { all.contains($0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            modelRow

            if !hasKey {
                Label {
                    Text("editor.generate.noKey \(preset.provider.displayName)", bundle: .module)
                        .dsFont(.sans, .medium, 12, lineHeight: 1.35)
                } icon: {
                    Image(systemName: "key.slash")
                }
                .foregroundStyle(DS.Palette.accentWarm)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if preset.isCustom {
                TextField(
                    preset.provider == .fal ? "fal-ai/…/text-to-video" : "owner/model",
                    text: Binding(
                        get: { model.generationDefaults.customModel },
                        set: { model.generationDefaults.customModel = $0 }
                    )
                )
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .dsFont(.mono, .medium, 12)
                .padding(.horizontal, 10)
                .frame(height: 38)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(DS.Palette.hairline(0.07)))
            }

            placementRow
            lengthRow

            HStack(spacing: 8) {
                Button(action: onCompose) {
                    Text(verbatim: draft.isEmpty ? String(localized: "editor.generate.placeholder", bundle: .module) : draft)
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
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(canSend ? DS.Palette.inkInverse : DS.Palette.ink(0.35))
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(canSend ? DS.Palette.lime : DS.Palette.hairline(0.1)))
                        .symbolEffect(.bounce, value: model.generationJobs.count)
                }
                .buttonStyle(.dsPressIcon)
                .disabled(!canSend)
                .accessibilityLabel(Text("editor.generate.send", bundle: .module))
            }

            Text("editor.generate.note \(Int(options.seconds))", bundle: .module)
                .dsFont(.sans, .regular, 10, lineHeight: 1.35)
                .foregroundStyle(DS.Palette.ink(0.42))

            if !model.generationJobs.isEmpty {
                VStack(spacing: 6) {
                    ForEach(model.generationJobs.reversed()) { job in
                        GenerationJobRow(model: model, job: job)
                            .transition(.asymmetric(
                                insertion: .move(edge: .top).combined(with: .opacity),
                                removal: .opacity.combined(with: .scale(scale: 0.95))
                            ))
                    }
                }
                .animation(reduceMotion ? .easeOut(duration: 0.2) : DS.Motion.settle, value: model.generationJobs.map(\.id))
            }
        }
        .animation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.38, dampingFraction: 0.8), value: model.generationDefaults)
        .animation(DS.Motion.snap, value: model.generationPlacement)
    }

    private func send() {
        guard canSend else { return }
        model.generateClip(prompt: draft)
        draft = ""
    }

    // MARK: Rows

    private var modelRow: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(VideoModelPreset.catalog) { item in
                    let isOn = item.id == model.generationDefaults.preset
                    Button {
                        withAnimation(DS.Motion.snap) {
                            model.generationDefaults.preset = item.id
                            model.generationDefaults = model.fittedGenerationOptions(model.generationDefaults)
                        }
                    } label: {
                        HStack(spacing: 5) {
                            if model.generationHasKey(item.provider) {
                                Circle().fill(isOn ? DS.Palette.inkInverse : DS.Palette.lime).frame(width: 5, height: 5)
                            }
                            Text(verbatim: item.title)
                                .dsFont(.sans, .semibold, 12)
                        }
                        .foregroundStyle(isOn ? DS.Palette.inkInverse : DS.Palette.ink(model.generationHasKey(item.provider) ? 0.8 : 0.4))
                        .padding(.horizontal, 11)
                        .frame(height: 34)
                        .background {
                            if isOn {
                                Capsule().fill(DS.Palette.lime).matchedGeometryEffect(id: "model", in: selection)
                            } else {
                                Capsule().fill(DS.Palette.hairline(0.07))
                            }
                        }
                    }
                    .buttonStyle(.dsPress(radius: 17))
                }
            }
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
    }

    private var placementRow: some View {
        HStack(spacing: 6) {
            ForEach(GenerationPlacement.allCases, id: \.self) { place in
                let isOn = model.generationPlacement == place
                Button {
                    withAnimation(DS.Motion.snap) { model.generationPlacement = place }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Label(
                            String(localized: place == .broll ? "editor.generate.broll" : "editor.generate.clip", bundle: .module),
                            systemImage: place == .broll ? "square.2.layers.3d" : "film"
                        )
                        .dsFont(.sans, .semibold, 12)
                        Text(place == .broll ? "editor.generate.broll.note" : "editor.generate.clip.note", bundle: .module)
                            .dsFont(.sans, .regular, 10)
                            .opacity(0.7)
                            .lineLimit(1)
                    }
                    .foregroundStyle(isOn ? DS.Palette.ink : DS.Palette.ink(0.55))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(isOn ? DS.Palette.lime.opacity(0.14) : DS.Palette.hairline(0.05))
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(isOn ? DS.Palette.lime.opacity(0.7) : .clear, lineWidth: 1.2)
                    }
                }
                .buttonStyle(.dsPress(radius: 12))
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
    }

    private var lengthRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "timer")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(DS.Palette.ink(0.45))
            ForEach(lengths, id: \.self) { value in
                let isOn = abs(options.seconds - value) < 0.01
                Button {
                    withAnimation(DS.Motion.snap) { model.generationDefaults.seconds = value }
                } label: {
                    Text(verbatim: "\(Int(value)) s")
                        .dsFont(.mono, .medium, 11)
                        .foregroundStyle(isOn ? DS.Palette.inkInverse : DS.Palette.ink(0.65))
                        .padding(.horizontal, 10)
                        .frame(height: 30)
                        .background(Capsule().fill(isOn ? DS.Palette.ink : DS.Palette.hairline(0.07)))
                }
                .buttonStyle(.dsPress(radius: 15))
            }
            Spacer(minLength: 0)
            if preset.makesAudio {
                Image(systemName: "waveform")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DS.Palette.lime)
                    .accessibilityLabel(Text("editor.generate.makesSound", bundle: .module))
            }
        }
    }
}

/// One video on its way.
private struct GenerationJobRow: View {
    @Bindable var model: EditorModel
    let job: ClipGenerationJob

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                switch job.phase {
                case .working:
                    DSDevelopingFilm(started: job.started, progress: job.progress, showsClock: false)
                case .done:
                    if let thumbnail = job.thumbnail {
                        Image(uiImage: thumbnail).resizable().scaledToFill().transition(.blurReplace)
                    } else {
                        DS.Palette.lime.opacity(0.3)
                    }
                case .failed:
                    DS.Palette.accentWarm.opacity(0.2)
                        .overlay {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(DS.Palette.accentWarm)
                        }
                }
            }
            .frame(width: 34, height: 48)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: job.prompt)
                    .dsFont(.sans, .medium, 12)
                    .foregroundStyle(DS.Palette.ink(0.85))
                    .lineLimit(1)
                Group {
                    switch job.phase {
                    case .working:
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            Text(verbatim: "\(job.options.modelPreset.title) · \(DSDevelopingFilm.elapsed(since: job.started, now: context.date))")
                        }
                    case .done:
                        Text("editor.generate.arrived", bundle: .module)
                    case .failed:
                        Text(verbatim: job.failure ?? "")
                            .lineLimit(2)
                    }
                }
                .dsFont(.mono, .medium, 10)
                .foregroundStyle(job.phase == .failed ? DS.Palette.accentWarm : job.phase == .done ? DS.Palette.lime : DS.Palette.ink(0.45))
            }

            Spacer(minLength: 4)

            switch job.phase {
            case .working:
                iconButton("xmark", label: "editor.generate.cancel") { model.cancelGeneration(job.id) }
            case .failed:
                iconButton("arrow.clockwise", label: "editor.generate.retry") { model.retryGeneration(job.id) }
                iconButton("xmark", label: "editor.generate.dismiss") { model.dismissGeneration(job.id) }
            case .done:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(DS.Palette.lime)
                    .transition(.symbolEffect(.drawOn))
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(DS.Palette.hairline(0.05)))
        .animation(DS.Motion.settle, value: job.phase)
        .sensoryFeedback(.success, trigger: job.phase) { _, new in new == .done }
        .sensoryFeedback(.error, trigger: job.phase) { _, new in new == .failed }
    }

    private func iconButton(_ symbol: String, label: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(DS.Motion.settle) { action() }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(DS.Palette.ink(0.7))
                .frame(width: 30, height: 30)
                .background(Circle().fill(DS.Palette.hairline(0.08)))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.dsPressIcon)
        .accessibilityLabel(Text(label, bundle: .module))
    }
}
