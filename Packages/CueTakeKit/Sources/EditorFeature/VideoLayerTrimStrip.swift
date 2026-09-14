import DesignSystem
import Domain
import SwiftUI

/// The whole of an added video's file as a strip of pictures, with the part that plays held
/// between two handles — the trim the Photos app taught everyone.
///
/// Pull a handle to start later or stop sooner; slide the lit window to play another part of the
/// same length. The picture above follows the handle, so the frame being chosen is on screen.
struct VideoLayerTrimStrip: View {
    @Bindable var model: EditorModel
    let layer: VideoLayer

    private enum Grip { case start, end, window }
    @State private var origin: (start: Double, end: Double, grip: Grip)?

    static let height: CGFloat = 54
    private static let handleWidth: CGFloat = 16

    private var fileLength: Double {
        max(model.project.recording(id: layer.recordingID)?.duration.seconds ?? layer.duration, 0.2)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { proxy in
                let width = max(proxy.size.width - Self.handleWidth * 2, 1)
                let x = { (seconds: Double) in Self.handleWidth + CGFloat(seconds / fileLength) * width }
                let from = layer.sourceRange.start.seconds
                let to = layer.sourceRange.end.seconds

                ZStack(alignment: .topLeading) {
                    frames
                        .frame(width: width, height: Self.height)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .offset(x: Self.handleWidth)

                    // What does not play, dimmed.
                    Rectangle()
                        .fill(.black.opacity(0.6))
                        .frame(width: max(0, x(from) - Self.handleWidth), height: Self.height)
                        .offset(x: Self.handleWidth)
                    Rectangle()
                        .fill(.black.opacity(0.6))
                        .frame(width: max(0, Self.handleWidth + width - x(to)), height: Self.height)
                        .offset(x: x(to))

                    // The part that plays.
                    window(width: max(x(to) - x(from), 4))
                        .offset(x: x(from) - Self.handleWidth)
                        .gesture(drag(.window))
                }
                .frame(height: Self.height)
            }
            .frame(height: Self.height)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { total in
                stripWidth = max(1, total - Self.handleWidth * 2)
            }

            HStack(spacing: 6) {
                Text(verbatim: "\(MediaTime(seconds: layer.sourceRange.start.seconds).preciseTimecode) – \(MediaTime(seconds: layer.sourceRange.end.seconds).preciseTimecode)")
                    .dsFont(.mono, .medium, 10)
                    .foregroundStyle(DS.Palette.ink(0.75))
                    .contentTransition(.numericText())
                Text(verbatim: "· " + String(format: "%.1f s", layer.duration))
                    .dsFont(.mono, .medium, 10)
                    .foregroundStyle(DS.Palette.ink(0.45))
                Spacer(minLength: 0)
                Text(verbatim: MediaTime(seconds: fileLength).timecode)
                    .dsFont(.mono, .medium, 9)
                    .foregroundStyle(DS.Palette.ink(0.35))
            }
        }
        .task(id: layer.recordingID) { await model.loadRecordingFrames(layer.recordingID) }
    }

    private var frames: some View {
        GeometryReader { proxy in
            let pictures = model.recordingFrames[layer.recordingID] ?? []
            if pictures.isEmpty {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(VideoLayerLane.tint.opacity(0.2))
            } else {
                let tiles = max(1, Int(proxy.size.width / 34))
                HStack(spacing: 0) {
                    ForEach(0..<tiles, id: \.self) { tile in
                        Image(decorative: pictures[min(pictures.count - 1, tile * pictures.count / tiles)], scale: 1)
                            .resizable()
                            .scaledToFill()
                            .frame(width: proxy.size.width / CGFloat(tiles), height: proxy.size.height)
                            .clipped()
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func window(width: CGFloat) -> some View {
        let active = origin != nil
        return HStack(spacing: 0) {
            handle(systemName: "chevron.compact.left", active: origin?.grip == .start)
                .gesture(drag(.start))
            Rectangle()
                .fill(Color.white.opacity(0.001))
                .frame(width: width)
                .overlay(alignment: .top) { Rectangle().fill(DS.Palette.lime).frame(height: 3) }
                .overlay(alignment: .bottom) { Rectangle().fill(DS.Palette.lime).frame(height: 3) }
            handle(systemName: "chevron.compact.right", active: origin?.grip == .end)
                .gesture(drag(.end))
        }
        .frame(height: Self.height)
        .shadow(color: .black.opacity(active ? 0.4 : 0), radius: 6)
        .contentShape(Rectangle())
    }

    private func handle(systemName: String, active: Bool) -> some View {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(DS.Palette.lime)
            .frame(width: Self.handleWidth, height: Self.height)
            .overlay {
                Image(systemName: systemName)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(DS.Palette.inkInverse)
            }
            .scaleEffect(y: active ? 1.08 : 1)
            .contentShape(Rectangle().inset(by: -8))
    }

    private func drag(_ grip: Grip) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .global)
            .onChanged { value in
                if origin == nil || origin?.grip != grip {
                    origin = (layer.sourceRange.start.seconds, layer.sourceRange.end.seconds, grip)
                    model.pause()
                }
                guard let origin else { return }
                // Points on the strip to seconds of the file.
                let seconds = Double(value.translation.width) / Double(stripWidth) * fileLength
                switch grip {
                case .start:
                    let wanted = min(max(0, origin.start + seconds), origin.end - 0.2)
                    model.trimVideoLayer(layer.id, sourceStart: wanted)
                    followStart()
                case .end:
                    let wanted = max(min(fileLength, origin.end + seconds), origin.start + 0.2)
                    model.trimVideoLayer(layer.id, sourceEnd: wanted)
                    if let fresh = model.project.videoLayers.first(where: { $0.id == layer.id }) {
                        model.seek(to: max(fresh.start.seconds, fresh.end - 0.04))
                    }
                case .window:
                    let length = origin.end - origin.start
                    let wanted = min(max(0, origin.start + seconds), max(0, fileLength - length))
                    model.trimVideoLayer(layer.id, slideTo: wanted)
                    followStart()
                }
            }
            .onEnded { _ in origin = nil }
    }

    /// The width of the pictures, which is the whole file.
    @State private var stripWidth: CGFloat = 300

    private func followStart() {
        if let fresh = model.project.videoLayers.first(where: { $0.id == layer.id }) {
            model.seek(to: fresh.start.seconds + 0.01)
        }
    }
}
