import DesignSystem
import Domain
import SwiftUI

/// One background effect: when it runs, what goes behind the person, and how.
///
/// Time first, the same as a text or a picture: exact start and end in tenths, either end put
/// where the playhead is, or snapped to the clip or the whole video. Then the look, and the details
/// a look has — how blurred, how dark, how soft the edge around the person.
struct EffectInspector: View {
    @Bindable var model: EditorModel
    let effect: TimelineEffect
    let onClose: () -> Void

    /// The sliders' values while a finger is on them. A slider that re-rendered the clip on every
    /// step would start forty renders a second; the change is made when the finger lifts.
    @State private var draftStrength: Double?
    @State private var draftFeather: Double?

    private var settings: BackgroundSettings { effect.background ?? BackgroundSettings(style: .blur) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    timing
                    looks
                    details
                    actions
                }
                .padding(.bottom, 8)
            }
            .scrollIndicators(.hidden)
        }
        .padding(16)
        .frame(maxHeight: 360)
        .dsGlass(
            tint: DS.Palette.glassSheet(0.95),
            in: UnevenRoundedRectangle(topLeadingRadius: DS.Radius.sheet, topTrailingRadius: DS.Radius.sheet, style: .continuous),
            border: DS.Palette.hairline(0.12)
        )
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "person.crop.rectangle")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DS.Palette.inkInverse)
                .frame(width: 28, height: 28)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(EffectLane.tint))
            VStack(alignment: .leading, spacing: 1) {
                Text("editor.dock.background", bundle: .module)
                    .dsFont(.sans, .semibold, 14)
                    .foregroundStyle(DS.Palette.ink)
                Text(verbatim: "\(MediaTime(seconds: effect.start.seconds).preciseTimecode) – \(MediaTime(seconds: effect.end).preciseTimecode) · \(String(format: "%.1f", effect.duration.seconds)) s")
                    .dsFont(.mono, .medium, 10)
                    .foregroundStyle(DS.Palette.ink(0.45))
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
    }

    // MARK: - Timing

    private var timing: some View {
        VStack(alignment: .leading, spacing: 8) {
            DSKicker(String(localized: "editor.overlay.when", bundle: .module), size: 9, color: DS.Palette.ink(0.42))
            TimingReadout(start: effect.start.seconds, end: effect.end)
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    smallButton("editor.overlay.startHere", symbol: "arrow.right.to.line") {
                        model.setEffectEdge(effect.id, start: model.playhead, coalescing: "effect-start")
                    }
                    smallButton("editor.overlay.endHere", symbol: "arrow.left.to.line") {
                        model.setEffectEdge(effect.id, end: model.playhead, coalescing: "effect-end")
                    }
                    if let index = model.segmentAtPlayhead?.index {
                        smallButton("editor.effect.fitClip", symbol: "rectangle.center.inset.filled") {
                            let range = model.timelineRange(ofSegmentAt: index)
                            model.updateEffect(effect.id, coalescing: "effect-fit") {
                                $0.start = MediaTime(seconds: range.lowerBound)
                                $0.duration = MediaTime(seconds: range.upperBound - range.lowerBound)
                            }
                        }
                    }
                    smallButton("editor.tool.split", symbol: "scissors") {
                        withAnimation(DS.Motion.settle) { model.splitEffect(effect.id) }
                    }
                    smallButton("editor.effect.wholeVideo", symbol: "arrow.left.and.right") {
                        let length = model.duration
                        model.updateEffect(effect.id, coalescing: "effect-fit") {
                            $0.start = .zero
                            $0.duration = MediaTime(seconds: length)
                        }
                    }
                }
            }
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
        }
    }

    // MARK: - Look

    private var looks: some View {
        VStack(alignment: .leading, spacing: 8) {
            DSKicker(String(localized: "editor.effect.look", bundle: .module), size: 9, color: DS.Palette.ink(0.42))
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(ToolDock.backgroundChoices, id: \.self) { style in
                        let isOn = settings.style == style
                        Button {
                            withAnimation(DS.Motion.snap) {
                                model.updateBackground(effect.id) {
                                    $0.style = style
                                    if style == .color, $0.color == nil { $0.color = Self.colors[0] }
                                }
                            }
                        } label: {
                            VStack(spacing: 5) {
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .fill(ToolDock.swatch(style, color: settings.color))
                                    .frame(width: 44, height: 44)
                                    .overlay {
                                        Image(systemName: "person.fill")
                                            .font(.system(size: 16, weight: .semibold))
                                            .foregroundStyle(style == .white ? Color.black.opacity(0.75) : Color.white.opacity(0.9))
                                    }
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                                            .strokeBorder(isOn ? DS.Palette.lime : DS.Palette.hairline(0.12), lineWidth: isOn ? 2.5 : 1)
                                    }
                                Text(ToolDock.label(style))
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
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 12) {
            if settings.usesStrength {
                slider(
                    settings.style == .blur ? "editor.effect.blurAmount" : "editor.effect.dimAmount",
                    symbol: settings.style == .blur ? "drop.fill" : "moon.fill",
                    value: draftStrength ?? settings.strength,
                    onChange: { draftStrength = $0 },
                    onCommit: {
                        guard let value = draftStrength else { return }
                        model.updateBackground(effect.id, coalescing: "strength") { $0.strength = value }
                        draftStrength = nil
                    }
                )
            }

            slider(
                "editor.effect.feather",
                symbol: "circle.dotted",
                value: draftFeather ?? settings.feather,
                onChange: { draftFeather = $0 },
                onCommit: {
                    guard let value = draftFeather else { return }
                    model.updateBackground(effect.id, coalescing: "feather") { $0.feather = value }
                    draftFeather = nil
                }
            )

            if settings.style == .color {
                HStack(spacing: 8) {
                    ForEach(Array(Self.colors.enumerated()), id: \.offset) { _, color in
                        let isOn = settings.color.map { abs($0.red - color.red) < 0.02 && abs($0.green - color.green) < 0.02 && abs($0.blue - color.blue) < 0.02 } ?? false
                        Button {
                            model.updateBackground(effect.id, coalescing: "color") { $0.color = color }
                        } label: {
                            Circle()
                                .fill(Color(red: color.red, green: color.green, blue: color.blue))
                                .frame(width: 26, height: 26)
                                .overlay(Circle().stroke(isOn ? DS.Palette.lime : DS.Palette.hairline(0.2), lineWidth: isOn ? 2 : 1).padding(-3))
                        }
                        .buttonStyle(.dsPressIcon)
                    }
                    ColorPicker(
                        String(localized: "editor.effect.customColor", bundle: .module),
                        selection: Binding(
                            get: { settings.color.map { Color(red: $0.red, green: $0.green, blue: $0.blue) } ?? .black },
                            set: { value in
                                let resolved = value.resolve(in: EnvironmentValues())
                                model.updateBackground(effect.id, coalescing: "color") {
                                    $0.color = RGBAColor(red: Double(resolved.red), green: Double(resolved.green), blue: Double(resolved.blue))
                                }
                            }
                        ),
                        supportsOpacity: false
                    )
                    .labelsHidden()
                }
            }

            Button {
                model.updateBackground(effect.id, coalescing: "edges") { $0.fineEdges.toggle() }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: settings.fineEdges ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(settings.fineEdges ? DS.Palette.lime : DS.Palette.ink(0.4))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("editor.effect.fineEdges", bundle: .module)
                            .dsFont(.sans, .semibold, 12)
                            .foregroundStyle(DS.Palette.ink)
                        Text("editor.effect.fineEdges.note", bundle: .module)
                            .dsFont(.sans, .regular, 10)
                            .foregroundStyle(DS.Palette.ink(0.45))
                    }
                    Spacer(minLength: 0)
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(DS.Palette.hairline(0.06)))
            }
            .buttonStyle(.dsPress(radius: 12))
            .accessibilityAddTraits(settings.fineEdges ? .isSelected : [])
        }
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(role: .destructive) {
                withAnimation(DS.Motion.settle) { model.removeEffect(effect.id) }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "trash").font(.system(size: 11, weight: .semibold))
                    Text("editor.effect.remove", bundle: .module).dsFont(.sans, .semibold, 12)
                }
                .foregroundStyle(DS.Palette.accent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(DS.Palette.accent(0.12)))
            }
            .buttonStyle(.dsPress(radius: 12))

            Text("editor.background.note", bundle: .module)
                .dsFont(.sans, .regular, 10, lineHeight: 1.35)
                .foregroundStyle(DS.Palette.ink(0.4))
        }
    }

    // MARK: - Parts

    static let colors: [RGBAColor] = [
        RGBAColor(red: 0.1, green: 0.1, blue: 0.12),
        RGBAColor(red: 0.96, green: 0.94, blue: 0.9),
        RGBAColor(red: 0.2, green: 0.36, blue: 0.95),
        RGBAColor(red: 1, green: 0.42, blue: 0.62),
        RGBAColor(red: 1, green: 0.78, blue: 0.2),
    ]

    private func slider(
        _ key: String.LocalizationValue,
        symbol: String,
        value: Double,
        onChange: @escaping (Double) -> Void,
        onCommit: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(String(localized: key, bundle: .module))
                    .dsFont(.sans, .medium, 11)
                    .foregroundStyle(DS.Palette.ink(0.55))
                Spacer()
                Text(verbatim: "%\(Int((value * 100).rounded()))")
                    .dsFont(.mono, .medium, 10)
                    .foregroundStyle(DS.Palette.ink(0.7))
                    .contentTransition(.numericText())
            }
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 11))
                    .foregroundStyle(DS.Palette.ink(0.45))
                Slider(
                    value: Binding(get: { value }, set: onChange),
                    in: 0...1,
                    onEditingChanged: { editing in if !editing { onCommit() } }
                )
                .tint(EffectLane.tint)
            }
        }
    }

    private func timeStepper(_ key: String.LocalizationValue, value: Double, onStep: @escaping (Double) -> Void) -> some View {
        HStack(spacing: 0) {
            stepButton("minus") { onStep(-0.1) }
            VStack(spacing: 1) {
                Text(String(localized: key, bundle: .module))
                    .dsFont(.mono, .medium, 8)
                    .foregroundStyle(DS.Palette.ink(0.4))
                Text(verbatim: MediaTime(seconds: value).preciseTimecode)
                    .dsFont(.mono, .medium, 13)
                    .foregroundStyle(DS.Palette.ink)
                    .contentTransition(.numericText(value: value))
            }
            .frame(maxWidth: .infinity)
            stepButton("plus") { onStep(0.1) }
        }
        .padding(4)
        .background(Capsule().fill(DS.Palette.hairline(0.06)))
    }

    private func stepButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(DS.Palette.ink)
                .frame(width: 32, height: 32)
                .background(Circle().fill(DS.Palette.hairline(0.08)))
        }
        .buttonRepeatBehavior(.enabled)
        .buttonStyle(.dsPressIcon)
    }

    private func smallButton(_ key: String.LocalizationValue, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 10, weight: .semibold))
                Text(String(localized: key, bundle: .module)).dsFont(.sans, .medium, 11).lineLimit(1)
            }
            .foregroundStyle(DS.Palette.ink(0.85))
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Capsule().fill(DS.Palette.hairline(0.08)))
        }
        .buttonStyle(.dsPress(radius: 20))
    }
}
