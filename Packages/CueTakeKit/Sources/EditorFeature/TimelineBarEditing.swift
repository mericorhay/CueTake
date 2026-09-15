import DesignSystem
import Domain
import SwiftUI

/// What a bar on the timeline can have done to it while it is selected.
struct TimelineBarEdits {
    /// Called with the new start, keeping the length.
    var move: ((Double) -> Void)?
    /// Called with the new start, keeping the end.
    var trimStart: ((Double) -> Void)?
    /// Called with the new end, keeping the start.
    var trimEnd: ((Double) -> Void)?
}

/// Fine-tuning on the timeline itself, the same for every kind of bar.
///
/// Timing used to be set in panels with plus and minus buttons that covered the timeline — a tenth
/// of a second per tap, with nothing to see it against. Now a selected bar is taken by the hand:
/// its middle moves it, either end stretches it, a label above the finger says the exact time, the
/// edge snaps to the playhead, to cuts and to the edges of everything else with a tick, and the
/// picture follows the edge being dragged so the frame it lands on is seen while choosing it.
///
/// Measured in the lane's coordinate space, which stays put, rather than the bar's, which moves
/// under the finger. Ahead of the timeline's scrolling only while selected: an unselected bar
/// leaves the drag to the scroll view.
struct TimelineBarEditing: ViewModifier {
    @Bindable var model: EditorModel
    let isSelected: Bool
    let start: Double
    let end: Double
    let scale: Double
    /// The named coordinate space of the lane the bar is laid out in.
    let space: String
    let edits: TimelineBarEdits
    let onTap: () -> Void

    private enum Grip { case start, end, body }

    @State private var origin: (start: Double, end: Double, grip: Grip)?
    /// Where edges can land, taken when the drag begins. Taken once: read live, the bar's own
    /// moving edges would be among them and it would stick to where it just was.
    @State private var landings: [Double] = []
    @State private var shown: (time: Double, grip: Grip)?
    @State private var snapTick = 0
    @State private var lastSnap: Double?

    static let edgeGrip: CGFloat = 24

