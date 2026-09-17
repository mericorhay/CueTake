import DesignSystem
import Domain
import SwiftUI

/// The picture being placed, drawn on the editor's own preview: drag it to move it, pinch anywhere
/// or pull its corner to resize it. It is either an added video or the shot video itself, because
/// a split screen needs both halves to be movable.
///
/// Placing used to happen only on a separate full screen, which hid the timeline — so a video
/// could not be placed and timed together. Here both are on screen at once.
struct VideoLayerCanvas: View {
    @Bindable var model: EditorModel

    @State private var moveOrigin: VideoPlacement?
    @State private var sizeOrigin: VideoPlacement?
    @State private var tick = 0

    private var tint: Color {
        model.isPlacingMainVideo ? DS.Palette.lime : VideoLayerLane.tint
    }

    var body: some View {
        GeometryReader { proxy in
            let rect = OverlayCanvas.videoRect(in: proxy.size, render: model.project.format.renderSize)
            if let piece = model.placedPiece {
                let playing = isPlaying(piece)
                let placement = model.placement(of: piece)
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
                        .gesture(resize(piece))

                    box(playing: playing)
                        .frame(width: frame.width, height: frame.height)
                        .offset(x: frame.minX, y: frame.minY)
                        .gesture(move(piece, in: rect))

                    // The corner handle, for one-finger resizing.
                    Circle()
                        .fill(tint)
                        .overlay(Circle().stroke(DS.Palette.inkInverse, lineWidth: 2))
                        .frame(width: 18, height: 18)
                        .frame(width: 40, height: 40)
                        .contentShape(Rectangle())
                        .offset(x: frame.maxX - 20, y: frame.maxY - 20)
                        .gesture(corner(piece, in: rect))

                    if case .layer(let id) = piece, !playing,
                       let layer = model.project.videoLayers.first(where: { $0.id == id }) {
                        Button {
                            model.seek(to: layer.start.seconds + 0.01)
                        } label: {
                            Label(String(localized: "editor.video.goToIt", bundle: .module), systemImage: "arrow.uturn.forward")
                                .dsFont(.sans, .semibold, 11)
                                .foregroundStyle(DS.Palette.inkInverse)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(Capsule().fill(tint))
                        }
                        .buttonStyle(.dsPress(radius: 20))
                        .position(x: rect.midX, y: rect.maxY - 22)
                    }
                }
                .animation(DS.Motion.snap, value: model.isPlacingMainVideo)
                .sensoryFeedback(.selection, trigger: tick)
            }
        }
    }

    /// The shot video is always on screen; an added one only over its own stretch of the timeline.
    private func isPlaying(_ piece: StagePiece) -> Bool {
        switch piece {
        case .main:
            return true
        case .layer(let id):
            guard let layer = model.project.videoLayers.first(where: { $0.id == id }) else { return false }
            return model.playhead >= layer.start.seconds && model.playhead < layer.end
        }
    }

    private func box(playing: Bool) -> some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(tint.opacity(playing ? 0.04 : 0.12))
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(tint, style: StrokeStyle(lineWidth: 2, dash: playing ? [] : [6, 4]))
            }
            .contentShape(Rectangle())
    }

    private func move(_ piece: StagePiece, in rect: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                if moveOrigin == nil {
                    moveOrigin = model.placement(of: piece)
                    model.pause()
                }
                guard var placement = moveOrigin else { return }
                placement.x += Double(value.translation.width / max(rect.width, 1))
                placement.y += Double(value.translation.height / max(rect.height, 1))
                model.setPlacement(placement, of: piece)
            }
            .onEnded { _ in
                moveOrigin = nil
                tick += 1
            }
    }

    private func corner(_ piece: StagePiece, in rect: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                if sizeOrigin == nil {
                    sizeOrigin = model.placement(of: piece)
                    model.pause()
                }
                guard let origin = sizeOrigin else { return }
                // The top-left corner stays put; the pulled corner sets the width.
                var next = origin
                let width = origin.width + Double(value.translation.width / max(rect.width, 1))
                let ratio = origin.height / max(origin.width, 0.01)
                next.width = min(max(width, 0.1), 1)
                next.height = min(max(next.width * ratio, 0.1), 1)
                model.setPlacement(next, of: piece)
            }
            .onEnded { _ in
                sizeOrigin = nil
                tick += 1
            }
    }

    private func resize(_ piece: StagePiece) -> some Gesture {
        MagnifyGesture(minimumScaleDelta: 0.01)
            .onChanged { value in
                if sizeOrigin == nil { sizeOrigin = model.placement(of: piece) }
                guard let origin = sizeOrigin else { return }
                let factor = min(max(Double(value.magnification), 0.25), 4)
                model.setPlacement(origin.resized(width: origin.width * factor), of: piece)
            }
            .onEnded { _ in
                sizeOrigin = nil
                tick += 1
            }
    }
}
