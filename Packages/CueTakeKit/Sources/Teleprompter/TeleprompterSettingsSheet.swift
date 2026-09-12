import DesignSystem
import SwiftUI

/// The prompter's settings panel. Docks to the bottom in portrait and to the right in landscape,
/// as the design's `tpSheet` does.
public struct TeleprompterSettingsSheet: View {
    @Bindable private var model: TeleprompterModel

    public init(model: TeleprompterModel) {
        self.model = model
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            presetRow
            tabRow
            sliderRows
            segmentedRows

            Text("teleprompter.hint", bundle: .module)
                .dsFont(.sans, .regular, 10)
                .foregroundStyle(DS.Palette.ink(0.3))
                .padding(.top, 8)
        }
        .padding(.horizontal, 17)
        .padding(.vertical, 15)
        .background {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(Color(hex: 0x121216, alpha: 0.86))
                )
        }
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(DS.Palette.hairline(0.13), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .dsEnter(.rise(duration: 0.35))
    }

    private var header: some View {
        HStack(spacing: 8) {
            DSKicker(String(localized: "teleprompter.title", bundle: .module), size: 9, color: DS.Palette.ink(0.45))
            Spacer(minLength: 0)
            Button {
                model.isSettingsOpen = false
            } label: {
                Text("✕")
                    .font(.system(size: 15))
                    .foregroundStyle(DS.Palette.ink(0.5))
            }
            .buttonStyle(.dsPress)
        }
        .padding(.bottom, 12)
    }

    private var presetRow: some View {
        HStack(spacing: 6) {
            ForEach([TeleprompterModel.Preset.compact, .band, .full, .corner], id: \.self) { preset in
                presetButton(preset)
            }
        }
        .padding(.bottom, 12)
    }

    private func presetButton(_ preset: TeleprompterModel.Preset) -> some View {
        let isOn = model.preset == preset
        let frame = model.presets[preset]
        return Button {
            model.apply(preset)
        } label: {
            VStack(spacing: 6) {
                // Glyph: a band showing where the panel sits vertically in the frame.
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(DS.Palette.ink(0.25), lineWidth: 1)
                    .frame(width: 30, height: 20)
                    .overlay(alignment: .top) {
                        if let frame {
                            Rectangle()
                                .fill(isOn ? DS.Palette.accent : DS.Palette.ink(0.6))
                                .frame(height: 20 * min(1, frame.height / 100))
                                .offset(y: 20 * frame.y / 100)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))

                Text(preset.label)
                    .dsFont(.sans, .medium, 10)
            }
            .foregroundStyle(isOn ? DS.Palette.accent : DS.Palette.ink(0.6))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .padding(.horizontal, 4)
            // Without this the row only responds on the preview shape and the label itself.
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.dsPress)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isOn ? DS.Palette.accent(0.18) : DS.Palette.hairline(0.06))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isOn ? DS.Palette.accent : .clear, lineWidth: 1)
        }
        .animation(DS.Easing.ease(0.25), value: isOn)
    }

    private var tabRow: some View {
        HStack(spacing: 6) {
            ForEach(TeleprompterModel.SettingsTab.allCases, id: \.self) { tab in
                let isOn = model.settingsTab == tab
                Button {
                    model.settingsTab = tab
                } label: {
                    Text(tab.label)
                        .dsFont(.sans, .medium, 12)
                        .foregroundStyle(isOn ? DS.Palette.inkInverse : DS.Palette.ink(0.6))
                        .padding(.horizontal, 13)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .fill(isOn ? DS.Palette.ink : DS.Palette.hairline(0.07))
                        )
                }
                .buttonStyle(.dsPress)
            }
            Spacer(minLength: 0)
        }
        .padding(.bottom, 10)
    }

    @ViewBuilder
    private var sliderRows: some View {
        switch model.settingsTab {
        case .layout:
            sliderRow(String(localized: "teleprompter.slider.textSize", bundle: .module), value: $model.textSize, in: 14...34, step: 1) {
                "\(Int(model.textSize))pt"
            }
            sliderRow(String(localized: "teleprompter.slider.width", bundle: .module), value: $model.frame.width, in: 26...96, step: 1, onEdit: {
                model.preset = .custom
                model.frame.x = min(model.frame.x, 98 - model.frame.width)
            }) {
                "\(Int(model.frame.width.rounded()))%"
            }
            sliderRow(String(localized: "teleprompter.slider.height", bundle: .module), value: $model.frame.height, in: 12...80, step: 1, onEdit: {
                model.preset = .custom
                model.frame.y = min(model.frame.y, 93 - model.frame.height)
            }) {
                "\(Int(model.frame.height.rounded()))%"
            }
            sliderRow(String(localized: "teleprompter.slider.opacity", bundle: .module), value: $model.opacity, in: 10...100, step: 1) {
                "\(Int(model.opacity))%"
            }
        case .flow:
            sliderRow(String(localized: "teleprompter.slider.speed", bundle: .module), value: $model.speed, in: 0...100, step: 1) {
                model.speedLabel
            }
            sliderRow(String(localized: "teleprompter.slider.lookAhead", bundle: .module), value: lookAheadBinding, in: 0...4, step: 1) {
                "\(model.lookAhead)w"
            }
        }
    }

    private var lookAheadBinding: Binding<Double> {
        Binding(
            get: { Double(model.lookAhead) },
            set: { model.lookAhead = Int($0.rounded()) }
        )
    }

    private func sliderRow(
        _ label: String,
        value: Binding<Double>,
        in range: ClosedRange<Double>,
        step: Double,
        onEdit: (() -> Void)? = nil,
        display: @escaping () -> String
    ) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .dsFont(.sans, .regular, 12)
                .foregroundStyle(DS.Palette.ink(0.55))
                .frame(width: 66, alignment: .leading)

            DSSlider(
                value: Binding(
                    get: { value.wrappedValue },
                    set: { newValue in
                        value.wrappedValue = newValue
                        onEdit?()
                    }
                ),
                in: range,
                step: step
            )

            Text(display())
                .dsFont(.mono, .medium, 11)
                .foregroundStyle(DS.Palette.ink)
                .frame(width: 38, alignment: .trailing)
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var segmentedRows: some View {
        switch model.settingsTab {
        case .layout:
            segmentedRow(
                String(localized: "teleprompter.row.align", bundle: .module),
                options: TeleprompterModel.Alignment.allCases,
                label: { $0.label },
                isOn: { model.alignment == $0 },
                select: { model.alignment = $0 }
            )
            segmentedRow(
                String(localized: "teleprompter.row.mirror", bundle: .module),
                options: [false, true],
                label: { $0 ? String(localized: "teleprompter.mirror.on", bundle: .module) : String(localized: "teleprompter.mirror.off", bundle: .module) },
                isOn: { model.isMirrored == $0 },
                select: { model.isMirrored = $0 }
            )
        case .flow:
            segmentedRow(
                String(localized: "teleprompter.row.highlight", bundle: .module),
                options: TeleprompterModel.HighlightMode.allCases,
                label: { $0.label },
                isOn: { model.mode == $0 },
                select: { model.mode = $0 }
            )
        }
    }

    /// Options stay typed; only their labels come from the catalog.
    private func segmentedRow<Option: Hashable>(
        _ label: String,
        options: [Option],
        label optionLabel: @escaping (Option) -> String,
        isOn: @escaping (Option) -> Bool,
        select: @escaping (Option) -> Void
    ) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .dsFont(.sans, .regular, 12)
                .foregroundStyle(DS.Palette.ink(0.55))
                .frame(width: 66, alignment: .leading)

            HStack(spacing: 5) {
                ForEach(options, id: \.self) { option in
                    DSPill(
                        optionLabel(option),
                        isOn: isOn(option),
                        fontSize: 11,
                        radius: 10,
                        verticalPadding: 8
                    ) {
                        select(option)
                    }
                }
            }
        }
        .padding(.vertical, 7)
    }
}
