import DesignSystem
import Domain
import SwiftUI
import UniformTypeIdentifiers

/// The chrome every effect panel shares: a header with its name and times, the times read out with
/// the playhead shortcuts, the effect's own controls, and cutting or removing it.
struct EffectPanelShell<Content: View>: View {
    @Bindable var model: EditorModel
    let effect: TimelineEffect
    let title: String
    let symbol: String
    let tint: Color
    let onClose: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DS.Palette.inkInverse)
                    .frame(width: 28, height: 28)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(tint))
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: title)
                        .dsFont(.sans, .semibold, 14)
                        .foregroundStyle(DS.Palette.ink)
                    Text(verbatim: "\(MediaTime(seconds: effect.start.seconds).preciseTimecode) – \(MediaTime(seconds: effect.end).preciseTimecode)")
                        .dsFont(.mono, .medium, 10)
                        .foregroundStyle(DS.Palette.ink(0.56))
                        .contentTransition(.numericText())
                }
                Spacer(minLength: 0)
                Button(action: onClose) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(DS.Palette.inkInverse)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(DS.Palette.lime))
                }
                .buttonStyle(.dsPressIcon)
                .accessibilityLabel(Text("editor.done", bundle: .module))
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    TimingReadout(start: effect.start.seconds, end: effect.end)
                    ScrollView(.horizontal) {
                        HStack(spacing: 8) {
                            chip("editor.overlay.startHere", symbol: "arrow.right.to.line") {
                                model.setEffectEdge(effect.id, start: model.playhead, coalescing: "effect-start")
                            }
                            chip("editor.overlay.endHere", symbol: "arrow.left.to.line") {
                                model.setEffectEdge(effect.id, end: model.playhead, coalescing: "effect-end")
                            }
                            chip("editor.tool.split", symbol: "scissors") {
                                withAnimation(DS.Motion.settle) { model.splitEffect(effect.id) }
                            }
                            chip("editor.effect.wholeVideo", symbol: "arrow.left.and.right") {
                                let length = model.duration
                                model.updateEffect(effect.id, coalescing: "effect-fit") {
                                    $0.start = .zero
                                    $0.duration = MediaTime(seconds: length)
                                }
                            }
                            chip("editor.effect.delete", symbol: "trash", destructive: true) {
                                let id = effect.id
                                onClose()
                                withAnimation(DS.Motion.settle) { model.removeEffect(id) }
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                    .scrollClipDisabled()

                    content()
                }
                .padding(.bottom, 10)
            }
            .scrollIndicators(.hidden)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsGlass(
            tint: DS.Palette.glassSheet(0.95),
            in: UnevenRoundedRectangle(topLeadingRadius: DS.Radius.sheet, topTrailingRadius: DS.Radius.sheet, style: .continuous),
            border: DS.Palette.hairline(0.12)
        )
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func chip(_ key: String.LocalizationValue, symbol: String, destructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 10, weight: .semibold))
                Text(String(localized: key, bundle: .module)).dsFont(.sans, .medium, 11).lineLimit(1)
            }
            .foregroundStyle(destructive ? DS.Palette.accent : DS.Palette.ink(0.85))
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Capsule().fill(destructive ? DS.Palette.accent(0.12) : DS.Palette.hairline(0.08)))
        }
        .buttonStyle(.dsPress(radius: 20))
    }
}

/// A slider with its name and value, the one every effect panel uses.
struct EffectSlider: View {
    let key: String.LocalizationValue
    let symbol: String
    let value: Double
    let range: ClosedRange<Double>
    let tint: Color
    let format: (Double) -> String
    let onChange: (Double) -> Void
    var onCommit: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: symbol)
                    .font(.system(size: 11))
                    .foregroundStyle(DS.Palette.ink(0.56))
                Text(String(localized: key, bundle: .module))
                    .dsFont(.sans, .medium, 11)
                    .foregroundStyle(DS.Palette.ink(0.6))
                Spacer()
                Text(verbatim: format(value))
                    .dsFont(.mono, .medium, 10)
                    .foregroundStyle(DS.Palette.ink(0.75))
                    .contentTransition(.numericText())
            }
            Slider(
                value: Binding(get: { value }, set: onChange),
                in: range,
                onEditingChanged: { editing in if !editing { onCommit() } }
            )
            .tint(tint)
        }
    }
}

/// A filter: the look, how much of it, and the adjustments a look is fine-tuned with. Every change
/// is on the picture as the finger moves.
struct FilterInspector: View {
    @Bindable var model: EditorModel
    let effect: TimelineEffect
    let onClose: () -> Void

