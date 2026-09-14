import DesignSystem
import Domain
import SwiftUI

/// Additional movies get a dedicated lane so their timing is visible beside the main cut.
struct VideoLayerLane: View {
    @Bindable var model: EditorModel
    let scale: Double

    @State private var drag: DragState?
    @State private var trim: DragState?

    private struct DragState: Equatable {
        var id: VideoLayer.ID
        var origin: Double
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: "rectangle.split.2x1")
                Text("editor.videoLayers", bundle: .module)
            }
            .dsFont(.mono, .medium, 9)
            .foregroundStyle(DS.Palette.ink(0.45))
            ForEach(model.project.videoLayers) { layer in
                view(for: layer)
                    .frame(width: max(38, CGFloat(layer.duration * scale)), height: 25, alignment: .leading)
                    .offset(x: CGFloat(layer.start.seconds * scale))
                    .zIndex(model.selectedVideoLayer == layer.id ? 1 : 0)
            }
        }
        .frame(minHeight: CGFloat(model.project.videoLayers.count) * 29 + 18, alignment: .topLeading)
    }

    private func view(for layer: VideoLayer) -> some View {
        let isSelected = model.selectedVideoLayer == layer.id
        return HStack(spacing: 6) {
            Image(systemName: layer.isMuted ? "speaker.slash.fill" : "video.fill")
                .font(.system(size: 9, weight: .semibold))
            Text(layer.title)
                .dsFont(.sans, .semibold, 10)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
        .foregroundStyle(DS.Palette.inkInverse)
        .padding(.horizontal, 8)
        .background(RoundedRectangle(cornerRadius: 7).fill(DS.Palette.lime.opacity(isSelected ? 1 : 0.65)))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(DS.Palette.ink, lineWidth: isSelected ? 2 : 0))
        .overlay(alignment: .trailing) {
            if isSelected { trimHandle(for: layer) }
        }
        .overlay(alignment: .leading) {
            if isSelected { startTrimHandle(for: layer) }
        }
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .contentShape(RoundedRectangle(cornerRadius: 7))
        .onTapGesture {
            withAnimation(DS.Motion.snap) { model.select(videoLayer: isSelected ? nil : layer.id) }
        }
        .gesture(moveGesture(for: layer))
    }

    private func trimHandle(for layer: VideoLayer) -> some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(DS.Palette.ink)
            .frame(width: trim?.id == layer.id ? 5 : 3, height: 16)
            .padding(.trailing, 3)
            .frame(width: 24, height: 25, alignment: .trailing)
            .contentShape(Rectangle())
            .gesture(trimGesture(for: layer))
    }

    private func startTrimHandle(for layer: VideoLayer) -> some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(DS.Palette.ink)
            .frame(width: trim?.id == layer.id ? 5 : 3, height: 16)
            .padding(.leading, 3)
            .frame(width: 24, height: 25, alignment: .leading)
            .contentShape(Rectangle())
            .gesture(startTrimGesture(for: layer))
    }

    private func moveGesture(for layer: VideoLayer) -> some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { gesture in
                let origin = drag?.origin ?? layer.start.seconds
                if drag == nil {
                    drag = DragState(id: layer.id, origin: origin)
                    model.select(videoLayer: layer.id)
                }
                let raw = origin + Double(gesture.translation.width) / scale
                let tolerance = TimelineScale.snapTolerance(pointsPerSecond: scale)
                let target = model.snapTarget(for: raw, tolerance: tolerance) ?? raw
                model.updateVideoLayer(layer.id, coalescing: "video-layer-move-\(layer.id)") {
                    $0.start = MediaTime(seconds: max(0, target))
                }
            }
            .onEnded { _ in drag = nil }
    }

    private func trimGesture(for layer: VideoLayer) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { gesture in
                let origin = trim?.origin ?? layer.sourceRange.duration.seconds
                if trim == nil { trim = DragState(id: layer.id, origin: origin) }
                let wanted = origin + Double(gesture.translation.width) / scale
                model.updateVideoLayer(layer.id, coalescing: "video-layer-trim-\(layer.id)") { edited in
                    edited.sourceRange.duration = MediaTime(seconds: max(0.2, wanted))
                }
            }
            .onEnded { _ in trim = nil }
    }

    private func startTrimGesture(for layer: VideoLayer) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { gesture in
                let origin = trim?.origin ?? layer.start.seconds
                if trim == nil { trim = DragState(id: layer.id, origin: origin) }
                let wanted = max(0, origin + Double(gesture.translation.width) / scale)
                let delta = wanted - origin
                model.updateVideoLayer(layer.id, coalescing: "video-layer-trim-start-\(layer.id)") { edited in
                    let applied = min(
                        max(delta, -layer.sourceRange.start.seconds),
                        max(0, layer.sourceRange.duration.seconds - 0.2)
                    )
                    let newStart = max(0, layer.start.seconds + applied)
                    edited.start = MediaTime(seconds: newStart)
                    edited.sourceRange.start = MediaTime(seconds: max(0, layer.sourceRange.start.seconds + applied))
                    edited.sourceRange.duration = MediaTime(seconds: max(0.2, layer.sourceRange.duration.seconds - applied))
                    if applied > 0 {
                        edited.placement = layer.placement(at: layer.start.seconds + applied)
                        edited.keyframes = edited.keyframes.compactMap { frame in
                            guard frame.time > applied else { return nil }
                            var shifted = frame
                            shifted.time -= applied
                            return shifted
                        }
                    }
                }
            }
            .onEnded { _ in trim = nil }
    }
}
