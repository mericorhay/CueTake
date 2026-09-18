import DesignSystem
import Domain
import SwiftUI

/// A whole recording as a strip of its pictures, with the part in use held between two handles —
/// the trim the Photos app taught everyone.
///
/// Pull a handle to start later or stop sooner; where sliding is offered, slide the lit window to
/// use another part of the same length. The picture above follows the handle, so the frame being
/// chosen is on screen while it is chosen. Used for clips and for added videos alike.
struct FootageTrimStrip: View {
    @Bindable var model: EditorModel
    let recordingID: Recording.ID
    /// The part in use, in seconds of the file.
    let from: Double
    let to: Double
    let tint: Color
    /// Called with the wanted start, in seconds of the file.
    let onStart: (Double) -> Void
    /// Called with the wanted end.
    let onEnd: (Double) -> Void
    /// Called with the wanted start of the same length. Nil where a part cannot be slid.
    var onSlide: ((Double) -> Void)? = nil
    /// Where to put the playhead to show a moment of the file, if that moment is on the timeline.
    var moment: (Double) -> Double? = { _ in nil }

    private enum Grip { case start, end, window }
    @State private var origin: (from: Double, to: Double, grip: Grip)?
    /// The width of the pictures, which is the whole file.
    @State private var stripWidth: CGFloat = 300

    static let height: CGFloat = 54
    private static let handleWidth: CGFloat = 16

    private var fileLength: Double {
        max(model.project.recording(id: recordingID)?.duration.seconds ?? to, 0.2)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { proxy in
                let width = max(proxy.size.width - Self.handleWidth * 2, 1)
                let x = { (seconds: Double) in Self.handleWidth + CGFloat(seconds / fileLength) * width }

                ZStack(alignment: .topLeading) {
                    frames
                        .frame(width: width, height: Self.height)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .offset(x: Self.handleWidth)

                    // What is not used, dimmed.
                    Rectangle()
                        .fill(.black.opacity(0.6))
                        .frame(width: max(0, x(from) - Self.handleWidth), height: Self.height)
                        .offset(x: Self.handleWidth)
                    Rectangle()
                        .fill(.black.opacity(0.6))
                        .frame(width: max(0, Self.handleWidth + width - x(to)), height: Self.height)
                        .offset(x: x(to))

                    window(width: max(x(to) - x(from), 4))
                        .offset(x: x(from) - Self.handleWidth)
                }
                .frame(height: Self.height)
            }
            .frame(height: Self.height)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { total in
                stripWidth = max(1, total - Self.handleWidth * 2)
            }

            HStack(spacing: 6) {
                Text(verbatim: "\(MediaTime(seconds: from).preciseTimecode) – \(MediaTime(seconds: to).preciseTimecode)")
                    .dsFont(.mono, .medium, 10)
                    .foregroundStyle(DS.Palette.ink(0.75))
                    .contentTransition(.numericText())
                Text(verbatim: "· " + String(format: "%.1f s", to - from))
                    .dsFont(.mono, .medium, 10)
                    .foregroundStyle(DS.Palette.ink(0.56))
                Spacer(minLength: 0)
                Text(verbatim: MediaTime(seconds: fileLength).timecode)
                    .dsFont(.mono, .medium, 10)
                    .foregroundStyle(DS.Palette.ink(0.52))
            }
        }
        .task(id: recordingID) { await model.loadRecordingFrames(recordingID) }
    }

    private var frames: some View {
        GeometryReader { proxy in
            let pictures = model.recordingFrames[recordingID] ?? []
            if pictures.isEmpty {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(tint.opacity(0.2))
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
        HStack(spacing: 0) {
            handle(systemName: "chevron.compact.left", active: origin?.grip == .start)
                .gesture(drag(.start))
            Rectangle()
                .fill(Color.white.opacity(0.001))
                .frame(width: width)
                .overlay(alignment: .top) { Rectangle().fill(DS.Palette.lime).frame(height: 3) }
                .overlay(alignment: .bottom) { Rectangle().fill(DS.Palette.lime).frame(height: 3) }
                .gesture(drag(.window), including: onSlide == nil ? .none : .all)
            handle(systemName: "chevron.compact.right", active: origin?.grip == .end)
                .gesture(drag(.end))
        }
        .frame(height: Self.height)
        .shadow(color: .black.opacity(origin != nil ? 0.4 : 0), radius: 6)
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
                    origin = (from, to, grip)
                    model.pause()
                }
                guard let origin else { return }
                // Points on the strip to seconds of the file.
                let seconds = Double(value.translation.width) / Double(stripWidth) * fileLength
                switch grip {
                case .start:
                    let wanted = min(max(0, origin.from + seconds), origin.to - 0.2)
                    onStart(wanted)
                    if let time = moment(wanted) { model.seek(to: time) }
                case .end:
                    let wanted = max(min(fileLength, origin.to + seconds), origin.from + 0.2)
                    onEnd(wanted)
                    if let time = moment(wanted) { model.seek(to: max(0, time - 0.04)) }
                case .window:
                    let length = origin.to - origin.from
                    let wanted = min(max(0, origin.from + seconds), max(0, fileLength - length))
                    onSlide?(wanted)
                    if let time = moment(wanted) { model.seek(to: time) }
                }
            }
            .onEnded { _ in origin = nil }
    }
}

/// An added video's trim strip.
struct VideoLayerTrimStrip: View {
    @Bindable var model: EditorModel
    let layer: VideoLayer

    var body: some View {
        FootageTrimStrip(
            model: model,
            recordingID: layer.recordingID,
            from: layer.sourceRange.start.seconds,
            to: layer.sourceRange.end.seconds,
            tint: VideoLayerLane.tint,
            onStart: { model.trimVideoLayer(layer.id, sourceStart: $0) },
            onEnd: { model.trimVideoLayer(layer.id, sourceEnd: $0) },
            onSlide: { model.trimVideoLayer(layer.id, slideTo: $0) },
            moment: { seconds in
                guard let fresh = model.project.videoLayers.first(where: { $0.id == layer.id }) else { return nil }
                return fresh.start.seconds + max(0, seconds - fresh.sourceRange.start.seconds)
            }
        )
    }
}
