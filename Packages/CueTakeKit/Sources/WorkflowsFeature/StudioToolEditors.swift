import DesignSystem
import Domain
import SwiftUI

/// The details of the studio's own tools inside a workflow: a title, a brand template, a look, a
/// camera move. Each shows the same choices the studio offers, by name, in the viewer's language.
struct StudioToolEditor: View {
    @Bindable var model: WorkflowStudioModel
    let step: WorkflowStep

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch step.kind {
            case .cleanup(let options):
                toggle("studio.param.cleanPauses", isOn: options.pauses) { var o = options; o.pauses.toggle(); set(.cleanup(o)) }
                toggle("studio.param.cleanFillers", isOn: options.fillers) { var o = options; o.fillers.toggle(); set(.cleanup(o)) }
                toggle("studio.param.cleanRepeats", isOn: options.repeats) { var o = options; o.repeats.toggle(); set(.cleanup(o)) }
                toggle("studio.param.cleanRestarts", isOn: options.restarts) { var o = options; o.restarts.toggle(); set(.cleanup(o)) }

            case .brandKit(let options):
                toggle("studio.param.brandColors", isOn: options.colors) { var o = options; o.colors.toggle(); set(.brandKit(o)) }
                toggle("studio.param.brandLogo", isOn: options.logo) { var o = options; o.logo.toggle(); set(.brandKit(o)) }
                note("studio.param.brandNote")

            case .addTitle(let options):
                field("studio.param.titleText", text: options.text, prompt: "studio.param.titleAuto") { value in
                    var o = options; o.text = value; set(.addTitle(o))
                }
                moment(options.moment) { var o = options; o.moment = $0; set(.addTitle(o)) }
                if options.moment == .at {
                    slider("studio.param.at", value: options.seconds, range: 0...60, step: 0.5, format: "%.1f s") { var o = options; o.seconds = $0; set(.addTitle(o)) }
                }
                slider("studio.param.duration", value: options.duration, range: 0.5...10, step: 0.5, format: "%.1f s") { var o = options; o.duration = $0; set(.addTitle(o)) }
                slider("studio.param.height", value: options.y, range: 0.06...0.94, step: 0.02, format: "%.2f") { var o = options; o.y = $0; set(.addTitle(o)) }
                slider("studio.param.size", value: options.scale, range: 0.5...2.5, step: 0.1, format: "%.1f×") { var o = options; o.scale = $0; set(.addTitle(o)) }
                chips("studio.param.animation", options: ["pop", "fade", "slideUp", "none"], selected: options.animation, prefix: "studio.animation.") {
                    var o = options; o.animation = $0; set(.addTitle(o))
                }
                toggle("studio.param.behind", isOn: options.behind) { var o = options; o.behind.toggle(); set(.addTitle(o)) }

            case .brandTemplate(let options):
                chips("studio.param.templateStyle", options: WorkflowTemplateStyle.names, selected: options.style, prefix: "studio.template.") {
                    var o = options; o.style = $0; set(.brandTemplate(o))
                }
                ForEach(WorkflowTemplateStyle.slots(of: options.style), id: \.self) { slot in
                    field(
                        String.LocalizationValue(stringLiteral: "studio.slot." + slot),
                        text: options.lines[slot] ?? "",
                        prompt: "studio.param.lineEmpty"
                    ) { value in
                        var o = options; o.lines[slot] = value; set(.brandTemplate(o))
                    }
                }
                field("studio.param.color", text: options.color, prompt: "studio.param.colorBrand") { value in
                    var o = options; o.color = value; set(.brandTemplate(o))
                }
                moment(options.moment) { var o = options; o.moment = $0; set(.brandTemplate(o)) }
                if options.moment == .at {
                    slider("studio.param.at", value: options.seconds, range: 0...60, step: 0.5, format: "%.1f s") { var o = options; o.seconds = $0; set(.brandTemplate(o)) }
                }
                slider("studio.param.duration", value: options.duration, range: 1...12, step: 0.5, format: "%.1f s") { var o = options; o.duration = $0; set(.brandTemplate(o)) }

            case .filter(let options):
                chips("studio.param.look", options: FilterSettings.Look.allCases.map(\.rawValue), selected: options.look, prefix: "studio.look.") {
                    var o = options; o.look = $0; set(.filter(o))
                }
                slider("studio.param.intensity", value: options.intensity, range: 0...1, step: 0.05, format: "%.2f") { var o = options; o.intensity = $0; set(.filter(o)) }
                target(options.target) { var o = options; o.target = $0; set(.filter(o)) }

            case .background(let options):
                chips("studio.param.backgroundStyle", options: ClipBackground.allCases.map(\.rawValue), selected: options.style, prefix: "studio.background.") {
                    var o = options; o.style = $0; set(.background(o))
                }
                slider("studio.param.strength", value: options.strength, range: 0...1, step: 0.05, format: "%.2f") { var o = options; o.strength = $0; set(.background(o)) }
                if options.style == "color" {
                    field("studio.param.color", text: options.color, prompt: "studio.param.colorHex") { value in
                        var o = options; o.color = value; set(.background(o))
                    }
                }
                target(options.target) { var o = options; o.target = $0; set(.background(o)) }

            case .autoZoom(let options):
                chips("studio.param.zoomStyle", options: ZoomStepOptions.Style.allCases.map(\.rawValue), selected: options.style.rawValue, prefix: "studio.zoom.") {
                    var o = options; o.style = ZoomStepOptions.Style(rawValue: $0) ?? .mixed; set(.autoZoom(o))
                }
                slider("studio.param.zoomAmount", value: options.amount, range: 0.04...0.35, step: 0.01, format: "%.2f") { var o = options; o.amount = $0; set(.autoZoom(o)) }
                slider("studio.param.spacing", value: options.spacing, range: 2...15, step: 0.5, format: "%.1f s") { var o = options; o.spacing = $0; set(.autoZoom(o)) }

            case .trackFace(let options):
                slider("studio.param.closeness", value: options.closeness, range: 0.08...0.2, step: 0.01, format: "%.2f") { var o = options; o.closeness = $0; set(.trackFace(o)) }
                note("tool.trackFace.note")

            case .transitions(let options):
                chips("studio.param.transition", options: Self.transitionKinds, selected: options.kind, prefix: "studio.transition.") {
                    var o = options; o.kind = $0; set(.transitions(o))
                }
                slider("studio.param.duration", value: options.seconds, range: 0.2...2, step: 0.05, format: "%.2f s") { var o = options; o.seconds = $0; set(.transitions(o)) }
                chips("studio.param.placement", options: TransitionStepOptions.Placement.allCases.map(\.rawValue), selected: options.placement.rawValue, prefix: "studio.placement.") {
                    var o = options; o.placement = TransitionStepOptions.Placement(rawValue: $0) ?? .sections; set(.transitions(o))
                }

            case .voiceEffect(let options):
                chips("studio.param.soundPreset", options: SoundSettings.Preset.allCases.map(\.rawValue), selected: options.preset, prefix: "studio.sound.") {
                    var o = options; o.preset = $0; set(.voiceEffect(o))
                }
                slider("studio.param.amount", value: options.amount, range: 0...1, step: 0.05, format: "%.2f") { var o = options; o.amount = $0; set(.voiceEffect(o)) }
                target(options.target) { var o = options; o.target = $0; set(.voiceEffect(o)) }

            case .videoLayout(let options):
                chips("studio.param.layout", options: VideoLayoutOptions.layouts, selected: options.layout, prefix: "studio.layout.") {
                    set(.videoLayout(VideoLayoutOptions(layout: $0)))
                }

            case .aiEdit(let options):
                field("studio.param.instruction", text: options.instruction, prompt: "studio.param.instructionHint", lines: 3) { value in
                    set(.aiEdit(AIEditOptions(instruction: value)))
                }
                note("studio.param.aiEditNote")

            case .soundDesign(let options):
                chips("studio.param.sfxLevel", options: SoundDesignOptions.Intensity.allCases.map(\.rawValue), selected: options.intensity.rawValue, prefix: "studio.sfx.") {
                    var o = options; o.intensity = SoundDesignOptions.Intensity(rawValue: $0) ?? .normal; set(.soundDesign(o))
                }
                toggle("studio.param.sfxWhoosh", isOn: options.whooshes) { var o = options; o.whooshes.toggle(); set(.soundDesign(o)) }
                toggle("studio.param.sfxPop", isOn: options.pops) { var o = options; o.pops.toggle(); set(.soundDesign(o)) }
                toggle("studio.param.sfxImpact", isOn: options.impacts) { var o = options; o.impacts.toggle(); set(.soundDesign(o)) }
                toggle("studio.param.sfxDing", isOn: options.dings) { var o = options; o.dings.toggle(); set(.soundDesign(o)) }
                toggle("studio.param.sfxKeywords", isOn: options.keywords) { var o = options; o.keywords.toggle(); set(.soundDesign(o)) }
                note("studio.param.sfxNote")

            case .applyStyle(let options):
                chips("studio.param.style", options: VideoStyle.allCases.map(\.rawValue), selected: options.style.rawValue, prefix: "style.") {
                    set(.applyStyle(ApplyStyleOptions(style: VideoStyle(rawValue: $0) ?? .boldBusiness)))
                }
                note(String.LocalizationValue(stringLiteral: "style." + options.style.rawValue + ".note"))

            case .bestTakes:
                note("tool.bestTakes.note")

            default:
                EmptyView()
            }
        }
    }

    /// The transitions worth choosing from in a workflow: one of each family and direction people use.
    static let transitionKinds = ["crossfade", "fadeBlack", "fadeWhite", "slideLeft", "slideUp", "pushLeft", "wipeLeft", "zoomIn", "zoomOut"]

    private func set(_ kind: WorkflowStepKind) {
        model.updateStep(step.id, kind: kind)
    }

    // MARK: - Controls

    private func label(_ key: String.LocalizationValue) -> some View {
        Text(AppLocalization.string(key, bundle: .module))
            .dsFont(.mono, .medium, 10, letterSpacing: 0.12)
            .foregroundStyle(DS.Palette.ink(0.52))
    }

    private func note(_ key: String.LocalizationValue) -> some View {
        Text(AppLocalization.string(key, bundle: .module))
            .dsFont(.sans, .regular, 12, lineHeight: 1.4)
            .foregroundStyle(DS.Palette.ink(0.5))
            .fixedSize(horizontal: false, vertical: true)
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
            Slider(value: Binding(get: { min(max(value, range.lowerBound), range.upperBound) }, set: set), in: range, step: step)
                .tint(DS.Palette.lime)
        }
    }

    /// Named choices: each value's name comes from `prefix + value` in the catalog.
    private func chips(
        _ key: String.LocalizationValue,
        options: [String],
        selected: String,
        prefix: String,
        set: @escaping (String) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            label(key)
            FlowLayout(horizontalSpacing: 5, verticalSpacing: 5) {
                ForEach(options, id: \.self) { option in
                    let isOn = option == selected
                    Button {
                        set(option)
                    } label: {
                        Text(AppLocalization.string(String.LocalizationValue(stringLiteral: prefix + option), bundle: .module))
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

    private func moment(_ selected: WorkflowMoment, set: @escaping (WorkflowMoment) -> Void) -> some View {
        chips("studio.param.moment", options: WorkflowMoment.allCases.map(\.rawValue), selected: selected.rawValue, prefix: "studio.moment.") {
            set(WorkflowMoment(rawValue: $0) ?? .start)
        }
    }

    private func target(_ selected: String, set: @escaping (String) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            label("studio.param.target")
            FlowLayout(horizontalSpacing: 5, verticalSpacing: 5) {
                ForEach(WorkflowTarget.options, id: \.self) { option in
                    let isOn = option == selected
                    Button {
                        set(option)
                    } label: {
                        Text(StudioCatalog.targetLabel(option))
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

    private func field(
        _ key: String.LocalizationValue,
        text: String,
        prompt: String.LocalizationValue,
        lines: Int = 1,
        set: @escaping (String) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            label(key)
            TextField(
                AppLocalization.string(prompt, bundle: .module),
                text: Binding(get: { text }, set: set),
                axis: .vertical
            )
            .lineLimit(lines...max(lines, 6))
            .dsFont(.sans, .regular, 13)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(DS.Palette.hairline(0.06)))
        }
    }
}