    @State private var pickingTable = false
    @State private var refused = false

    private var settings: FilterSettings { effect.filter ?? FilterSettings(look: .natural) }

    var body: some View {
        EffectPanelShell(
            model: model,
            effect: effect,
            title: FilterPresets.label(settings.look),
            symbol: "camera.filters",
            tint: EffectLane.filterTint,
            onClose: onClose
        ) {
            VStack(alignment: .leading, spacing: 14) {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(FilterPresets.looks, id: \.self) { look in
                            let isOn = settings.look == look
                            Button {
                                withAnimation(DS.Motion.snap) {
                                    model.updateFilter(effect.id, coalescing: "filter-look") { $0.look = look }
                                }
                            } label: {
                                VStack(spacing: 5) {
                                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                                        .fill(FilterPresets.swatch(look))
                                        .frame(width: 48, height: 48)
                                        .overlay {
                                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                                .strokeBorder(isOn ? DS.Palette.lime : DS.Palette.hairline(0.12), lineWidth: isOn ? 2.5 : 1)
                                        }
                                    Text(FilterPresets.label(look))
                                        .dsFont(.sans, .medium, 10)
                                        .foregroundStyle(isOn ? DS.Palette.ink : DS.Palette.ink(0.55))
                                }
                            }
                            .buttonStyle(.dsPress(radius: 9))
                            .accessibilityAddTraits(isOn ? .isSelected : [])
                        }
                    }
                    .padding(.vertical, 2)
                }
                .scrollIndicators(.hidden)
                .scrollClipDisabled()

                if settings.look != .natural || settings.lut != nil {
                    slider("editor.filter.intensity", "circle.lefthalf.filled", \.intensity, 0...1) { "%\(Int(($0 * 100).rounded()))" }
                }
                slider("editor.filter.brightness", "sun.max", \.brightness, -1...1, signed: true)
                slider("editor.filter.contrast", "circle.righthalf.filled", \.contrast, -1...1, signed: true)
                slider("editor.filter.saturation", "drop.halffull", \.saturation, -1...1, signed: true)
                slider("editor.filter.warmth", "thermometer.medium", \.warmth, -1...1, signed: true)
                slider("editor.filter.vignette", "circle.dashed", \.vignette, 0...1) { "%\(Int(($0 * 100).rounded()))" }
                slider("editor.filter.sharpness", "triangle", \.sharpness, 0...1) { "%\(Int(($0 * 100).rounded()))" }
                lookUpTable
            }
        }
        .fileImporter(
            isPresented: $pickingTable,
            allowedContentTypes: [UTType(filenameExtension: "cube") ?? .data]
        ) { result in
            guard case .success(let url) = result else { return }
            withAnimation(DS.Motion.settle) {
                refused = !model.useLookUpTable(at: url, on: effect.id)
            }
        }
    }

    /// A grade bought as a file. Shown last: it is the one thing here that is not a slider, and
    /// most videos never use one.
    @ViewBuilder
    private var lookUpTable: some View {
        if let table = settings.lut {
            HStack(spacing: 10) {
                Image(systemName: "swatchpalette.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(EffectLane.filterTint)
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: table.name)
                        .dsFont(.sans, .semibold, 12)
                        .foregroundStyle(DS.Palette.ink)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text("editor.filter.lut.on \(table.size)", bundle: .module)
                        .dsFont(.sans, .regular, 10)
                        .foregroundStyle(DS.Palette.ink(0.56))
                }
                Spacer(minLength: 0)
                Button {
                    withAnimation(DS.Motion.settle) { model.removeLookUpTable(from: effect.id) }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(DS.Palette.ink(0.6))
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(DS.Palette.hairline(0.08)))
                }
                .buttonStyle(.dsPressIcon)
                .accessibilityLabel(Text("editor.filter.lut.remove", bundle: .module))
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(DS.Palette.hairline(0.06)))
        } else {
            Button { pickingTable = true } label: {
                Label {
                    Text("editor.filter.lut.add", bundle: .module)
                } icon: {
                    Image(systemName: "swatchpalette")
                }
                .dsFont(.sans, .medium, 12)
                .foregroundStyle(DS.Palette.ink(0.75))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(DS.Palette.hairline(0.07)))
            }
            .buttonStyle(.dsPress(radius: 14))
            if refused {
                Text("editor.filter.lut.refused", bundle: .module)
                    .dsFont(.sans, .regular, 10)
                    .foregroundStyle(DS.Palette.accentWarm)
            }
        }
    }

    private func slider(
        _ key: String.LocalizationValue,
        _ symbol: String,
        _ path: WritableKeyPath<FilterSettings, Double>,
        _ range: ClosedRange<Double>,
        signed: Bool = false,
        format: ((Double) -> String)? = nil
    ) -> some View {
        EffectSlider(
            key: key,
            symbol: symbol,
            value: settings[keyPath: path],
            range: range,
            tint: EffectLane.filterTint,
            format: format ?? { value in signed ? String(format: "%+d", Int((value * 100).rounded())) : "\(Int((value * 100).rounded()))" },
            onChange: { value in
                model.updateFilter(effect.id, coalescing: "filter-\(symbol)") { $0[keyPath: path] = value }
            }
        )
    }
}

