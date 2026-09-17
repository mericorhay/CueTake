import DesignSystem
import Domain
import SwiftUI

/// Added videos on the timeline, one row each, to scale with the clips they play over.
///
/// The row shows the film itself, like the clips above it, rather than a coloured stripe with a
/// file name on it: an added video is a video, and the moment to use is picked by looking at it.
///
/// Tap a bar to open it; a selected bar is moved and trimmed right here (see `TimelineBarEditing`).
struct VideoLayerLane: View {
    @Bindable var model: EditorModel
    let scale: Double

    static let rowHeight: CGFloat = 42
    static let rowSpacing: CGFloat = 5
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
                    // An added video arrives and leaves like something being put down, not by
                    // appearing fully formed in the middle of the timeline.
                    .transition(.scale(scale: 0.86, anchor: .leading).combined(with: .opacity))
            }
        }
        .frame(height: Self.height(for: model.project.videoLayers), alignment: .topLeading)
        .coordinateSpace(.named(Self.space))
        .animation(DS.Motion.settle, value: model.project.videoLayers.count)
    }

    private func bar(_ layer: VideoLayer, width: CGFloat) -> some View {
        let selected = model.selectedVideoLayer == layer.id
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        return ZStack(alignment: .leading) {
            film(layer)
                .opacity(layer.isHidden ? 0.3 : 1)
            // The title has to stay readable over whatever the film happens to be showing.
            LinearGradient(
                colors: [.black.opacity(0.66), .black.opacity(0.06)],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: min(width, 132))
            .allowsHitTesting(false)

            HStack(spacing: 5) {
                Image(systemName: layer.isHidden ? "eye.slash.fill" : (layer.isMuted ? "speaker.slash.fill" : "video.fill"))
                    .font(.system(size: 9, weight: .bold))
                Text(verbatim: layer.title)
                    .dsFont(.sans, .semibold, 10)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
            }
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.5), radius: 2, y: 1)
            .padding(.horizontal, selected ? 12 : 7)
        }
        .clipShape(shape)
        .overlay {
            shape.stroke(selected ? DS.Palette.ink : Self.tint.opacity(0.85), lineWidth: selected ? 2 : 1.5)
        }
        .shadow(color: .black.opacity(selected ? 0.28 : 0), radius: selected ? 7 : 0, y: 2)
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

    /// The stretch of the file this bar plays, in pictures. Until they arrive the bar is the old
    /// pink stripe, so the timeline never waits on a thumbnail.
    private func film(_ layer: VideoLayer) -> some View {
        GeometryReader { proxy in
            let pictures = model.recordingFrames[layer.recordingID] ?? []
            let length = model.project.recordings.first { $0.id == layer.recordingID }?.duration.seconds ?? 0
            if pictures.isEmpty || length <= 0 {
                Self.tint.opacity(0.72)
            } else {
                let tiles = max(1, Int(proxy.size.width / 30))
                HStack(spacing: 0) {
                    ForEach(0..<tiles, id: \.self) { tile in
                        let atSource = layer.sourceRange.start.seconds
                            + (Double(tile) + 0.5) / Double(tiles) * layer.duration
                        let index = min(pictures.count - 1, max(0, Int(atSource / length * Double(pictures.count))))
                        Image(decorative: pictures[index], scale: 1)
                            .resizable()
                            .scaledToFill()
                            .frame(width: proxy.size.width / CGFloat(tiles), height: proxy.size.height)
                            .clipped()
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .task(id: layer.recordingID) { await model.loadRecordingFrames(layer.recordingID) }
    }
}
