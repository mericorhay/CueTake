import DesignSystem
import Domain
import SwiftUI

/// The editing surface: a ruler in seconds, clips drawn to scale, and a playhead you can take hold of.
///
/// Everything here follows from one decision — width is time, not proportion. That is what lets the
/// timeline be zoomed into, which is what lets a cut be placed where it belongs rather than where
/// the arithmetic happens to put it.
struct EditorTimeline: View {
    @Bindable var model: EditorModel

    @State private var scrubOrigin: Double?
    @State private var zoomOrigin: Double?
    @State private var trim: (index: Int, origin: Double)?
    @State private var lift: (index: Int, offset: Double)?
    /// Bumped every time something snaps, which is what the haptic keys off.
    @State private var snapCount = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var scale: Double { model.pointsPerSecond }
    private var contentWidth: CGFloat { CGFloat(model.duration * scale) }

    var body: some View {
        ScrollView(.horizontal) {
            ZStack(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 7) {
                    ruler
                    clipRow
                }

                playhead
            }
            .frame(width: max(contentWidth, 1), alignment: .topLeading)
            .padding(.vertical, 6)
            // Scrubbing on the ruler rather than only on the playhead: reaching for a 2pt line is
            // a target-acquisition task, and the whole strip is the target people actually aim at.
            .contentShape(Rectangle())
            .gesture(scrubGesture)
            .simultaneousGesture(zoomGesture)
        }
        .scrollIndicators(.hidden)
        .scrollDisabled(model.isScrubbing || trim != nil || lift != nil)
        .frame(height: 108)
        .sensoryFeedback(.selection, trigger: snapCount)
        .dsMotion(DS.Motion.settle, reduced: reduceMotion, value: model.pointsPerSecond)
    }

    // MARK: - Ruler

    private var ruler: some View {
        let interval = TimelineScale.tickInterval(pointsPerSecond: scale)
        let count = Int(model.duration / interval) + 1

        return ZStack(alignment: .topLeading) {
            ForEach(0..<max(count, 1), id: \.self) { index in
                let seconds = Double(index) * interval
                VStack(alignment: .leading, spacing: 2) {
                    Rectangle()
                        .fill(DS.Palette.hairline(0.22))
                        .frame(width: 1, height: 5)
                    Text(MediaTime(seconds: seconds).timecode)
                        .dsFont(.mono, .medium, 8)
                        .foregroundStyle(DS.Palette.ink(0.34))
                        .fixedSize()
                }
                .offset(x: CGFloat(seconds * scale))
            }
        }
        .frame(height: 18, alignment: .topLeading)
    }

    // MARK: - Clips

    private var clipRow: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(model.project.segments.enumerated()), id: \.element.id) { index, segment in
                clip(segment, at: index)
                    .frame(width: max(CGFloat(segment.barWeight * scale) - 3, 12), height: 64)
                    .offset(x: CGFloat(model.start(at: index) * scale) + CGFloat(lift?.index == index ? lift?.offset ?? 0 : 0))
                    .zIndex(lift?.index == index ? 1 : 0)
            }
        }
        .frame(height: 64, alignment: .topLeading)
    }

    private func clip(_ segment: Segment, at index: Int) -> some View {
        let isSelected = model.inspectedSegment == segment.id
        let isLifted = lift?.index == index
        let isActive = model.isActive(at: index)

        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(DS.Palette.segment(at: segment.role.paletteIndex))

            VStack(alignment: .leading, spacing: 2) {
                Text(segment.role.displayLabel)
                    .dsFont(.archivo, .bold, 12)
                    .foregroundStyle(DS.Palette.inkInverse)
                Text(MediaTime(seconds: segment.barWeight).timecode)
                    .dsFont(.mono, .medium, 9)
                    .foregroundStyle(DS.Palette.inkInverse(0.55))
            }
            .padding(.horizontal, 9)
            .padding(.top, 8)
            .lineLimit(1)
            .allowsHitTesting(false)
        }
        .overlay(alignment: .trailing) {
            if isSelected { trimHandle(at: index) }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(DS.Palette.ink(isSelected ? 0.9 : 0), lineWidth: 2)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .opacity(isActive || isSelected ? 1 : 0.62)
        .scaleEffect(isLifted && !reduceMotion ? 1.04 : 1)
        .shadow(color: .black.opacity(isLifted ? 0.55 : 0), radius: 18, y: 10)
        .dsMotion(DS.Motion.settle, reduced: reduceMotion, value: isLifted)
        .dsMotion(DS.Motion.snap, reduced: reduceMotion, value: isSelected)
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onTapGesture {
            withAnimation(DS.Motion.snap) {
                model.inspectedSegment = segment.id
                model.inspectorTab = .script
            }
        }
        .gesture(reorderGesture(at: index))
    }

    /// Only the trailing edge trims.
    ///
    /// A leading handle would have to move the start of the take inside its file, and until there
    /// is a file there is nothing for it to mean. Shipping one that silently did something else
    /// would be worse than not shipping it.
    private func trimHandle(at index: Int) -> some View {
        let isActive = trim?.index == index
        return RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(DS.Palette.ink)
            .frame(width: isActive ? 6 : 4, height: 30)
            .padding(.trailing, 4)
            .frame(width: 30, height: 64, alignment: .trailing)
            .contentShape(Rectangle())
            .dsMotion(DS.Motion.snap, reduced: reduceMotion, value: isActive)
            .gesture(trimGesture(at: index))
    }

    // MARK: - Playhead

    private var playhead: some View {
        let x = CGFloat(model.playhead * scale)
        return Rectangle()
            .fill(DS.Palette.ink)
            .frame(width: 2, height: 96)
            .overlay(alignment: .top) {
                Capsule()
                    .fill(DS.Palette.ink)
                    .frame(width: model.isScrubbing ? 16 : 11, height: 11)
                    .overlay {
                        Text(model.playheadLabel)
                            .dsFont(.mono, .medium, 9)
                            .foregroundStyle(DS.Palette.ink)
                            .fixedSize()
                            .offset(y: -14)
                            .opacity(model.isScrubbing ? 1 : 0)
                    }
                    .offset(y: -4)
            }
            .shadow(color: .black.opacity(0.6), radius: 5)
            .offset(x: x - 1)
            .allowsHitTesting(false)
            .dsMotion(DS.Motion.snap, reduced: reduceMotion, value: model.isScrubbing)
    }

    // MARK: - Gestures

    private var scrubGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { gesture in
                if scrubOrigin == nil {
                    scrubOrigin = model.playhead
                    model.beginScrub()
                }
                let raw = (scrubOrigin ?? 0) + Double(gesture.translation.width) / scale
                seek(to: raw)
            }
            .onEnded { _ in
                scrubOrigin = nil
                model.endScrub()
            }
    }

    /// Snapping is the reason this is an editing surface and not a slider: a cut that lands one
    /// frame off a boundary is a cut that has to be done again.
    private func seek(to raw: Double) {
        let tolerance = TimelineScale.snapTolerance(pointsPerSecond: scale)
        if let target = model.snapTarget(for: raw, tolerance: tolerance) {
            if abs(model.playhead - target) > 0.001 { snapCount += 1 }
            model.seek(to: target)
        } else {
            model.seek(to: raw)
        }
    }

    private var zoomGesture: some Gesture {
        MagnifyGesture(minimumScaleDelta: 0.01)
            .onChanged { gesture in
                let origin = zoomOrigin ?? model.pointsPerSecond
                if zoomOrigin == nil { zoomOrigin = origin }
                model.pointsPerSecond = TimelineScale.clamp(origin * gesture.magnification)
            }
            .onEnded { _ in zoomOrigin = nil }
    }

    private func trimGesture(at index: Int) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { gesture in
                let origin = trim?.origin ?? model.project.segments[index].barWeight
                if trim == nil { trim = (index, origin) }
                model.setDuration(origin + Double(gesture.translation.width) / scale, forSegmentAt: index)
            }
            .onEnded { _ in trim = nil }
    }

    /// Long press to pick a clip up, then drag it past its neighbours.
    ///
    /// Long press rather than a plain drag because a plain drag is already the scrub, and a
    /// timeline where brushing a clip rearranges the video is a timeline nobody trusts.
    private func reorderGesture(at index: Int) -> some Gesture {
        LongPressGesture(minimumDuration: 0.35)
            .onEnded { _ in
                lift = (index, 0)
                snapCount += 1
            }
            .sequenced(before: DragGesture(minimumDistance: 0))
            .onChanged { value in
                guard case .second(_, let drag?) = value, lift != nil else { return }
                lift = (index, Double(drag.translation.width))
            }
            .onEnded { _ in
                guard let lift else { return }
                let destination = destinationIndex(from: lift.index, offset: lift.offset)
                if destination != lift.index {
                    withAnimation(DS.Motion.settle) {
                        model.move(segmentAt: lift.index, to: destination)
                    }
                    snapCount += 1
                }
                self.lift = nil
            }
    }

    /// Where the clip would land, by how far its centre has travelled past its neighbours.
    private func destinationIndex(from index: Int, offset: Double) -> Int {
        let centre = model.start(at: index) + model.project.segments[index].barWeight / 2 + offset / scale
        var running = 0.0
        for (candidate, segment) in model.project.segments.enumerated() {
            if centre < running + segment.barWeight / 2 { return candidate }
            running += segment.barWeight
        }
        return model.project.segments.count - 1
    }
}
