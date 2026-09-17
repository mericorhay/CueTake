import DesignSystem
import Domain
import SwiftUI

/// An added video, open under the timeline.
///
/// Nothing here is set with plus and minus. When it plays is dragged on the timeline above; which
/// part of the file plays is chosen on the strip of its pictures; where it sits in the frame is
/// dragged and pinched on the picture itself. The panel holds the rest: layouts, size, sound, a
/// cut, and taking it away.
struct VideoLayerPanel: View {
    @Bindable var model: EditorModel
    let onOpenPlacementEditor: () -> Void
    let onClose: () -> Void

    private var layer: VideoLayer? { model.selectedVideoLayerValue }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    stage
                    if let layer {
                        VStack(alignment: .leading, spacing: 8) {
                            DSKicker(String(localized: "editor.video.part", bundle: .module), size: 9, color: DS.Palette.ink(0.42))
                            VideoLayerTrimStrip(model: model, layer: layer)
                        }
                        actions(layer)
                        smartReframe(layer)
                        if model.isReframed(videoLayer: layer.id), !isAnalyzing {
                            Button {
                                withAnimation(DS.Motion.settle) { model.removeReframe(fromVideoLayer: layer.id) }
                            } label: {
                                Label {
                                    Text("editor.video.smartReframe.remove", bundle: .module)
                                } icon: {
                                    Image(systemName: "xmark.circle")
                                }
                                .dsFont(.sans, .medium, 12)
                                .foregroundStyle(DS.Palette.ink(0.6))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                            }
                            .buttonStyle(.dsPress(radius: 14))
                        }
                        placement(layer)
                        sound(layer)
                    } else {
                        mainPicture
                    }
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

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: layer == nil ? "person.crop.rectangle" : "rectangle.inset.filled")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DS.Palette.inkInverse)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(layer == nil ? DS.Palette.lime : VideoLayerLane.tint)
                )
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: layer?.title ?? String(localized: "editor.video.main", bundle: .module))
                    .dsFont(.sans, .semibold, 14)
                    .foregroundStyle(DS.Palette.ink)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let layer {
                    Text(verbatim: "\(MediaTime(seconds: layer.start.seconds).preciseTimecode) – \(MediaTime(seconds: layer.end).preciseTimecode)")
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

    // MARK: - The stage

    /// Which of the pictures on screen the fingers are placing. The shot video is one of them:
    /// a split screen is two pictures sharing a frame, and either of them may be the small one.
    @ViewBuilder
    private var stage: some View {
        if !model.project.videoLayers.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                DSKicker(String(localized: "editor.video.stage", bundle: .module), size: 9, color: DS.Palette.ink(0.42))
                ScrollView(.horizontal) {
                    HStack(spacing: 7) {
                        piece(
                            title: String(localized: "editor.video.main", bundle: .module),
                            symbol: "person.crop.rectangle",
                            tint: DS.Palette.lime,
                            isOn: model.isPlacingMainVideo
                        ) {
                            withAnimation(DS.Motion.snap) { model.placeMainVideo(true) }
                        }
                        ForEach(model.project.videoLayers) { other in
                            piece(
                                title: other.title,
                                symbol: "rectangle.inset.filled",
                                tint: VideoLayerLane.tint,
                                isOn: model.selectedVideoLayer == other.id
                            ) {
                                withAnimation(DS.Motion.snap) { model.select(videoLayer: other.id) }
                            }
                        }
                    }
                    .padding(.vertical, 1)
                }
                .scrollIndicators(.hidden)
                .scrollClipDisabled()

                if let together = layer ?? model.project.videoLayers.first {
                    HStack(spacing: 7) {
                        splitButton(.sideBySide, "rectangle.split.2x1", with: together)
                        splitButton(.stacked, "rectangle.split.1x2", with: together)
                        splitButton(.pictureInPicture, "rectangle.inset.filled", with: together)
                        Button {
                            withAnimation(DS.Motion.settle) { model.swapStage(with: together.id) }
                        } label: {
                            Image(systemName: "arrow.left.arrow.right")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(DS.Palette.ink)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(DS.Palette.hairline(0.08)))
                        }
                        .buttonStyle(.dsPress(radius: 11))
                        .accessibilityLabel(Text("editor.video.swap", bundle: .module))
                    }
                }
            }
        }
    }

    /// The shot video's own size and brightness, for when it is the one being placed.
    private var mainPicture: some View {
        let current = model.project.mainVideoPlacement.bounded
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                DSKicker(String(localized: "editor.video.where", bundle: .module), size: 9, color: DS.Palette.ink(0.42))
                Text("editor.video.placeOnPicture", bundle: .module)
                    .dsFont(.sans, .regular, 10)
                    .foregroundStyle(DS.Palette.ink(0.4))
            }
            slider("editor.video.size", symbol: "square.resize", value: current.width, range: 0.1...1) { value in
                model.setMainVideoPlacement(current.resized(width: value))
            }
            Button {
                withAnimation(DS.Motion.settle) { model.fillFrameWithMainVideo() }
            } label: {
                Label {
                    Text("editor.video.wholeFrame", bundle: .module)
                } icon: {
                    Image(systemName: "rectangle")
                }
                .dsFont(.sans, .medium, 12)
                .foregroundStyle(DS.Palette.ink(0.75))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(DS.Palette.hairline(0.07)))
            }
            .buttonStyle(.dsPress(radius: 14))
            .disabled(model.isMainVideoWholeFrame)
            .opacity(model.isMainVideoWholeFrame ? 0.4 : 1)
        }
    }

    private func piece(
        title: String,
        symbol: String,
        tint: Color,
        isOn: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
                Text(verbatim: title)
                    .dsFont(.sans, .medium, 11)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .foregroundStyle(isOn ? DS.Palette.inkInverse : DS.Palette.ink(0.8))
            .padding(.horizontal, 12)
            .frame(height: 34)
            .frame(maxWidth: 150)
            .background(Capsule().fill(isOn ? tint : DS.Palette.hairline(0.07)))
        }
        .buttonStyle(.dsPress(radius: 17))
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private func splitButton(_ layout: VideoLayout, _ symbol: String, with other: VideoLayer) -> some View {
        Button {
            withAnimation(DS.Motion.settle) { model.splitScreen(layout, with: other.id) }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(DS.Palette.ink)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(DS.Palette.hairline(0.08)))
        }
        .buttonStyle(.dsPress(radius: 11))
        .accessibilityLabel(Text(layoutLabel(layout)))
    }

    // MARK: - Actions

    private func actions(_ layer: VideoLayer) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: 7) {
                chip("arrow.right.to.line", "editor.video.moveHere") {
                    withAnimation(DS.Motion.settle) { model.moveVideoLayer(layer.id, to: model.playhead) }
                }
                chip("scissors", "editor.tool.split", enabled: model.canSplitVideoLayer(layer.id)) {
                    withAnimation(DS.Motion.settle) { model.splitVideoLayer(layer.id) }
                }
                chip("arrow.up.left.and.arrow.down.right", "editor.video.fullscreen", action: onOpenPlacementEditor)
                chip(layer.isHidden ? "eye.slash.fill" : "eye.fill", "editor.video.hide", isOn: layer.isHidden) {
                    model.updateVideoLayer(layer.id) { $0.isHidden.toggle() }
                }
                chip("arrow.left.and.right.righttriangle.left.righttriangle.right", "editor.video.mirror", isOn: layer.placement.isMirrored) {
                    model.toggleVideoLayerMirror(layer.id)
                }
                chip("diamond", "editor.video.keyframe") {
                    model.addVideoKeyframe(to: layer.id)
                }
                chip("trash", "editor.video.remove", destructive: true) {
                    let id = layer.id
                    onClose()
                    withAnimation(DS.Motion.settle) { model.removeVideoLayer(id) }
                }
            }
            .padding(.vertical, 1)
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
    }

    // MARK: - Placement

    private var isAnalyzing: Bool {
        if case .analyzing = model.subjectTracking { return true }
        return false
    }

    private func smartReframe(_ layer: VideoLayer) -> some View {
        let analyzing = isAnalyzing
        return Button {
            Task { await model.smartReframeVideoLayer(layer.id) }
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(VideoLayerLane.tint.opacity(0.16))
                    Image(systemName: "viewfinder")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(VideoLayerLane.tint)
                        .symbolEffect(.breathe, options: .repeating, isActive: analyzing)
                }
                .frame(width: 42, height: 42)

                VStack(alignment: .leading, spacing: 2) {
                    Text("editor.video.smartReframe", bundle: .module)
                        .dsFont(.sans, .semibold, 13)
                        .foregroundStyle(DS.Palette.ink)
                    Text(trackingDetail)
                        .dsFont(.sans, .regular, 10)
                        .foregroundStyle(trackingDetailColor)
                        .lineLimit(2)
                        .contentTransition(.numericText())
                }
                Spacer(minLength: 8)
                trackingAccessory
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(DS.Palette.hairline(0.06))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(VideoLayerLane.tint.opacity(analyzing ? 0.5 : 0.16), lineWidth: 1)
            }
        }
        .buttonStyle(.dsPress(radius: 16))
        .disabled(analyzing)
        .animation(DS.Motion.snap, value: model.subjectTracking)
    }

    private var trackingDetail: String {
        switch model.subjectTracking {
        case .idle:
            String(localized: "editor.video.smartReframe.hint", bundle: .module)
        case .analyzing(let progress):
            String(localized: "editor.video.smartReframe.progress \(Int((progress * 100).rounded()))", bundle: .module)
        case .applied(let points):
            String(localized: "editor.video.smartReframe.done \(points)", bundle: .module)
        case .noFace:
            String(localized: "editor.video.smartReframe.noFace", bundle: .module)
        case .failed:
            String(localized: "editor.video.smartReframe.failed", bundle: .module)
        }
    }

    private var trackingDetailColor: Color {
        switch model.subjectTracking {
        case .applied: VideoLayerLane.tint
        case .noFace, .failed: DS.Palette.accentWarm
        default: DS.Palette.ink(0.45)
        }
    }

    @ViewBuilder
    private var trackingAccessory: some View {
        switch model.subjectTracking {
        case .analyzing(let progress):
            ProgressView(value: progress)
                .progressViewStyle(.circular)
                .tint(VideoLayerLane.tint)
                .frame(width: 28, height: 28)
        case .applied:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(VideoLayerLane.tint)
                .symbolEffect(.bounce, value: model.subjectTracking)
        case .noFace, .failed:
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(DS.Palette.accentWarm)
                .frame(width: 28, height: 28)
        case .idle:
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(DS.Palette.ink(0.35))
                .frame(width: 28, height: 28)
        }
    }

    private func placement(_ layer: VideoLayer) -> some View {
        let current = layer.placement(at: model.playhead)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                DSKicker(String(localized: "editor.video.where", bundle: .module), size: 9, color: DS.Palette.ink(0.42))
                Text("editor.video.placeOnPicture", bundle: .module)
                    .dsFont(.sans, .regular, 10)
                    .foregroundStyle(DS.Palette.ink(0.4))
            }
            HStack(spacing: 7) {
                layoutButton(.pictureInPicture, "rectangle.inset.filled")
                layoutButton(.sideBySide, "rectangle.split.2x1")
                layoutButton(.stacked, "rectangle.split.1x2")
                layoutButton(.grid, "square.grid.2x2")
            }
            slider("editor.video.size", symbol: "square.resize", value: current.width, range: 0.1...1) { value in
                model.setVideoLayerPlacement(layer.id, current.resized(width: value))
            }
            slider("editor.video.opacity", symbol: "circle.lefthalf.filled", value: current.opacity, range: 0.05...1) { value in
                var next = current
                next.opacity = value
                model.setVideoLayerPlacement(layer.id, next)
            }
        }
    }

    private func sound(_ layer: VideoLayer) -> some View {
        HStack(spacing: 10) {
            Button {
                model.updateVideoLayer(layer.id) { $0.isMuted.toggle() }
            } label: {
                Image(systemName: layer.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(layer.isMuted ? DS.Palette.inkInverse : DS.Palette.ink)
                    .frame(width: 36, height: 36)
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

    // MARK: - Parts

    private func chip(
        _ symbol: String,
        _ key: String.LocalizationValue,
        isOn: Bool = false,
        enabled: Bool = true,
        destructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .medium))
                Text(String(localized: key, bundle: .module))
                    .dsFont(.sans, .medium, 10)
                    .lineLimit(1)
            }
            .foregroundStyle(
                isOn ? DS.Palette.inkInverse
                    : destructive ? DS.Palette.accent
                    : DS.Palette.ink(enabled ? 0.88 : 0.25)
            )
            .frame(width: 66, height: 56)
            .background(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(isOn ? VideoLayerLane.tint : DS.Palette.hairline(enabled ? 0.07 : 0.03))
            )
        }
        .buttonStyle(.dsPress(radius: 15))
        .disabled(!enabled)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private func layoutButton(_ layout: VideoLayout, _ symbol: String) -> some View {
        Button {
            withAnimation(DS.Motion.settle) { model.applyVideoLayout(layout) }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(DS.Palette.ink)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(DS.Palette.hairline(0.08)))
        }
        .buttonStyle(.dsPress(radius: 11))
        .accessibilityLabel(Text(layoutLabel(layout)))
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

    private func layoutLabel(_ layout: VideoLayout) -> String {
        switch layout {
        case .sideBySide: String(localized: "editor.video.layout.sideBySide", bundle: .module)
        case .stacked: String(localized: "editor.video.layout.stacked", bundle: .module)
        case .pictureInPicture: String(localized: "editor.video.layout.pip", bundle: .module)
        case .grid: String(localized: "editor.video.layout.grid", bundle: .module)
        }
    }
}

extension VideoPlacement {
    /// The same shape at another width, around the same centre.
    func resized(width: Double) -> VideoPlacement {
        var next = self
        let centerX = x + self.width / 2
        let centerY = y + height / 2
        let ratio = height / max(self.width, 0.01)
        next.width = min(max(width, 0.1), 1)
        next.height = min(max(next.width * ratio, 0.1), 1)
        next.x = centerX - next.width / 2
        next.y = centerY - next.height / 2
        return next
    }
}
