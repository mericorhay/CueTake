import DesignSystem
import Domain
import SwiftUI

/// Everything about one added video: when it plays, which part of it, where it sits, how loud.
///
/// Time first, the same as a text, a picture or a background: exact start and end in tenths, either
/// end put where the playhead is, a cut at the playhead. It used to offer only a position, so a
/// video could be placed anywhere in the frame but not told when to come in or when to leave.
struct VideoLayerPanel: View {
    @Bindable var model: EditorModel
    let onOpenPlacementEditor: () -> Void
    let onClose: () -> Void

    private var layer: VideoLayer? { model.selectedVideoLayerValue }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if let layer {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        timing(layer)
                        placement(layer)
                        sound(layer)
                        actions(layer)
                    }
                    .padding(.bottom, 8)
                }
                .scrollIndicators(.hidden)
            }
        }
        .padding(16)
        .frame(maxHeight: 380)
        .dsGlass(
            tint: DS.Palette.glassSheet(0.95),
            in: UnevenRoundedRectangle(topLeadingRadius: DS.Radius.sheet, topTrailingRadius: DS.Radius.sheet, style: .continuous),
            border: DS.Palette.hairline(0.12)
        )
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "rectangle.inset.filled")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DS.Palette.inkInverse)
                .frame(width: 28, height: 28)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(VideoLayerLane.tint))
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: layer?.title ?? "")
                    .dsFont(.sans, .semibold, 14)
                    .foregroundStyle(DS.Palette.ink)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let layer {
                    Text(verbatim: "\(MediaTime(seconds: layer.start.seconds).preciseTimecode) – \(MediaTime(seconds: layer.end).preciseTimecode) · \(String(format: "%.1f", layer.duration)) s")
                        .dsFont(.mono, .medium, 10)
                        .foregroundStyle(DS.Palette.ink(0.5))
                        .contentTransition(.numericText())
                }
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

    private func timing(_ layer: VideoLayer) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            DSKicker(String(localized: "editor.overlay.when", bundle: .module), size: 9, color: DS.Palette.ink(0.42))
            HStack(spacing: 8) {
                timeStepper("editor.overlay.start", value: layer.start.seconds) { delta in
                    model.setVideoLayerStartEdge(layer.id, to: layer.start.seconds + delta)
                }
                timeStepper("editor.overlay.end", value: layer.end) { delta in
                    model.setVideoLayerEnd(layer.id, to: layer.end + delta)
                }
            }
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    smallButton("editor.overlay.startHere", symbol: "arrow.right.to.line") {
                        model.setVideoLayerStartEdge(layer.id, to: model.playhead)
                    }
                    smallButton("editor.overlay.endHere", symbol: "arrow.left.to.line") {
                        model.setVideoLayerEnd(layer.id, to: model.playhead)
                    }
                    smallButton("editor.video.moveHere", symbol: "arrow.left.and.right") {
                        model.moveVideoLayer(layer.id, to: model.playhead)
                    }
                    smallButton("editor.tool.split", symbol: "scissors", enabled: model.canSplitVideoLayer(layer.id)) {
                        withAnimation(DS.Motion.settle) { model.splitVideoLayer(layer.id) }
                    }
                }
            }
            .scrollIndicators(.hidden)
            .scrollClipDisabled()

            // Which part of its own file plays: the same length, a different stretch of the video.
            timeStepper("editor.video.sourceStart", value: layer.sourceRange.start.seconds) { delta in
                model.setVideoLayerSourceStart(layer.id, to: layer.sourceRange.start.seconds + delta)
            }
        }
    }

    // MARK: - Placement

    private func placement(_ layer: VideoLayer) -> some View {
        let current = layer.placement(at: model.playhead)
        return VStack(alignment: .leading, spacing: 10) {
            DSKicker(String(localized: "editor.video.where", bundle: .module), size: 9, color: DS.Palette.ink(0.42))

            Button(action: onOpenPlacementEditor) {
                Label(String(localized: "editor.video.placement", bundle: .module), systemImage: "arrow.up.left.and.arrow.down.right")
                    .dsFont(.sans, .semibold, 13)
                    .foregroundStyle(DS.Palette.inkInverse)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(Capsule().fill(DS.Palette.ink))
            }
            .buttonStyle(.dsPress(radius: 20))

            HStack(spacing: 7) {
                layoutButton(.pictureInPicture, "rectangle.inset.filled")
                layoutButton(.sideBySide, "rectangle.split.2x1")
                layoutButton(.stacked, "rectangle.split.1x2")
                layoutButton(.grid, "square.grid.2x2")
            }

            slider("editor.video.size", symbol: "square.resize", value: current.width, range: 0.1...1) { value in
                model.setVideoLayerPlacement(layer.id, Self.resized(current, width: value))
            }
            slider("editor.video.opacity", symbol: "circle.lefthalf.filled", value: current.opacity, range: 0.05...1) { value in
                var next = current
                next.opacity = value
                model.setVideoLayerPlacement(layer.id, next)
            }

            HStack(spacing: 7) {
                nudgeButton("arrow.left", label: "editor.video.nudge.left", x: -0.02)
                nudgeButton("arrow.right", label: "editor.video.nudge.right", x: 0.02)
                nudgeButton("arrow.up", label: "editor.video.nudge.up", y: -0.02)
                nudgeButton("arrow.down", label: "editor.video.nudge.down", y: 0.02)
                Spacer(minLength: 0)
                Button {
                    model.addVideoKeyframe(to: layer.id)
                } label: {
                    Label(String(localized: "editor.video.keyframe", bundle: .module), systemImage: "diamond.fill")
                        .dsFont(.sans, .semibold, 12)
                        .foregroundStyle(DS.Palette.ink)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(DS.Palette.hairline(0.1)))
                }
                .buttonStyle(.dsPress(radius: 20))
            }
        }
    }

    /// The same shape at another width, around the same centre.
    static func resized(_ placement: VideoPlacement, width: Double) -> VideoPlacement {
        var next = placement
        let centerX = placement.x + placement.width / 2
        let centerY = placement.y + placement.height / 2
        let ratio = placement.height / max(placement.width, 0.01)
        next.width = min(max(width, 0.1), 1)
        next.height = min(max(next.width * ratio, 0.1), 1)
        next.x = centerX - next.width / 2
        next.y = centerY - next.height / 2
        return next
    }

    // MARK: - Sound and actions

    private func sound(_ layer: VideoLayer) -> some View {
        HStack(spacing: 10) {
            Button {
                model.updateVideoLayer(layer.id) { $0.isMuted.toggle() }
            } label: {
                Image(systemName: layer.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(layer.isMuted ? DS.Palette.inkInverse : DS.Palette.ink)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(layer.isMuted ? DS.Palette.accent : DS.Palette.hairline(0.08)))
            }
            .buttonStyle(.dsPressIcon)
            .accessibilityLabel(Text("editor.video.mute", bundle: .module))
            Slider(
                value: Binding(
                    get: { model.selectedVideoLayerValue?.volume ?? layer.volume },
                    set: { value in model.updateVideoLayer(layer.id, coalescing: "video-layer-volume-\(layer.id)") { $0.volume = value } }
                ),
                in: 0...1
            )
            .tint(VideoLayerLane.tint)
            .disabled(layer.isMuted)
            .opacity(layer.isMuted ? 0.35 : 1)
            Text(verbatim: "%\(Int((layer.volume * 100).rounded()))")
                .dsFont(.mono, .medium, 10)
                .foregroundStyle(DS.Palette.ink(0.6))
                .frame(width: 38, alignment: .trailing)
        }
    }

    private func actions(_ layer: VideoLayer) -> some View {
        HStack(spacing: 8) {
            Button {
                model.updateVideoLayer(layer.id) { $0.isHidden.toggle() }
            } label: {
                Label(String(localized: "editor.video.hide", bundle: .module), systemImage: layer.isHidden ? "eye.slash.fill" : "eye.fill")
                    .dsFont(.sans, .semibold, 12)
                    .foregroundStyle(layer.isHidden ? DS.Palette.inkInverse : DS.Palette.ink(0.85))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(Capsule().fill(layer.isHidden ? DS.Palette.lime : DS.Palette.hairline(0.08)))
            }
            .buttonStyle(.dsPress(radius: 20))

            Button(role: .destructive) {
                let id = layer.id
                onClose()
                withAnimation(DS.Motion.settle) { model.removeVideoLayer(id) }
            } label: {
                Label(String(localized: "editor.video.remove", bundle: .module), systemImage: "trash")
                    .dsFont(.sans, .semibold, 12)
                    .foregroundStyle(DS.Palette.accent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(Capsule().fill(DS.Palette.accent(0.12)))
            }
            .buttonStyle(.dsPress(radius: 20))
        }
    }

    // MARK: - Parts

    private func layoutButton(_ layout: VideoLayout, _ symbol: String) -> some View {
        Button {
            withAnimation(DS.Motion.settle) { model.applyVideoLayout(layout) }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(DS.Palette.ink)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(DS.Palette.hairline(0.08)))
        }
        .buttonStyle(.dsPress(radius: 11))
        .accessibilityLabel(Text(layoutLabel(layout)))
    }

    private func nudgeButton(_ symbol: String, label: String.LocalizationValue, x: Double = 0, y: Double = 0) -> some View {
        Button {
            guard let layer else { return }
            model.nudgeVideoLayer(layer.id, x: x, y: y)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(DS.Palette.ink)
                .frame(width: 38, height: 38)
                .background(Circle().fill(DS.Palette.hairline(0.08)))
        }
        .buttonRepeatBehavior(.enabled)
        .buttonStyle(.dsPressIcon)
        .accessibilityLabel(Text(String(localized: label, bundle: .module)))
    }

    private func slider(
        _ key: String.LocalizationValue,
        symbol: String,
        value: Double,
        range: ClosedRange<Double>,
        onChange: @escaping (Double) -> Void
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 12))
                .foregroundStyle(DS.Palette.ink(0.5))
                .frame(width: 18)
            Text(String(localized: key, bundle: .module))
                .dsFont(.sans, .medium, 11)
                .foregroundStyle(DS.Palette.ink(0.55))
                .frame(width: 64, alignment: .leading)
            Slider(value: Binding(get: { value }, set: onChange), in: range)
                .tint(VideoLayerLane.tint)
            Text(verbatim: "%\(Int((value * 100).rounded()))")
                .dsFont(.mono, .medium, 10)
                .foregroundStyle(DS.Palette.ink(0.6))
                .frame(width: 38, alignment: .trailing)
        }
    }

    private func timeStepper(_ key: String.LocalizationValue, value: Double, onStep: @escaping (Double) -> Void) -> some View {
        HStack(spacing: 0) {
            stepButton("minus") { onStep(-0.1) }
            VStack(spacing: 1) {
                Text(String(localized: key, bundle: .module))
                    .dsFont(.mono, .medium, 8)
                    .foregroundStyle(DS.Palette.ink(0.45))
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

    private func smallButton(_ key: String.LocalizationValue, symbol: String, enabled: Bool = true, action: @escaping () -> Void) -> some View {
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
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
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
