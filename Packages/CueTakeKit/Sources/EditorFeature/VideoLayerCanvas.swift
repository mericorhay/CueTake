import DesignSystem
import Domain
import SwiftUI

/// The selected added video's frame, drawn on the editor's own picture: drag it to move it, pinch
/// anywhere on the picture or pull its corner to resize it.
///
/// Placing used to happen only on a separate full screen, which hid the timeline — so a video
/// could not be placed and timed together. Here both are on screen at once.
struct VideoLayerCanvas: View {
    @Bindable var model: EditorModel

    @State private var moveOrigin: VideoPlacement?
    @State private var sizeOrigin: VideoPlacement?
    @State private var tick = 0

    var body: some View {
        GeometryReader { proxy in
            let rect = OverlayCanvas.videoRect(in: proxy.size, render: model.project.format.renderSize)
            if let layer = model.selectedVideoLayerValue {
                let playing = model.playhead >= layer.start.seconds && model.playhead < layer.end
                let placement = layer.placement(at: model.playhead).bounded
                let frame = CGRect(
                    x: rect.minX + rect.width * placement.x,
                    y: rect.minY + rect.height * placement.y,
                    width: max(30, rect.width * placement.width),
                    height: max(30, rect.height * placement.height)
                )

                ZStack(alignment: .topLeading) {
                    // Pinching anywhere on the picture resizes: two fingers rarely fit on a small video.
                    Color.clear
                        .contentShape(Rectangle())
                        .gesture(resize(layer))

                    box(playing: playing)
                        .frame(width: frame.width, height: frame.height)
                        .offset(x: frame.minX, y: frame.minY)
                        .gesture(move(layer, in: rect))

                    // The corner handle, for one-finger resizing.
                    Circle()
                        .fill(VideoLayerLane.tint)
                        .overlay(Circle().stroke(DS.Palette.inkInverse, lineWidth: 2))
                        .frame(width: 18, height: 18)
                        .frame(width: 40, height: 40)
                        .contentShape(Rectangle())
                        .offset(x: frame.maxX - 20, y: frame.maxY - 20)
                        .gesture(corner(layer, in: rect))

                    if !playing {
                        Button {
                            model.seek(to: layer.start.seconds + 0.01)
                        } label: {
                            Label(String(localized: "editor.video.goToIt", bundle: .module), systemImage: "arrow.uturn.forward")
                                .dsFont(.sans, .semibold, 11)
                                .foregroundStyle(DS.Palette.inkInverse)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(Capsule().fill(VideoLayerLane.tint))
                        }
                        .buttonStyle(.dsPress(radius: 20))
                        .position(x: rect.midX, y: rect.maxY - 22)
                    }
                }
                .sensoryFeedback(.selection, trigger: tick)
            }
        }
    }

    private func box(playing: Bool) -> some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(VideoLayerLane.tint.opacity(playing ? 0.04 : 0.12))
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(VideoLayerLane.tint, style: StrokeStyle(lineWidth: 2, dash: playing ? [] : [6, 4]))
            }
            .contentShape(Rectangle())
    }

    private func move(_ layer: VideoLayer, in rect: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                if moveOrigin == nil {
                    moveOrigin = layer.placement(at: model.playhead)
                    model.pause()
                }
                guard var placement = moveOrigin else { return }
                placement.x += Double(value.translation.width / max(rect.width, 1))
                placement.y += Double(value.translation.height / max(rect.height, 1))
                model.setVideoLayerPlacement(layer.id, placement)
            }
            .onEnded { _ in
                moveOrigin = nil
                tick += 1
            }
    }

    private func corner(_ layer: VideoLayer, in rect: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                if sizeOrigin == nil {
                    sizeOrigin = layer.placement(at: model.playhead)
                    model.pause()
                }
                guard let origin = sizeOrigin else { return }
                // The top-left corner stays put; the pulled corner sets the width.
                var next = origin
                let width = origin.width + Double(value.translation.width / max(rect.width, 1))
                let ratio = origin.height / max(origin.width, 0.01)
                next.width = min(max(width, 0.1), 1)
                next.height = min(max(next.width * ratio, 0.1), 1)
                model.setVideoLayerPlacement(layer.id, next)
            }
            .onEnded { _ in
                sizeOrigin = nil
                tick += 1
            }
    }

    private func resize(_ layer: VideoLayer) -> some Gesture {
        MagnifyGesture(minimumScaleDelta: 0.01)
            .onChanged { value in
                if sizeOrigin == nil { sizeOrigin = layer.placement(at: model.playhead) }
                guard let origin = sizeOrigin else { return }
                let factor = min(max(Double(value.magnification), 0.25), 4)
                model.setVideoLayerPlacement(layer.id, origin.resized(width: origin.width * factor))
            }
            .onEnded { _ in
                sizeOrigin = nil
                tick += 1
            }
    }
}
