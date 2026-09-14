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
    /// Opens a caption for editing on the picture.
    var onEditCaption: (CaptionCue.ID) -> Void = { _ in }
    /// Opens a clip's speed, reverse and freeze.
    var onOpenPlayback: (Segment.ID) -> Void = { _ in }

    @State private var zoomOrigin: Double?
    @State private var trim: (index: Int, origin: Double)?
    @State private var lift: (index: Int, offset: Double)?
    /// Bumped every time something snaps, which is what the haptic keys off.
    @State private var snapCount = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var scale: Double { model.pointsPerSecond }
    /// The audio can run past the last clip — an outro over black is a real thing — so the surface
    /// is as long as the longest of the two, not as long as the footage.
    private var contentWidth: CGFloat { CGFloat(model.timelineDuration * scale) }

    /// Everything under and over the clips that grows the timeline: audio rows and overlay rows.
    private var audioHeight: CGFloat {
        let rows = model.audioRowCount
        let audio = rows > 0
            ? CGFloat(rows) * AudioLane.rowHeight + CGFloat(rows - 1) * AudioLane.rowSpacing + 7
            : 0
        let overlays = model.project.overlays.isEmpty ? 0 : OverlayLane.height(for: model.project.overlays) + 7
        let captions = hasCaptions ? CaptionLane.height + 7 : 0
        let effects = EffectLane.rowCount(in: model.project) > 0 ? EffectLane.height(in: model.project) + 7 : 0
        return audio + overlays + captions + effects
    }

    private var hasCaptions: Bool {
        model.project.segments.contains { !$0.captions.isEmpty }
    }

    /// Where the scroll view is, and whether a finger is moving it.
    @State private var position = ScrollPosition(edge: .leading)
    @State private var viewport: CGFloat = 0
    @State private var userScrolling = false

    /// The playhead stands still in the middle and the timeline moves under it, the way every
    /// phone editor people already know works.
    ///
    /// The old arrangement had a playhead that travelled across a timeline you had to scrub by
    /// grabbing the ruler, and a pinch that always zoomed from the first second — so on a project of
    /// eight clips, zooming in meant losing the clip you were looking at. Now scrolling *is*
    /// scrubbing, the picture follows the timeline as it moves, and a pinch zooms around the moment
    /// under the playhead, which is the moment being worked on.
    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 0) {
                Color.clear.frame(width: viewport / 2)
                surface
                Color.clear.frame(width: viewport / 2)
            }
        }
        .scrollIndicators(.hidden)
        .scrollPosition($position)
        .scrollDisabled(trim != nil || lift != nil)
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { width in
            viewport = width
            follow()
        }
        .onScrollPhaseChange { _, phase in
            let moving = phase == .interacting || phase == .decelerating || phase == .tracking
            if moving, !userScrolling {
                userScrolling = true
                model.beginScrub()
            } else if !moving, userScrolling {
                userScrolling = false
                settleOnSnap()
                model.endScrub()
            }
        }
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.contentOffset.x
        } action: { _, offset in
            guard userScrolling else { return }
            model.seek(to: Double(offset) / scale)
        }
        // Playing, seeking from a button, or zooming: the timeline comes to the playhead.
        .onChange(of: model.playhead) { follow() }
        .onChange(of: model.pointsPerSecond) { follow() }
        .overlay { centreLine }
        .overlay {
            if model.aiSession?.phase == .thinking {
                AIReadingBeam()
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .transition(.opacity)
            }
        }

        .frame(height: 116 + audioHeight)
        .sensoryFeedback(.selection, trigger: snapCount)
    }

    private var surface: some View {
        ZStack(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 7) {
                ruler
                    .frame(width: max(contentWidth, 1), height: 26, alignment: .topLeading)
                    .contentShape(Rectangle())
                    // A tap on a second of the ruler goes to that second.
                    .gesture(
                        SpatialTapGesture().onEnded { tap in
                            jump(to: Double(tap.location.x) / scale)
                        }
                    )
                if !model.project.overlays.isEmpty {
                    OverlayLane(model: model, scale: scale)
                }
                clipRow
                if EffectLane.rowCount(in: model.project) > 0 {
                    EffectLane(model: model, scale: scale, onOpenPlayback: onOpenPlayback)
                }
                if hasCaptions {
                    CaptionLane(
                        model: model,
                        scale: scale,
                        onSeek: { jump(to: $0) },
                        onEdit: { id in
                            if let cue = model.project.captionCues.first(where: { $0.id == id }) {
                                jump(to: cue.range.start.seconds + 0.01)
                            }
                            onEditCaption(id)
                        }
                    )
                }
                if model.audioRowCount > 0 {
                    AudioLane(model: model, scale: scale)
                }
            }

            // The tool's own answer, drawn over the surface it acted on. Keyed by the pulse so
            // using the same tool twice in a row plays twice rather than once.
            if let pulse = model.lastTool {
                ToolFlourish(pulse: pulse)
                    .id(pulse.id)
                    .frame(width: max(contentWidth, 1), height: 96 + audioHeight)
            }

            // The stretch the AI is working on right now.
            if let mark = model.aiScan {
                AIScanBand(mark: mark, scale: scale, height: 92 + audioHeight)
                    .id(mark.id)
                    .padding(.top, 2)
            }
        }
        .frame(width: max(contentWidth, 1), alignment: .topLeading)
        .padding(.vertical, 6)
        .simultaneousGesture(zoomGesture)
    }

    /// Fixed in the middle of the timeline.
    private var centreLine: some View {
        ZStack(alignment: .top) {
            Rectangle()
                .fill(DS.Palette.ink)
                .frame(width: 2)
                .padding(.top, 4)
                .shadow(color: .black.opacity(0.6), radius: 5)

            Capsule()
                .fill(DS.Palette.ink)
                .frame(width: model.isScrubbing ? 16 : 11, height: 11)

            // Under the finger, where the finger is covering the answer.
            if model.isScrubbing {
                ScrubLens(model: model)
                    .offset(y: -34)
                    .transition(.opacity)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .allowsHitTesting(false)
        .dsMotion(DS.Motion.snap, reduced: reduceMotion, value: model.isScrubbing)
    }

    /// Scrolls so the playhead's moment is under the centre line — unless a finger is doing the
    /// scrolling, in which case the finger is in charge.
    private func follow() {
        guard !userScrolling else { return }
        // While the AI works the timeline travels to each change rather than jumping to it, so the
        // eye can follow where it went.
        if model.isAIDriving, !reduceMotion {
            withAnimation(.smooth(duration: 0.45)) {
                position.scrollTo(x: CGFloat(model.playhead * scale))
            }
        } else {
            position.scrollTo(x: CGFloat(model.playhead * scale))
        }
    }

    private func jump(to seconds: Double) {
        model.seek(to: seconds)
        withAnimation(DS.Motion.settle) {
            position.scrollTo(x: CGFloat(model.playhead * scale))
        }
    }

    /// When the timeline comes to rest near a cut, it settles on the cut. A cut that lands one frame
    /// off a boundary is a cut that has to be done again.
    private func settleOnSnap() {
        let tolerance = TimelineScale.snapTolerance(pointsPerSecond: scale)
        guard let target = model.snapTarget(for: model.playhead, tolerance: tolerance),
              abs(target - model.playhead) > 0.001
        else { return }
        snapCount += 1
        jump(to: target)
    }

    // MARK: - Ruler

    private var ruler: some View {
        let interval = TimelineScale.tickInterval(pointsPerSecond: scale)
        let count = Int(model.timelineDuration / interval) + 1

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
        let frames = segment.selectedTakeID.flatMap { model.thumbnails[$0] } ?? []
        let tint = DS.Palette.segment(at: segment.role.paletteIndex)
        // Over pictures the label is light with a shadow; over a flat role colour it stays dark.
        let labelInk = frames.isEmpty ? DS.Palette.inkInverse : DS.Palette.ink

        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(tint)

            if !frames.isEmpty {
                // The shot itself, as a strip of frames. The role colour stays as a cap along the
                // top, so the timeline still reads as hook / intro / point at a glance.
                GeometryReader { proxy in
                    // One tile per 40 points, each showing the frame nearest its place in the
                    // clip, so zooming in shows more of the shot instead of stretching six frames.
                    let tiles = max(1, Int(proxy.size.width / 40))
                    HStack(spacing: 0) {
                        ForEach(0..<tiles, id: \.self) { tile in
                            let frame = frames[min(frames.count - 1, tile * frames.count / tiles)]
                            Image(decorative: frame, scale: 1)
                                .resizable()
                                .scaledToFill()
                                .frame(width: proxy.size.width / CGFloat(tiles), height: proxy.size.height)
                                .clipped()
                        }
                    }
                }
                .overlay {
                    LinearGradient(
                        colors: [.black.opacity(0.55), .black.opacity(0.05)],
                        startPoint: .top,
                        endPoint: .center
                    )
                }
                .overlay(alignment: .top) {
                    tint.frame(height: 4)
                }
                .transition(.opacity)
                .allowsHitTesting(false)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(segment.role.displayLabel)
                    .dsFont(.archivo, .bold, 12)
                    .foregroundStyle(labelInk)
                    .shadow(color: .black.opacity(frames.isEmpty ? 0 : 0.6), radius: 3)
                HStack(spacing: 5) {
                    Text(MediaTime(seconds: segment.barWeight).timecode)
                        .dsFont(.mono, .medium, 9)
                        .foregroundStyle(frames.isEmpty ? DS.Palette.inkInverse(0.55) : DS.Palette.ink(0.8))

                    // What is being done to this clip, on the clip. A speed set in a panel and
                    // visible only in that panel is a setting people forget they turned on.
                    if let badge = segment.playback.badge {
                        Text(badge)
                            .dsFont(.mono, .medium, 8)
                            .foregroundStyle(DS.Palette.inkInverse)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(
                                Capsule().fill(DS.Palette.inkInverse(0.22))
                            )
                    }
                }
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
        .overlay(alignment: .topTrailing) {
            if model.isAITouched(.clip(segment.id)) {
                AISparkle(size: 8)
                    .padding(5)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .opacity(isActive || isSelected ? 1 : 0.62)
        .aiGlow(model.glowToken(.clip(segment.id)), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .scaleEffect(isLifted && !reduceMotion ? 1.04 : 1)
        .shadow(color: .black.opacity(isLifted ? 0.55 : 0), radius: 18, y: 10)
        .dsMotion(DS.Motion.settle, reduced: reduceMotion, value: isLifted)
        .dsMotion(DS.Motion.snap, reduced: reduceMotion, value: isSelected)
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onTapGesture {
            if lift != nil {
                withAnimation(DS.Motion.settle) { lift = nil }
                return
            }
            withAnimation(DS.Motion.snap) {
                model.inspectedSegment = segment.id
                model.inspectorTab = .script
            }
        }
        .onLongPressGesture(minimumDuration: 0.35) {
            withAnimation(DS.Motion.bloom) { lift = (index, 0) }
            snapCount += 1
        }
        .gesture(reorderDrag(at: index), including: isLifted ? .all : .subviews)
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

    // MARK: - Gestures

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

    /// Long press picks a clip up; dragging it then moves it past its neighbours.
    ///
    /// Two steps rather than one gesture. A long press chained into a drag, attached to every clip,
    /// claimed each touch on the clips before the scroll view could see it — which is why the ruler
    /// scrolled and the clips did not. The drag is only attached to a clip that has been lifted, so
    /// every other touch on the timeline belongs to scrolling.
    private func reorderDrag(at index: Int) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { drag in
                guard lift?.index == index else { return }
                lift = (index, Double(drag.translation.width))
            }
            .onEnded { _ in
                guard let lift, lift.index == index else { return }
                let destination = destinationIndex(from: lift.index, offset: lift.offset)
                if destination != lift.index {
                    withAnimation(DS.Motion.settle) {
                        model.move(segmentAt: lift.index, to: destination)
                    }
                    snapCount += 1
                }
                withAnimation(DS.Motion.settle) { self.lift = nil }
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
