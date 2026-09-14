import AVKit
import DesignSystem
import Domain
import SwiftUI

/// A distraction-free placement surface for a selected video layer.
///
/// The layer is moved with a direct drag and resized with a pinch. Arrow nudges remain useful for
/// tiny corrections in the compact panel, but they are no longer the primary placement control.
struct VideoLayerPlacementEditor: View {
    @Bindable var model: EditorModel
    let onClose: () -> Void

    @State private var dragOrigin: VideoPlacement?
    @State private var zoomOrigin: VideoPlacement?
    @State private var snapTick = 0

    private var layer: VideoLayer? { model.selectedVideoLayerValue }

    var body: some View {
        GeometryReader { proxy in
            let videoRect = OverlayCanvas.videoRect(in: proxy.size, render: model.project.format.renderSize)
            ZStack {
                DS.Palette.camera.ignoresSafeArea()

                if let player = model.player {
                    VideoPlayer(player: player)
                        .disabled(true)
                        .frame(width: videoRect.width, height: videoRect.height)
                        .position(x: videoRect.midX, y: videoRect.midY)
                } else {
                    Text("editor.preview.failed", bundle: .module)
                        .dsFont(.sans, .semibold, 14)
                        .foregroundStyle(DS.Palette.inkInverse(0.7))
                }

                if let layer {
                    selection(for: layer, in: videoRect)
                }

                VStack(spacing: 0) {
                    header
                    Spacer(minLength: 0)
                    footer
                }
                .padding(.top, proxy.safeAreaInsets.top)
                .padding(.bottom, proxy.safeAreaInsets.bottom)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .background(DS.Palette.camera)
        .statusBarHidden(true)
        .sensoryFeedback(.selection, trigger: snapTick)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .frame(width: 42, height: 42)
                    .background(Circle().fill(.black.opacity(0.45)))
            }
            .buttonStyle(.dsPressIcon)
            .accessibilityLabel(Text("editor.panel.close", bundle: .module))

            VStack(alignment: .leading, spacing: 2) {
                Text("editor.video.placement", bundle: .module)
                    .dsFont(.sans, .semibold, 15)
                Text(layer?.title ?? "")
                    .dsFont(.mono, .medium, 10)
                    .opacity(0.65)
            }
            .foregroundStyle(DS.Palette.inkInverse)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.top, 12)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Label(String(localized: "editor.video.placementHint", bundle: .module), systemImage: "hand.draw")
                .dsFont(.sans, .medium, 11)
                .foregroundStyle(DS.Palette.inkInverse(0.8))
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(Capsule().fill(.black.opacity(0.45)))

            Spacer(minLength: 0)

            if let layer {
                Button {
                    model.addVideoKeyframe(to: layer.id)
                } label: {
                    Label(String(localized: "editor.video.keyframe", bundle: .module), systemImage: "diamond.fill")
                        .dsFont(.sans, .semibold, 12)
                        .foregroundStyle(DS.Palette.inkInverse)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(AIPalette.blue))
                }
                .buttonStyle(.dsPress(radius: 20))
            }
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 14)
    }

    private func selection(for layer: VideoLayer, in videoRect: CGRect) -> some View {
        let placement = layer.placement(at: model.playhead).bounded
        let frame = CGRect(
            x: videoRect.minX + videoRect.width * placement.x,
            y: videoRect.minY + videoRect.height * placement.y,
            width: videoRect.width * placement.width,
            height: videoRect.height * placement.height
        )

        return RoundedRectangle(cornerRadius: 8, style: .continuous)
            .stroke(DS.Palette.lime, style: StrokeStyle(lineWidth: 2, dash: [7, 5]))
            .frame(width: max(36, frame.width), height: max(36, frame.height))
            .position(x: frame.midX, y: frame.midY)
            .overlay {
                Image(systemName: "hand.draw.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(DS.Palette.inkInverse)
                    .padding(10)
                    .background(Circle().fill(.black.opacity(0.48)))
                    .allowsHitTesting(false)
            }
            .contentShape(Rectangle())
            .gesture(moveGesture(for: layer, in: videoRect))
            .simultaneousGesture(resizeGesture(for: layer))
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

    private func resizeGesture(for layer: VideoLayer) -> some Gesture {
        MagnifyGesture(minimumScaleDelta: 0.01)
            .onChanged { value in
                let origin = zoomOrigin ?? layer.placement(at: model.playhead)
                if zoomOrigin == nil { zoomOrigin = origin }
                let factor = min(max(Double(value.magnification), 0.35), 2.5)
                var placement = origin
                let centerX = origin.x + origin.width / 2
                let centerY = origin.y + origin.height / 2
                placement.width = origin.width * factor
                placement.height = origin.height * factor
                placement.x = centerX - placement.width / 2
                placement.y = centerY - placement.height / 2
                model.setVideoLayerPlacement(layer.id, placement)
            }
            .onEnded { _ in zoomOrigin = nil }
    }
}