/// A sound effect: which one, how strong, the pitch and the level. Strength and pitch are applied
/// when the finger lifts, since each is a new render of the voice; the level is instant.
struct SoundInspector: View {
    @Bindable var model: EditorModel
    let effect: TimelineEffect
    let onClose: () -> Void

    @State private var draftAmount: Double?
    @State private var draftPitch: Double?

    private var settings: SoundSettings { effect.sound ?? SoundSettings(preset: .clean) }

    var body: some View {
        EffectPanelShell(
            model: model,
            effect: effect,
            title: SoundPresets.label(settings.preset),
            symbol: "waveform",
            tint: EffectLane.soundTint,
            onClose: onClose
        ) {
            VStack(alignment: .leading, spacing: 14) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                    ForEach(SoundPresets.presets, id: \.self) { preset in
                        let isOn = settings.preset == preset
                        Button {
                            withAnimation(DS.Motion.snap) {
                                model.updateSound(effect.id, coalescing: "sound-preset") {
                                    $0.preset = preset
                                    $0.pitch = SoundSettings.defaultPitch(for: preset)
                                }
                            }
                        } label: {
                            VStack(spacing: 5) {
                                Image(systemName: SoundPresets.symbol(preset))
                                    .font(.system(size: 15, weight: .medium))
                                Text(SoundPresets.label(preset))
                                    .dsFont(.sans, .medium, 10)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                            }
                            .foregroundStyle(isOn ? DS.Palette.inkInverse : DS.Palette.ink(0.85))
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                            .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(isOn ? EffectLane.soundTint : DS.Palette.hairline(0.07)))
                        }
                        .buttonStyle(.dsPress(radius: 13))
                        .accessibilityAddTraits(isOn ? .isSelected : [])
                    }
                }

                if settings.preset != .clean, settings.preset != .deep, settings.preset != .chipmunk {
                    EffectSlider(
                        key: "editor.sound.amount",
                        symbol: "slider.horizontal.3",
                        value: draftAmount ?? settings.amount,
                        range: 0...1,
                        tint: EffectLane.soundTint,
                        format: { "%\(Int(($0 * 100).rounded()))" },
                        onChange: { draftAmount = $0 },
                        onCommit: {
                            guard let value = draftAmount else { return }
                            model.updateSound(effect.id, coalescing: "sound-amount") { $0.amount = value }
                            draftAmount = nil
                        }
                    )
                }
                EffectSlider(
                    key: "editor.sound.pitch",
                    symbol: "music.note",
                    value: draftPitch ?? settings.pitch,
                    range: -12...12,
                    tint: EffectLane.soundTint,
                    format: { String(format: "%+.0f", $0) },
                    onChange: { draftPitch = ($0 * 2).rounded() / 2 },
                    onCommit: {
                        guard let value = draftPitch else { return }
                        model.updateSound(effect.id, coalescing: "sound-pitch") { $0.pitch = value }
                        draftPitch = nil
                    }
                )
                EffectSlider(
                    key: "editor.sound.volume",
                    symbol: "speaker.wave.2",
                    value: settings.volume,
                    range: -24...12,
                    tint: EffectLane.soundTint,
                    format: { String(format: "%+.0f dB", $0) },
                    onChange: { value in
                        model.updateSound(effect.id, coalescing: "sound-volume") { $0.volume = value.rounded() }
                    }
                )
                Text("editor.sound.note", bundle: .module)
                    .dsFont(.sans, .regular, 10, lineHeight: 1.35)
                    .foregroundStyle(DS.Palette.ink(0.56))
            }
        }
    }
}
