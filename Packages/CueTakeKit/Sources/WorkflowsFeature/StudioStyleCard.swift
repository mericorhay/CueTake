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
                DSKicker(AppLocalization.string("studio.style", bundle: .module), size: 10, color: DS.Palette.ink(0.56))
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
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(CaptionStyle.presetIDs, id: \.self) { preset in
                            presetTile(preset)
                                .frame(width: 84)
                        }
                    }
                }
                .scrollIndicators(.hidden)
                .scrollClipDisabled()
                .transition(.opacity.combined(with: .move(edge: .top)))

                row("studio.style.position", options: ["top", "middle", "bottom"], selected: style.captionPosition) {
                    model.definition.style.placeCaption(named: $0)
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
                        (Text("studio.style.preview.karaokeLead", bundle: .module).foregroundStyle(DS.Palette.lime)
                            + Text("studio.style.preview.karaokeTail", bundle: .module).foregroundStyle(.white))
                            .font(.system(size: 13, weight: .black))
                    case "clean":
                        Text("studio.style.preview.clean", bundle: .module)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(RoundedRectangle(cornerRadius: 4).fill(.black.opacity(0.55)))
                    default:
                        Text("studio.style.preview.bold", bundle: .module)
                            .font(.system(size: 13, weight: .heavy))
                            .foregroundStyle(.white)
                            .shadow(color: .black, radius: 0, x: 1, y: 1)
                            .rotationEffect(.degrees(-3))
                    }
                }
                .frame(height: 52)

                Text(Self.presetLabel(preset))
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
            Text(AppLocalization.string(key, bundle: .module))
                .dsFont(.mono, .medium, 10, letterSpacing: 0.12)
                .foregroundStyle(DS.Palette.ink(0.52))

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
        case "top": AppLocalization.string("studio.style.top", bundle: .module)
        case "middle": AppLocalization.string("studio.style.middle", bundle: .module)
        default: AppLocalization.string("studio.style.bottom", bundle: .module)
        }
    }

    static func presetLabel(_ preset: String) -> String {
        AppLocalization.string(String.LocalizationValue(stringLiteral: "studio.style.preset." + preset), bundle: .module)
    }

    static func aspectLabel(_ value: VideoFormat.AspectRatio) -> String {
        switch value {
        case .portrait9x16: "9:16"
        case .landscape16x9: "16:9"
        case .square1x1: "1:1"
        case .portrait4x5: "4:5"
        }
    }
}
