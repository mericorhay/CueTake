import DesignSystem
import Domain
import SwiftUI

/// Added videos on the timeline, one row each, to scale with the clips they play over.
///
/// Tap a bar to open it. A selected bar moves with a drag from its middle and trims from either
/// end — measured in the lane's own space, which stays put, rather than in the bar, which moves
/// under the finger — and takes the touch ahead of the timeline's scrolling, the same as a text or
/// a background does.
struct VideoLayerLane: View {
    @Bindable var model: EditorModel
    let scale: Double

    static let rowHeight: CGFloat = 25
    static let rowSpacing: CGFloat = 4
    static let tint = Color(red: 1.0, green: 0.56, blue: 0.74)
    private static let space = "videoLayerLane"

    /// The layer as it was when the finger went down, and which part of it was taken.
    @State private var origin: (layer: VideoLayer, grip: Grip)?

    private enum Grip { case start, end, body }

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
        .overlay {
            if selected {
                HStack {
                    handle
                    Spacer(minLength: 0)
                    handle
                }
                .padding(.horizontal, 3)
                .allowsHitTesting(false)
            }
        }
        .opacity(layer.isHidden ? 0.5 : 1)
        .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .onTapGesture {
            withAnimation(DS.Motion.snap) {
                model.select(videoLayer: selected ? nil : layer.id)
            }
        }
        .highPriorityGesture(drag(layer, width: width), including: selected ? .all : .subviews)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    private var handle: some View {
        Capsule()
            .fill(DS.Palette.inkInverse)
            .frame(width: 3, height: 13)
    }

    private func drag(_ layer: VideoLayer, width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .named(Self.space))
            .onChanged { value in
                if origin?.layer.id != layer.id {
                    let touch = value.startLocation.x - CGFloat(layer.start.seconds * scale)
                    let grip: Grip = touch < 22 ? .start : (touch > width - 22 ? .end : .body)
                    origin = (layer, grip)
                }
                guard let origin else { return }
                let delta = Double(value.translation.width) / scale
                switch origin.grip {
                case .start:
                    model.setVideoLayerStartEdge(layer.id, to: origin.layer.start.seconds + delta, coalescing: "video-layer-drag-start")
                case .end:
                    model.setVideoLayerEnd(layer.id, to: origin.layer.end + delta, coalescing: "video-layer-drag-end")
                case .body:
                    let raw = origin.layer.start.seconds + delta
                    let tolerance = TimelineScale.snapTolerance(pointsPerSecond: scale)
                    model.moveVideoLayer(layer.id, to: model.snapTarget(for: raw, tolerance: tolerance) ?? raw, coalescing: "video-layer-drag-move")
                }
            }
            .onEnded { _ in origin = nil }
    }
}
