import DesignSystem
import Domain
import SwiftUI

/// Added videos on the timeline, one row each, to scale with the clips they play over.
///
/// Tap a bar to open it; a selected bar is moved and trimmed right here (see `TimelineBarEditing`).
struct VideoLayerLane: View {
    @Bindable var model: EditorModel
    let scale: Double

    static let rowHeight: CGFloat = 25
    static let rowSpacing: CGFloat = 4
    static let tint = Color(red: 1.0, green: 0.56, blue: 0.74)
    private static let space = "videoLayerLane"

    static func height(for layers: [VideoLayer]) -> CGFloat {
        guard !layers.isEmpty else { return 0 }
        return CGFloat(layers.count) * rowHeight + CGFloat(layers.count - 1) * rowSpacing
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(model.project.videoLayers.enumerated()), id: \.element.id) { row, layer in
                let width = max(CGFloat(layer.duration * scale) - 2, 30)
                bar(layer, width: width)
                    .frame(width: width, height: Self.rowHeight)
                    .offset(
                        x: CGFloat(layer.start.seconds * scale),
                        y: CGFloat(row) * (Self.rowHeight + Self.rowSpacing)
                    )
                    .zIndex(model.selectedVideoLayer == layer.id ? 1 : 0)
            }
        }
        .frame(height: Self.height(for: model.project.videoLayers), alignment: .topLeading)
        .coordinateSpace(.named(Self.space))
    }

    private func bar(_ layer: VideoLayer, width: CGFloat) -> some View {
        let selected = model.selectedVideoLayer == layer.id
        return HStack(spacing: 5) {
            Image(systemName: layer.isHidden ? "eye.slash.fill" : (layer.isMuted ? "speaker.slash.fill" : "video.fill"))
                .font(.system(size: 9, weight: .bold))
            Text(verbatim: layer.title)
                .dsFont(.sans, .semibold, 10)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
        .foregroundStyle(DS.Palette.inkInverse)
        .padding(.horizontal, selected ? 12 : 7)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Self.tint.opacity(selected ? 1 : 0.72)))
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(DS.Palette.ink, lineWidth: selected ? 2 : 0)
        }
        .opacity(layer.isHidden ? 0.5 : 1)
        .timelineBarEditing(
            model: model,
            isSelected: selected,
            start: layer.start.seconds,
            end: layer.end,
            scale: scale,
            space: Self.space,
            edits: TimelineBarEdits(
                move: { start in model.moveVideoLayer(layer.id, to: start, coalescing: "video-layer-drag-move") },
                trimStart: { start in model.setVideoLayerStartEdge(layer.id, to: start, coalescing: "video-layer-drag-start") },
                trimEnd: { end in model.setVideoLayerEnd(layer.id, to: end, coalescing: "video-layer-drag-end") }
            ),
            onTap: {
                withAnimation(DS.Motion.snap) {
                    model.select(videoLayer: selected ? nil : layer.id)
                }
            }
        )
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}