    func body(content: Content) -> some View {
        content
            .overlay {
                if isSelected { handles }
            }
            .overlay(alignment: .top) {
                if let shown {
                    // Over the edge being dragged, clear of the finger.
                    let half = CGFloat((end - start) * scale) / 2
                    bubble(shown.time)
                        .offset(x: shown.grip == .end ? half : -half, y: -34)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
            .zIndex(origin != nil ? 2 : 0)
            .contentShape(Rectangle())
            .onTapGesture(perform: onTap)
            .highPriorityGesture(drag, including: isSelected ? .all : .subviews)
            .sensoryFeedback(.selection, trigger: snapTick)
    }

    // MARK: Parts

    private var handles: some View {
        GeometryReader { proxy in
            if proxy.size.width >= 18 {
                HStack(spacing: 0) {
                    if edits.trimStart != nil { handle(active: origin?.grip == .start) }
                    Spacer(minLength: 0)
                    if edits.trimEnd != nil { handle(active: origin?.grip == .end) }
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func handle(active: Bool) -> some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(DS.Palette.ink)
            .frame(width: active ? 9 : 7)
            .overlay {
                Capsule()
                    .fill(DS.Palette.inkInverse(0.55))
                    .frame(width: 2)
                    .padding(.vertical, 6)
            }
            .shadow(color: .black.opacity(0.4), radius: 2)
    }

    private func bubble(_ time: Double) -> some View {
        VStack(spacing: 1) {
            Text(verbatim: MediaTime(seconds: time).preciseTimecode)
                .dsFont(.mono, .medium, 11)
            Text(verbatim: String(format: "%.2f s", max(0, end - start)))
                .dsFont(.mono, .medium, 8)
                .opacity(0.6)
        }
        .foregroundStyle(DS.Palette.inkInverse)
        .fixedSize()
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(DS.Palette.ink))
    }

    // MARK: Gesture

    private var drag: some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .named(space))
            .onChanged { value in
                if origin == nil {
                    let width = CGFloat((end - start) * scale)
                    let touch = value.startLocation.x - CGFloat(start * scale)
                    // A short bar keeps a middle to hold: the grips shrink before the body does.
                    let grip = min(Self.edgeGrip, width / 3)
                    let chosen: Grip = if touch < grip, edits.trimStart != nil {
                        .start
                    } else if touch > width - grip, edits.trimEnd != nil {
                        .end
                    } else {
                        .body
                    }
                    origin = (start, end, chosen)
                    landings = model.timelineSnapPoints(playhead: model.playhead).filter { point in
                        abs(point - start) > 0.0005 && abs(point - end) > 0.0005
                    }
                    model.isAdjustingTimeline = true
                    model.pause()
                }
                guard let origin else { return }
                let delta = Double(value.translation.width) / scale
                let tolerance = TimelineScale.snapTolerance(pointsPerSecond: scale)

                switch origin.grip {
                case .start:
                    let wanted = origin.start + delta
                    let time = snapped(wanted, tolerance: tolerance)
                    edits.trimStart?(time)
                    follow(time, .start)
                case .end:
                    let wanted = origin.end + delta
                    let time = snapped(wanted, tolerance: tolerance)
                    edits.trimEnd?(time)
                    follow(time, .end)
                case .body:
                    let length = origin.end - origin.start
                    let rawStart = origin.start + delta
                    // Whichever end is nearer to something worth landing on decides.
                    let byStart = landing(near: rawStart, tolerance: tolerance)
                    let byEnd = landing(near: rawStart + length, tolerance: tolerance)
                    var newStart = rawStart
                    var landed: Double?
                    if let byStart, abs(byStart - rawStart) <= abs((byEnd ?? .infinity) - (rawStart + length)) {
                        newStart = byStart
                        landed = byStart
                    } else if let byEnd {
                        newStart = byEnd - length
                        landed = byEnd
                    }
                    noteSnap(landed)
                    edits.move?(max(0, newStart))
                    follow(max(0, newStart), .body)
                }
            }
            .onEnded { _ in
                origin = nil
                lastSnap = nil
                withAnimation(.easeOut(duration: 0.15)) { shown = nil }
                model.isAdjustingTimeline = false
            }
    }

    private func landing(near value: Double, tolerance: Double) -> Double? {
        landings
            .min { abs($0 - value) < abs($1 - value) }
            .flatMap { abs($0 - value) <= tolerance ? $0 : nil }
    }

    private func snapped(_ wanted: Double, tolerance: Double) -> Double {
        let target = landing(near: wanted, tolerance: tolerance)
        noteSnap(target)
        return max(0, target ?? wanted)
    }

    private func noteSnap(_ target: Double?) {
        if let target, lastSnap.map({ abs($0 - target) > 0.0001 }) ?? true {
            snapTick += 1
        }
        lastSnap = target
    }

    /// The picture goes to the edge being set, so the frame it lands on is on screen.
    private func follow(_ time: Double, _ grip: Grip) {
        shown = (time, grip)
        model.seek(to: grip == .end ? max(0, time - 0.03) : time)
    }
}

extension View {
    func timelineBarEditing(
        model: EditorModel,
        isSelected: Bool,
        start: Double,
        end: Double,
        scale: Double,
        space: String,
        edits: TimelineBarEdits,
        onTap: @escaping () -> Void
    ) -> some View {
        modifier(TimelineBarEditing(
            model: model,
            isSelected: isSelected,
            start: start,
            end: end,
            scale: scale,
            space: space,
            edits: edits,
            onTap: onTap
        ))
    }
}

extension EditorModel {
    /// Every moment worth landing an edge on: the ends of the video, cuts between clips, where the
    /// playhead was when the drag began, and the edges of every text, picture, effect, sound and
    /// video. (The playhead itself follows the drag, so snapping to it would stick to itself.)
    func timelineSnapPoints(playhead: Double) -> [Double] {
        var points = snapPoints
        points.append(playhead)
        for overlay in project.overlays {
            points += [overlay.start.seconds, overlay.start.seconds + overlay.duration.seconds]
        }
        for effect in project.effects {
            points += [effect.start.seconds, effect.end]
        }
        for clip in project.audio {
            points += [clip.start.seconds, clip.timelineRange.end.seconds]
        }
        for layer in project.videoLayers {
            points += [layer.start.seconds, layer.end]
        }
        return points
    }
}
