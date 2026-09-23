import AVKit
import DesignSystem
import Domain
import SwiftUI

/// The whole screen for placing one added video: drag it, pinch it, or use the size slider.
///
/// Its words were drawn in the app's dark ink on the dark camera ground, so the title, the hint and
/// the size note could not be read. Every label here is light, on a dark plate where it sits over
/// the picture.
struct VideoLayerPlacementEditor: View {
    @Bindable var model: EditorModel
    let onClose: () -> Void

    @State private var dragOrigin: VideoPlacement?
    @State private var zoomOrigin: VideoPlacement?
    @State private var snapTick = 0

    private var layer: VideoLayer? { model.selectedVideoLayerValue }

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                header
                    .padding(.top, proxy.safeAreaInsets.top + 6)

                GeometryReader { stage in
                    let videoRect = OverlayCanvas.videoRect(in: stage.size, render: model.project.format.renderSize)
                    ZStack(alignment: .topLeading) {
                        if let player = model.player {
                            VideoPlayer(player: player)
                                .disabled(true)
                                .frame(width: videoRect.width, height: videoRect.height)
                                .offset(x: videoRect.minX, y: videoRect.minY)
                        } else {
                            Text("editor.preview.failed", bundle: .module)
                                .dsFont(.sans, .semibold, 14)
                                .foregroundStyle(DS.Palette.ink(0.7))
                                .frame(width: stage.size.width, height: stage.size.height)
                        }

                        // The frame's own edge, so the layer is placed against the finished video,
                        // not against the phone.
                        Rectangle()
                            .strokeBorder(DS.Palette.hairline(0.25), lineWidth: 1)
                            .frame(width: videoRect.width, height: videoRect.height)
                            .offset(x: videoRect.minX, y: videoRect.minY)
                            .allowsHitTesting(false)

                        if let layer {
                            selection(for: layer, in: videoRect)
                        }
                    }
                    .frame(width: stage.size.width, height: stage.size.height, alignment: .topLeading)
                    .contentShape(Rectangle())
                    // Pinch anywhere on the stage: two fingers rarely fit on a small layer.
                    .gesture(resizeGesture)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)

                footer
                    .padding(.bottom, proxy.safeAreaInsets.bottom + 8)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .background(DS.Palette.camera.ignoresSafeArea())
        .statusBarHidden(true)
        .sensoryFeedback(.selection, trigger: snapTick)
    }

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("editor.video.placement", bundle: .module)
                    .dsFont(.sans, .semibold, 15)
                    .foregroundStyle(DS.Palette.ink)
                Text(verbatim: layer?.title ?? "")
                    .dsFont(.mono, .medium, 10)
                    .foregroundStyle(DS.Palette.ink(0.55))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 0)
            Button(action: onClose) {
                Text("editor.done", bundle: .module)
                    .dsFont(.sans, .semibold, 13)
                    .foregroundStyle(DS.Palette.inkInverse)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(Capsule().fill(DS.Palette.lime))
            }
            .buttonStyle(.dsPress(radius: 20))
        }
        .padding(.horizontal, 18)
    }

    private var footer: some View {
        VStack(spacing: 12) {
            if let layer {
                let current = layer.placement(at: model.playhead)
                HStack(spacing: 10) {
                    Image(systemName: "square.resize")
                        .font(.system(size: 13))
                        .foregroundStyle(DS.Palette.ink(0.6))
                    Text("editor.video.size", bundle: .module)
                        .dsFont(.sans, .medium, 12)
                        .foregroundStyle(DS.Palette.ink(0.75))
                    Slider(
                        value: Binding(
                            get: { current.width },
                            set: { model.setVideoLayerPlacement(layer.id, current.resized(width: $0)) }
                        ),
                        in: 0.1...1
                    )
                    .tint(VideoLayerLane.tint)
                    Text(verbatim: "%\(Int((current.width * 100).rounded()))")
                        .dsFont(.mono, .medium, 11)
                        .foregroundStyle(DS.Palette.ink(0.8))
                        .frame(width: 42, alignment: .trailing)
                }

                HStack(spacing: 10) {
                    Label(AppLocalization.string("editor.video.placementHint", bundle: .module), systemImage: "hand.draw")
                        .dsFont(.sans, .medium, 11)
                        .foregroundStyle(DS.Palette.ink(0.7))
                        .lineLimit(2)
                    Spacer(minLength: 0)
                    Button {
                        model.setVideoLayerPlacement(layer.id, .inset)
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(DS.Palette.ink)
                            .frame(width: 38, height: 38)
                            .background(Circle().fill(DS.Palette.hairline(0.1)))
                    }
                    .buttonStyle(.dsPressIcon)
                    .accessibilityLabel(Text("editor.video.resetPlacement", bundle: .module))
                    Button {
                        model.addVideoKeyframe(to: layer.id)
                    } label: {
                        Label(AppLocalization.string("editor.video.keyframe", bundle: .module), systemImage: "diamond.fill")
                            .dsFont(.sans, .semibold, 12)
                            .foregroundStyle(DS.Palette.ink)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 10)
                            .background(Capsule().fill(DS.Palette.hairline(0.1)))
                    }
                    .buttonStyle(.dsPress(radius: 20))
                }
            }
        }
        .padding(.horizontal, 18)
    }

    private func selection(for layer: VideoLayer, in videoRect: CGRect) -> some View {
        let placement = layer.placement(at: model.playhead).bounded
        let frame = CGRect(
            x: videoRect.minX + videoRect.width * placement.x,
            y: videoRect.minY + videoRect.height * placement.y,
            width: max(36, videoRect.width * placement.width),
            height: max(36, videoRect.height * placement.height)
        )

        return ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(VideoLayerLane.tint.opacity(0.08))
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(VideoLayerLane.tint, style: StrokeStyle(lineWidth: 2, dash: [7, 5]))
            Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(DS.Palette.ink)
                .padding(9)
                .background(Circle().fill(.black.opacity(0.5)))
        }
        .frame(width: frame.width, height: frame.height)
        .contentShape(Rectangle())
        .offset(x: frame.minX, y: frame.minY)
        .gesture(moveGesture(for: layer, in: videoRect))
    }

    private func moveGesture(for layer: VideoLayer, in videoRect: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                let origin = dragOrigin ?? layer.placement(at: model.playhead)
                if dragOrigin == nil { dragOrigin = origin }
                var placement = origin
                placement.x += Double(value.translation.width) / max(1, videoRect.width)
                placement.y += Double(value.translation.height) / max(1, videoRect.height)
                model.setVideoLayerPlacement(layer.id, placement)
            }
            .onEnded { _ in
                dragOrigin = nil
                snapTick += 1
            }
    }

    private var resizeGesture: some Gesture {
        MagnifyGesture(minimumScaleDelta: 0.01)
            .onChanged { value in
                guard let layer else { return }
                let origin = zoomOrigin ?? layer.placement(at: model.playhead)
                if zoomOrigin == nil { zoomOrigin = origin }
                let factor = min(max(Double(value.magnification), 0.25), 4)
                model.setVideoLayerPlacement(layer.id, origin.resized(width: origin.width * factor))
            }
            .onEnded { _ in zoomOrigin = nil }
    }
}
