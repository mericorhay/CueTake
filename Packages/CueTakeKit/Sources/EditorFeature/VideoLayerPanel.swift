import DesignSystem
import Domain
import SwiftUI

/// Controls for the selected movie layer. Presets make the first split-screen result immediate;
/// the timeline and placement controls remain available for precise work.
struct VideoLayerPanel: View {
    @Bindable var model: EditorModel
    let onOpenPlacementEditor: () -> Void
    let onClose: () -> Void

    private var layer: VideoLayer? { model.selectedVideoLayerValue }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "rectangle.split.2x1").foregroundStyle(DS.Palette.lime)
                Text("editor.videoLayers", bundle: .module).dsFont(.sans, .semibold, 15)
                Spacer()
                Button(action: onClose) { Image(systemName: "xmark").frame(width: 40, height: 40) }
                    .buttonStyle(.dsPressIcon)
                    .accessibilityLabel(Text("editor.panel.close", bundle: .module))
            }
            if let layer {
                Text(layer.title).dsFont(.mono, .medium, 10).foregroundStyle(DS.Palette.ink(0.5))
                Button(action: onOpenPlacementEditor) {
                    Label(String(localized: "editor.video.placement", bundle: .module), systemImage: "arrow.up.left.and.arrow.down.right")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                }
                .foregroundStyle(DS.Palette.inkInverse)
                .background(Capsule().fill(DS.Palette.ink))
                .buttonStyle(.dsPress(radius: 20))
                HStack(spacing: 8) {
                    Image(systemName: layer.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .foregroundStyle(DS.Palette.ink(0.5))
                    Text("editor.video.volume", bundle: .module)
                        .dsFont(.mono, .medium, 9)
                        .foregroundStyle(DS.Palette.ink(0.45))
                    Slider(
                        value: Binding(
                            get: { model.selectedVideoLayerValue?.volume ?? layer.volume },
                            set: { value in model.updateVideoLayer(layer.id, coalescing: "video-layer-volume-\(layer.id)") { $0.volume = value } }
                        ),
                        in: 0...1
                    )
                    .tint(DS.Palette.lime)
                    .disabled(layer.isMuted)
                    .opacity(layer.isMuted ? 0.35 : 1)
                    Text(verbatim: "\(Int(layer.volume * 100))%")
                        .dsFont(.mono, .medium, 10)
                        .foregroundStyle(DS.Palette.ink(0.6))
                        .frame(width: 36, alignment: .trailing)
                }
                Text("editor.video.layout", bundle: .module).dsFont(.sans, .medium, 11).foregroundStyle(DS.Palette.ink(0.5))
                HStack(spacing: 7) {
                    layoutButton(.sideBySide, "rectangle.split.2x1")
                    layoutButton(.pictureInPicture, "rectangle.inset.filled")
                    layoutButton(.stacked, "rectangle.split.1x2")
                    layoutButton(.grid, "square.grid.2x2")
                }
                HStack(spacing: 7) {
                    nudgeButton("arrow.left", label: "editor.video.nudge.left", x: -0.03)
                    nudgeButton("arrow.right", label: "editor.video.nudge.right", x: 0.03)
                    nudgeButton("arrow.up", label: "editor.video.nudge.up", y: -0.03)
                    nudgeButton("arrow.down", label: "editor.video.nudge.down", y: 0.03)
                    Button {
                        model.addVideoKeyframe(to: layer.id)
                    } label: {
                        Label(String(localized: "editor.video.keyframe", bundle: .module), systemImage: "diamond.fill")
                            .frame(maxWidth: .infinity).padding(.vertical, 10)
                    }
                    .foregroundStyle(DS.Palette.inkInverse)
                    .background(Capsule().fill(AIPalette.blue))
                    .buttonStyle(.dsPress(radius: 20))
                }
                HStack(spacing: 9) {
                    toggle("editor.video.mute", symbol: layer.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill", isOn: layer.isMuted) {
                        model.updateVideoLayer(layer.id) { $0.isMuted.toggle() }
                    }
                    toggle("editor.video.hide", symbol: layer.isHidden ? "eye.slash.fill" : "eye.fill", isOn: layer.isHidden) {
                        model.updateVideoLayer(layer.id) { $0.isHidden.toggle() }
                    }
                    Button {
                        model.removeVideoLayer(layer.id)
                        onClose()
                    } label: {
                        Label(String(localized: "editor.video.remove", bundle: .module), systemImage: "trash")
                            .frame(maxWidth: .infinity).padding(.vertical, 10)
                    }
                    .foregroundStyle(DS.Palette.accent)
                    .background(Capsule().fill(DS.Palette.accent.opacity(0.12)))
                    .buttonStyle(.dsPress(radius: 20))
                }
                Text("editor.video.hint", bundle: .module)
                    .dsFont(.sans, .regular, 11, lineHeight: 1.3)
                    .foregroundStyle(DS.Palette.ink(0.45))
            } else {
                Text("editor.video.selectHint", bundle: .module)
                    .dsFont(.sans, .regular, 13)
                    .foregroundStyle(DS.Palette.ink(0.6))
            }
        }
        .padding(15)
        .dsGlass(tint: DS.Palette.glassSheet(0.92), in: RoundedRectangle(cornerRadius: 22), border: DS.Palette.lime.opacity(0.35))
    }

    private func layoutButton(_ layout: VideoLayout, _ symbol: String) -> some View {
        Button {
            withAnimation(DS.Motion.settle) { model.applyVideoLayout(layout) }
        } label: {
            Image(systemName: symbol).frame(maxWidth: .infinity).padding(.vertical, 11)
        }
        .foregroundStyle(DS.Palette.ink)
        .background(RoundedRectangle(cornerRadius: 11).fill(DS.Palette.hairline(0.08)))
        .buttonStyle(.dsPress(radius: 11))
        .accessibilityLabel(Text(layoutLabel(layout)))
    }

    private func nudgeButton(_ symbol: String, label: String.LocalizationValue, x: Double = 0, y: Double = 0) -> some View {
        Button {
            guard let layer else { return }
            model.nudgeVideoLayer(layer.id, x: x, y: y)
        } label: {
            Image(systemName: symbol).frame(width: 35, height: 35)
        }
        .foregroundStyle(DS.Palette.ink)
        .background(Circle().fill(DS.Palette.hairline(0.08)))
        .buttonStyle(.dsPressIcon)
        .accessibilityLabel(Text(String(localized: label, bundle: .module)))
    }

    private func toggle(_ key: String.LocalizationValue, symbol: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(String(localized: key, bundle: .module), systemImage: symbol)
                .frame(maxWidth: .infinity).padding(.vertical, 10)
        }
        .foregroundStyle(isOn ? DS.Palette.inkInverse : DS.Palette.ink(0.8))
        .background(Capsule().fill(isOn ? DS.Palette.lime : DS.Palette.hairline(0.08)))
        .buttonStyle(.dsPress(radius: 20))
    }

    private func layoutLabel(_ layout: VideoLayout) -> String {
        switch layout {
        case .sideBySide: String(localized: "editor.video.layout.sideBySide", bundle: .module)
        case .stacked: String(localized: "editor.video.layout.stacked", bundle: .module)
        case .pictureInPicture: String(localized: "editor.video.layout.pip", bundle: .module)
        case .grid: String(localized: "editor.video.layout.grid", bundle: .module)
        }
    }
}
