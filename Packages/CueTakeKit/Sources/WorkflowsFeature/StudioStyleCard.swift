import DesignSystem
import Domain
import SwiftUI

/// The look, chosen apart from the structure.
///
/// Separate because they change separately. The same three-point structure goes out as a loud
/// karaoke reel on one platform and as a clean 4K cut on another, and a workflow that tied the
/// two together would have to be copied to change either.
struct StudioStyleCard: View {
    @Bindable var model: WorkflowStudioModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var style: WorkflowStyle { model.definition.style }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                DSKicker(String(localized: "studio.style", bundle: .module), size: 10, color: DS.Palette.ink(0.45))
                Spacer(minLength: 0)
                Toggle(isOn: binding(\.captions)) {
                    Text("studio.style.captions", bundle: .module)
                        .dsFont(.sans, .medium, 12)
                        .foregroundStyle(DS.Palette.ink(0.7))
                }
                .toggleStyle(.switch)
                .tint(DS.Palette.lime)
                .fixedSize(horizontal: true, vertical: false)
            }

            if style.captions {
                HStack(spacing: 8) {
                    ForEach(["pop", "clean", "karaoke"], id: \.self) { preset in
                        presetTile(preset)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))

                row("studio.style.position", options: ["top", "middle", "bottom"], selected: style.captionPosition) {
                    model.definition.style.captionPosition = $0
                } label: { Self.positionLabel($0) }
            }

            row(
                "studio.style.aspect",
                options: VideoFormat.AspectRatio.allCases,
                selected: style.aspect
            ) {
                model.definition.style.aspect = $0
            } label: { Self.aspectLabel($0) }

            row(
                "studio.style.resolution",
                options: VideoFormat.Resolution.allCases,
                selected: style.resolution
            ) { value in
                model.definition.style.resolution = value
                if !model.definition.style.format.isPhysicallyPlausible {
                    model.definition.style.frameRate = 30
                }
            } label: { $0.label }

            row(
                "studio.style.frameRate",
                options: VideoFormat.frameRateChoices,
                selected: style.frameRate
            ) {
                model.definition.style.frameRate = $0
            } label: { "\($0)" }
        }
        .padding(16)
        .dsCard(radius: DS.Radius.cardLarge)
        .animation(reduceMotion ? nil : DS.Motion.settle, value: style)
    }

    /// A tiny rendering of the caption look, not its name. Nobody chooses a caption style by
    /// reading "karaoke"; they choose it by seeing it.
    private func presetTile(_ preset: String) -> some View {
        let isOn = style.captionPreset == preset

        return Button {
            model.definition.style.captionPreset = preset
        } label: {
            VStack(spacing: 7) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(DS.Palette.camera)
                    switch preset {
                    case "karaoke":
                        (Text("SAY ").foregroundStyle(DS.Palette.lime) + Text("IT").foregroundStyle(.white))
                            .font(.system(size: 13, weight: .black))
                    case "clean":
                        Text("Say it")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(RoundedRectangle(cornerRadius: 4).fill(.black.opacity(0.55)))
                    default:
                        Text("SAY IT")
                            .font(.system(size: 13, weight: .heavy))
                            .foregroundStyle(.white)
                            .shadow(color: .black, radius: 0, x: 1, y: 1)
                            .rotationEffect(.degrees(-3))
                    }
                }
                .frame(height: 52)

                Text(preset.capitalized)
                    .dsFont(.sans, .medium, 11)
                    .foregroundStyle(isOn ? DS.Palette.ink : DS.Palette.ink(0.5))
            }
            .padding(6)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(DS.Palette.hairline(isOn ? 0.1 : 0.03))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isOn ? DS.Palette.lime : DS.Palette.hairline(0.07), lineWidth: isOn ? 2 : 1)
            }
            .scaleEffect(isOn && !reduceMotion ? 1.03 : 1)
            .animation(DS.Motion.bloom, value: isOn)
        }
        .buttonStyle(.dsPress(radius: 14))
    }

    private func row<Value: Hashable>(
        _ key: String.LocalizationValue,
        options: [Value],
        selected: Value,
        set: @escaping (Value) -> Void,
        label: @escaping (Value) -> String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(String(localized: key, bundle: .module))
                .dsFont(.mono, .medium, 9, letterSpacing: 0.12)
                .foregroundStyle(DS.Palette.ink(0.38))

            HStack(spacing: 5) {
                ForEach(options, id: \.self) { option in
                    let isOn = option == selected
                    Button {
                        set(option)
                    } label: {
                        Text(label(option))
                            .dsFont(.mono, .medium, 11)
                            .foregroundStyle(isOn ? DS.Palette.inkInverse : DS.Palette.ink(0.6))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(isOn ? DS.Palette.ink : DS.Palette.hairline(0.06))
                            )
                    }
                    .buttonStyle(.dsPress(radius: 10))
                }
            }
        }
    }

    private func binding(_ keyPath: WritableKeyPath<WorkflowStyle, Bool>) -> Binding<Bool> {
        Binding(
            get: { model.definition.style[keyPath: keyPath] },
            set: { model.definition.style[keyPath: keyPath] = $0 }
        )
    }

    static func positionLabel(_ value: String) -> String {
        switch value {
        case "top": String(localized: "studio.style.top", bundle: .module)
        case "middle": String(localized: "studio.style.middle", bundle: .module)
        default: String(localized: "studio.style.bottom", bundle: .module)
        }
    }

    static func aspectLabel(_ value: VideoFormat.AspectRatio) -> String {
        switch value {
        case .portrait9x16: "9:16"
        case .landscape16x9: "16:9"
        case .square1x1: "1:1"
        }
    }
}
