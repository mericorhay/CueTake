import DesignSystem
import Domain
import SwiftUI

/// A bubble of glass over the timeline, under the finger.
///
/// The problem it solves is physical: the finger covers the thing it is aiming at. Every precise
/// gesture on a touchscreen has this, and the answer has always been the same one — move the
/// information out from under the hand and magnify it. The lens sits above the strip, shows the
/// same ruler at two and a bit times the scale, and puts the exact time where it can actually be
/// read.
///
/// Real material rather than a painted panel: it picks up the clip colours passing underneath it,
/// which is what makes it read as glass sitting on the timeline instead of a tooltip floating over
/// one. It swells into place — a lens that simply appears is a label; one that grows is an object.
struct ScrubLens: View {
    @Bindable var model: EditorModel
    /// Points per second on the timeline below. The lens draws at a multiple of this.
    let scale: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var grown = false

    static let diameter: CGFloat = 92
    /// Enough to separate two frames at a normal zoom, not so much that the clip under the finger
    /// loses its context.
    static let magnification: Double = 2.4

    var body: some View {
        ZStack {
            Circle()
                .fill(.ultraThinMaterial)

            Canvas(opaque: false) { context, size in
                draw(in: context, size: size)
            }
            .clipShape(Circle())

            // The highlight along the top edge is what makes it look thick rather than printed.
            Circle()
                .stroke(
                    LinearGradient(
                        colors: [DS.Palette.ink(0.35), DS.Palette.hairline(0.1)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )

            VStack(spacing: 2) {
                Text(model.playheadLabel)
                    .dsFont(.mono, .medium, 13)
                    .foregroundStyle(DS.Palette.ink)
                    .contentTransition(.numericText())

                Text(Self.frameLabel(for: model))
                    .dsFont(.mono, .medium, 8)
                    .foregroundStyle(DS.Palette.ink(0.45))
            }
            .offset(y: -24)
        }
        .frame(width: Self.diameter, height: Self.diameter)
        .shadow(color: .black.opacity(0.45), radius: 16, y: 6)
        .scaleEffect(grown ? 1 : 0.55)
        .opacity(grown ? 1 : 0)
        .onAppear {
            guard !reduceMotion else {
                grown = true
                return
            }
            withAnimation(DS.Motion.bloom) { grown = true }
        }
    }

    /// The magnified strip: clip colours, ticks, and the line the playhead is actually on.
    private func draw(in context: GraphicsContext, size: CGSize) {
        let middle = size.height / 2
        let centre = size.width / 2
        let pointsPerSecond = scale * Self.magnification
        let focus = model.playhead

        func x(_ seconds: Double) -> CGFloat {
            centre + CGFloat((seconds - focus) * pointsPerSecond)
        }

        // Clips, as a band. Colour is how a clip is recognised on the timeline, so the lens has to
        // carry it or the magnified view is of somewhere else.
        var start = 0.0
        for segment in model.project.segments {
            let end = start + segment.barWeight
            let rect = CGRect(x: x(start), y: middle - 13, width: max(x(end) - x(start) - 1, 1), height: 26)
            if rect.maxX > 0, rect.minX < size.width {
                context.fill(
                    Path(roundedRect: rect, cornerRadius: 3),
                    with: .color(DS.Palette.segment(at: segment.role.paletteIndex).opacity(0.85))
                )
            }
            start = end
        }

        // Ticks at the magnified interval, so they thin out as the timeline is zoomed in rather
        // than crowding into a solid bar.
        let interval = TimelineScale.tickInterval(pointsPerSecond: pointsPerSecond)
        let first = focus - Double(size.width / 2) / pointsPerSecond
        var tick = (first / interval).rounded(.down) * interval
        let last = focus + Double(size.width / 2) / pointsPerSecond
        while tick <= last {
            if tick >= 0 {
                let position = x(tick)
                context.stroke(
                    Path { path in
                        path.move(to: CGPoint(x: position, y: middle + 16))
                        path.addLine(to: CGPoint(x: position, y: middle + 22))
                    },
                    with: .color(DS.Palette.ink(0.3)),
                    lineWidth: 1
                )
            }
            tick += interval
        }

        // The playhead itself, dead centre, because that is the promise the lens is making.
        context.stroke(
            Path { path in
                path.move(to: CGPoint(x: centre, y: middle - 24))
                path.addLine(to: CGPoint(x: centre, y: middle + 24))
            },
            with: .color(DS.Palette.ink),
            lineWidth: 1.5
        )
    }

    /// The frame number inside the current second. The reason anyone is holding a finger this
    /// still is that they are looking for one particular frame.
    static func frameLabel(for model: EditorModel) -> String {
        let rate = max(1, model.project.format.frameRate)
        let frame = Int((model.playhead - model.playhead.rounded(.down)) * Double(rate))
        return "f\(min(frame, rate - 1) + 1)/\(rate)"
    }
}
