import DesignSystem
import Domain
import SwiftUI
import UIKit

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
    /// Opens the camera move under a tapped Camera Lane ribbon.
    var onOpenCameraMotion: (Double) -> Void = { _ in }
    /// The caption open for editing, retimed on its lane.
    var editingCaption: CaptionCue.ID? = nil
    /// The height to fill when the timeline has the screen to itself. Empty space below the lanes
    /// still belongs to the scroll view, so a swipe there scrubs.
    var minimumHeight: CGFloat = 0

    @State private var zoomOrigin: Double?
    @State private var trim: (index: Int, origin: Double)?
    /// The clip whose front is being trimmed, and where its footage started when the finger went down.
    @State private var leadTrim: (index: Int, origin: Double)?
    /// A picked-up clip keeps its identity while the row underneath it previews the result. Using
    /// an id instead of a position matters because a successful drop changes the positions.
    @State private var lift: LiftState?
    /// True from the moment a held clip lifts until the finger lets go (or iOS cancels the touch),
    /// which the UIKit recogniser always reports.
    @State private var reorderGestureActive = false
    /// Bumped every time something snaps, which is what the haptic keys off.
    @State private var snapCount = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum ReorderIntent: Equatable {
        /// Land in the space between clips, moving the surrounding clips around it.
        case insert(Int)
        /// Land on the body of another clip, leaving every other position untouched.
        case swap(Int)

        var symbol: String {
            switch self {
            case .insert: "arrow.right.to.line.compact"
            case .swap: "arrow.left.arrow.right"
            }
        }
    }

    private struct LiftState: Equatable {
        let segmentID: Segment.ID
        let sourceIndex: Int
        var offset: Double
        var verticalOffset: Double
        var tilt: Double
        var intent: ReorderIntent?
    }

    private var scale: Double { model.pointsPerSecond }
    /// The audio can run past the last clip — an outro over black is a real thing — so the surface
    /// is as long as the longest of the two, not as long as the footage.
    private var contentWidth: CGFloat { CGFloat(model.timelineDuration * scale) }

    /// Everything under and over the clips that grows the timeline: audio rows and overlay rows.
    private var audioHeight: CGFloat { Self.lanesHeight(for: model) }

    /// How tall the whole timeline is drawn, for laying it out beside a panel.
    static func height(for model: EditorModel) -> CGFloat { 116 + lanesHeight(for: model) }

    static func lanesHeight(for model: EditorModel) -> CGFloat {
        let hasCaptions = model.project.segments.contains { !$0.captions.isEmpty }
        let rows = model.audioRowCount
        let audio = rows > 0
            ? CGFloat(rows) * AudioLane.rowHeight + CGFloat(rows - 1) * AudioLane.rowSpacing + 7
            : 0
        let overlays = model.project.overlays.isEmpty ? 0 : OverlayLane.height(for: model.project.overlays) + 7
        let captions = hasCaptions ? CaptionLane.height + 7 : 0
        let effects = EffectLane.rowCount(in: model.project) > 0 ? EffectLane.height(in: model.project) + 7 : 0
        let videoLayers = model.project.videoLayers.isEmpty ? 0 : VideoLayerLane.height(for: model.project.videoLayers) + 7
        let camera = CameraMotionLane.hasVisibleMoves(in: model.project)
            ? CameraMotionLane.height + 7
            : 0
        let tracks = model.subjectTrackSpans.isEmpty ? 0 : SubjectTrackLane.height + 7
        let generating = model.generationJobs.isEmpty ? 0 : GenerationGhostLane.height + 7
        return audio + overlays + captions + effects + videoLayers + camera + tracks + generating
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
                    .frame(maxHeight: .infinity, alignment: .top)
                Color.clear.frame(width: viewport / 2)
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .scrollIndicators(.hidden)
        .scrollPosition($position)
        .scrollDisabled(trim != nil || leadTrim != nil || reorderGestureActive || model.isAdjustingTimeline)
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
        .onChange(of: model.playhead) { if !model.isAdjustingTimeline { follow() } }
        // Once the finger lets go, the timeline comes to where the edge was left.
        .onChange(of: model.isAdjustingTimeline) { _, adjusting in
            if !adjusting {
                withAnimation(DS.Motion.settle) {
                    position.scrollTo(x: CGFloat(model.playhead * scale))
                }
            }
        }
        .onChange(of: model.pointsPerSecond) { follow() }
        // Taken off screen mid-scrub (a panel opening swaps the timeline): the scrub ends with it,
        // or the playhead stays deaf to playback.
        .onDisappear {
            if userScrolling {
                userScrolling = false
                model.endScrub()
            }
        }
        .overlay { centreLine }
        .overlay {
            if model.aiSession?.phase == .thinking {
                AIReadingBeam()
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .transition(.opacity)
            }
        }

        .frame(height: max(116 + audioHeight, minimumHeight))
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
                if CameraMotionLane.hasVisibleMoves(in: model.project) {
                    CameraMotionLane(model: model, scale: scale, onOpen: onOpenCameraMotion)
                }
                if !model.subjectTrackSpans.isEmpty {
                    SubjectTrackLane(model: model, scale: scale, onSeek: { jump(to: $0) })
                }
                clipRow
                if !model.generationJobs.isEmpty {
                    GenerationGhostLane(model: model, scale: scale)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
                if !model.project.videoLayers.isEmpty {
                    VideoLayerLane(model: model, scale: scale)
                }
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
                        },
                        editing: editingCaption
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

            // The exact time while scrubbing is read in the timeline heading: a glass bubble
            // above the line collided with that heading and was cut in half.
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
                        .dsFont(.mono, .medium, 10)
                        .foregroundStyle(DS.Palette.ink(0.52))
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
                let isLifted = lift?.segmentID == segment.id
                clip(segment, at: index)
                    .frame(width: max(CGFloat(segment.barWeight * scale) - 3, 12), height: 64)
                    .offset(
                        x: clipStart(for: segment, at: index),
                        y: lift?.segmentID == segment.id ? CGFloat(-10 + (lift?.verticalOffset ?? 0)) : 0
                    )
                    .zIndex(isLifted ? 1 : 0)
                    // Only the row rearranges with a spring. Animating the lifted clip itself
                    // makes it chase the finger, overshoot and appear to fly away.
                    .animation(isLifted || reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.82), value: lift?.intent)
            }

            // The cuts, each with its transition. Hidden while a clip is being carried.
            if lift == nil, model.project.segments.count > 1 {
                TransitionMarks(model: model, scale: scale) { id in
                    model.pause()
                    if let cut = model.cuts.first(where: { $0.after == id }) {
                        jump(to: cut.time)
                    }
                    snapCount += 1
                    withAnimation(DS.Motion.settle) {
                        model.select(transition: model.selectedTransition == id ? nil : id)
                    }
                }
                .zIndex(2)
                .transition(.opacity)
            }
        }
        .frame(height: 64, alignment: .topLeading)
    }

    private func clip(_ segment: Segment, at index: Int) -> some View {
        let isSelected = model.inspectedSegment == segment.id
        let isLifted = lift?.segmentID == segment.id
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
                        .dsFont(.mono, .medium, 10)
                        .foregroundStyle(frames.isEmpty ? DS.Palette.inkInverse(0.55) : DS.Palette.ink(0.8))

                    // What is being done to this clip, on the clip. A speed set in a panel and
                    // visible only in that panel is a setting people forget they turned on.
                    if let badge = segment.playback.badge {
                        Text(badge)
                            .dsFont(.mono, .medium, 10)
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
        .overlay(alignment: .leading) {
            if isSelected, segment.selectedTake != nil, segment.playback.freeze == nil { leadHandle(at: index) }
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
        .rotationEffect(.degrees(isLifted && !reduceMotion ? lift?.tilt ?? 0 : 0))
        .shadow(color: .black.opacity(isLifted ? 0.55 : 0), radius: 18, y: 10)
        .dsMotion(DS.Motion.settle, reduced: reduceMotion, value: isLifted)
        .dsMotion(DS.Motion.snap, reduced: reduceMotion, value: isSelected)
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onTapGesture(coordinateSpace: .local) { location in
            // A tap, not a zero-distance drag: a drag recogniser on every clip swallowed the pan
            // that scrolls the timeline, so a swipe over the clips no longer scrubbed.
            if lift != nil {
                withAnimation(DS.Motion.settle) { lift = nil }
                return
            }
            model.pause()
            // The clip body is also a time ruler. Seeking to the point touched restores the direct
            // "tap the frame you mean" interaction while the scroll view remains free to scrub.
            let local = min(max(Double(location.x) / scale, 0), segment.barWeight)
            jump(to: model.start(at: index) + local)
            snapCount += 1
            withAnimation(DS.Motion.snap) {
                let changedClip = model.inspectedSegment != segment.id
                model.select(cameraMotion: nil)
                model.select(subjectTrack: nil)
                model.inspectedSegment = segment.id
                if changedClip { model.inspectorTab = .script }
            }
        }
        .gesture(reorderGesture(for: segment, at: index))
        // How long the clip is, over it, while either end is pulled.
        .overlay(alignment: .top) {
            if trim?.index == index || leadTrim?.index == index {
                Text(verbatim: String(format: "%.2f s", segment.barWeight))
                    .dsFont(.mono, .medium, 11)
                    .foregroundStyle(DS.Palette.inkInverse)
                    .fixedSize()
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(DS.Palette.ink))
                    .offset(y: -30)
                    .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .top) {
            if isLifted, let intent = lift?.intent {
                Image(systemName: intent.symbol)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(DS.Palette.inkInverse)
                    .frame(width: 28, height: 24)
                    .background(Capsule().fill(DS.Palette.ink))
                    .offset(y: -31)
                    .transition(.scale.combined(with: .opacity))
                    .allowsHitTesting(false)
            }
        }
    }

    /// The front of a clip: pulled right it starts later in its footage, pulled left it brings back
    /// footage from before it. The picture shows the first frame the clip now starts on.
    private func leadHandle(at index: Int) -> some View {
        let isActive = leadTrim?.index == index
        return RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(DS.Palette.ink)
            .frame(width: isActive ? 6 : 4, height: 30)
            .padding(.leading, 4)
            .frame(width: 30, height: 64, alignment: .leading)
            .contentShape(Rectangle())
            .dsMotion(DS.Motion.snap, reduced: reduceMotion, value: isActive)
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { gesture in
                        guard project(index)?.selectedTake != nil else { return }
                        if leadTrim == nil, let take = project(index)?.selectedTake {
                            leadTrim = (index, take.sourceRange.start.seconds)
                            model.isAdjustingTimeline = true
                            model.pause()
                        }
                        guard let leadTrim, let segment = project(index), let take = segment.selectedTake else { return }
                        let speed = min(max(segment.playback.speed, 0.1), 8)
                        let wanted = leadTrim.origin + Double(gesture.translation.width) / scale * speed
                        model.trimStart(by: wanted - take.sourceRange.start.seconds, at: index)
                        model.seek(to: model.start(at: index) + 0.01)
                    }
                    .onEnded { _ in
                        leadTrim = nil
                        model.isAdjustingTimeline = false
                    }
            )
    }

    private func project(_ index: Int) -> Segment? {
        model.project.segments.indices.contains(index) ? model.project.segments[index] : nil
    }

    /// The end of a clip: its length, or how long a held frame is held.
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

    /// Measured on the screen, not on the handle: the handle rides the clip's end, and measured on
    /// itself every step of the drag moved the ruler it was measured against.
    private func trimGesture(at index: Int) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .global)
            .onChanged { gesture in
                guard model.project.segments.indices.contains(index) else { return }
                let origin = trim?.origin ?? model.project.segments[index].barWeight
                if trim == nil {
                    trim = (index, origin)
                    model.isAdjustingTimeline = true
                    model.pause()
                }
                model.setDuration(origin + Double(gesture.translation.width) / scale, forSegmentAt: index)
                let end = model.start(at: index) + model.project.segments[index].barWeight
                model.seek(to: max(model.start(at: index), end - 0.04))
            }
            .onEnded { _ in
                trim = nil
                model.isAdjustingTimeline = false
            }
    }

    /// One continuous hold-and-drag gesture. A hold only arms the gesture; the clip is not lifted
    /// and the timeline is not disabled until the finger deliberately moves. This keeps a tap a
    /// tap, lets a horizontal swipe scrub immediately, and prevents an ordinary selection from
    /// leaving the whole timeline in reorder mode.
    /// Hold, then drag. A UIKit long press rather than a SwiftUI sequence: the SwiftUI long press
    /// chained to a drag claimed every touch on the clips before the scroll view saw it, so a swipe
    /// that started on a clip did not scrub. UIKit's recogniser fails as soon as the finger moves
    /// early, leaving the swipe to the scroll view, and once it fires it follows the same touch.
    private func reorderGesture(for segment: Segment, at index: Int) -> ClipHoldGesture {
        ClipHoldGesture(
            onBegan: {
                reorderGestureActive = true
                withAnimation(DS.Motion.bloom) { beginReorder(segment, at: index) }
            },
            onChanged: { translation in
                updateReorder(with: translation, at: index)
            },
            onEnded: { committed in
                reorderGestureActive = false
                if committed, lift?.segmentID == segment.id {
                    commitReorder(at: index)
                } else {
                    cancelReorder(for: segment.id)
                }
            }
        )
    }

    private func beginReorder(_ segment: Segment, at index: Int) {
        guard lift == nil else { return }
        model.pause()
        lift = LiftState(
            segmentID: segment.id,
            sourceIndex: index,
            offset: 0,
            verticalOffset: 0,
            tilt: 0,
            intent: nil
        )
        snapCount += 1
    }

    private func updateReorder(with translation: CGSize, at index: Int) {
        guard var activeLift = lift, activeLift.sourceIndex == index else { return }
        let offset = clampedReorderOffset(Double(translation.width), from: index)
        let intent = reorderIntent(from: index, offset: offset)
        activeLift.offset = offset
        activeLift.verticalOffset = min(max(Double(translation.height) * 0.10, -3), 4)
        activeLift.tilt = min(max(Double(translation.height) * 0.12, -4), 4)
        let didCrossTarget = activeLift.intent != intent
        activeLift.intent = intent
        lift = activeLift
        if didCrossTarget { snapCount += 1 }
    }

    private func commitReorder(at index: Int) {
        guard let lift, lift.sourceIndex == index else { return }
        switch lift.intent {
        case .swap(let destination) where destination != index:
            model.swapSegments(at: index, with: destination)
            snapCount += 1
        case .insert(let destination) where destination != index:
            model.move(segmentAt: index, to: destination)
            snapCount += 1
        default:
            break
        }
        withAnimation(DS.Motion.settle) { self.lift = nil }
    }

    private func cancelReorder(for segmentID: Segment.ID) {
        guard lift?.segmentID == segmentID else { return }
        withAnimation(DS.Motion.settle) { lift = nil }
    }

    /// A clip body means "swap"; the breathing room either side means "insert". The split is
    /// intentional: it gives the common "swap 1 and 3, leave 2 and 4" edit its own simple move.
    private func reorderIntent(from index: Int, offset: Double) -> ReorderIntent? {
        guard model.project.segments.indices.contains(index) else { return nil }
        let centre = model.start(at: index) + model.project.segments[index].barWeight / 2 + offset / scale

        // Once a swap target is acquired, keep it through a small halo. Touch coordinates vary by
        // fractions of a point even under a still finger; without hysteresis that noise alternates
        // swap/insert every frame and makes the whole row shake left and right.
        if case .swap(let current)? = lift?.intent,
           model.project.segments.indices.contains(current) {
            let segment = model.project.segments[current]
            let start = model.start(at: current)
            let inset = min(segment.barWeight * 0.30, 0.55)
            let halo = min(segment.barWeight * 0.10, 0.22)
            if centre >= start + inset - halo, centre <= start + segment.barWeight - inset + halo {
                return .swap(current)
            }
        }

        for (candidate, segment) in model.project.segments.enumerated() where candidate != index {
            let start = model.start(at: candidate)
            let inset = min(segment.barWeight * 0.30, 0.55)
            if centre >= start + inset, centre <= start + segment.barWeight - inset {
                return .swap(candidate)
            }
        }
        let proposed = destinationIndex(from: index, centre: centre)
        if case .insert(let current)? = lift?.intent,
           current != proposed,
           model.project.segments.indices.contains(current) {
            let currentMidpoint = model.start(at: current) + model.project.segments[current].barWeight / 2
            if abs(centre - currentMidpoint) < 0.16 { return .insert(current) }
        }
        return .insert(proposed)
    }

    /// Keeps a clip inside the timeline while it is held. A fast swipe can report a translation
    /// far beyond the surface; rendering that raw value is what made clips disappear off-screen.
    private func clampedReorderOffset(_ offset: Double, from index: Int) -> Double {
        guard model.project.segments.indices.contains(index) else { return 0 }
        let start = model.start(at: index) * scale
        let width = model.project.segments[index].barWeight * scale
        let lastStart = max(model.timelineDuration * scale - width, 0)
        return min(max(offset, -start), lastStart - start)
    }

    /// Where an inserted clip would land, by how far its centre has travelled past its neighbours.
    private func destinationIndex(from index: Int, centre: Double) -> Int {
        var running = 0.0
        for (candidate, segment) in model.project.segments.enumerated() {
            if centre < running + segment.barWeight / 2 { return candidate }
            running += segment.barWeight
        }
        return model.project.segments.count - 1
    }

    /// Every non-lifted clip previews the pending order, while the lifted one stays under the
    /// finger. This is the thing that makes a gap and a swap legible before the user lets go.
    private func clipStart(for segment: Segment, at index: Int) -> CGFloat {
        guard let lift else { return CGFloat(model.start(at: index) * scale) }
        if lift.segmentID == segment.id {
            return CGFloat(model.start(at: index) * scale + lift.offset)
        }
        let projected = projectedSegments(for: lift)
        var start = 0.0
        for item in projected {
            if item.id == segment.id { return CGFloat(start * scale) }
            start += item.barWeight
        }
        return CGFloat(model.start(at: index) * scale)
    }

    private func projectedSegments(for lift: LiftState) -> [Segment] {
        var segments = model.project.segments
        switch lift.intent {
        case .swap(let destination):
            guard segments.indices.contains(lift.sourceIndex), segments.indices.contains(destination) else { return segments }
            segments.swapAt(lift.sourceIndex, destination)
        case .insert(let destination):
            guard segments.indices.contains(lift.sourceIndex), segments.indices.contains(destination) else { return segments }
            let item = segments.remove(at: lift.sourceIndex)
            segments.insert(item, at: destination)
        case nil:
            break
        }
        return segments
    }
}

/// A long press that keeps reporting where the finger goes after it fires.
struct ClipHoldGesture: UIGestureRecognizerRepresentable {
    var onBegan: () -> Void
    var onChanged: (CGSize) -> Void
    var onEnded: (Bool) -> Void

    final class Coordinator {
        var origin: CGPoint = .zero
    }

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator()
    }

    func makeUIGestureRecognizer(context: Context) -> UILongPressGestureRecognizer {
        let recognizer = UILongPressGestureRecognizer()
        recognizer.minimumPressDuration = 0.32
        // Moving further than this before the hold completes is a swipe: the recogniser fails
        // and the timeline scrolls.
        recognizer.allowableMovement = 10
        return recognizer
    }

    func handleUIGestureRecognizerAction(_ recognizer: UILongPressGestureRecognizer, context: Context) {
        let point = recognizer.location(in: nil)
        switch recognizer.state {
        case .began:
            context.coordinator.origin = point
            onBegan()
        case .changed:
            let origin = context.coordinator.origin
            onChanged(CGSize(width: point.x - origin.x, height: point.y - origin.y))
        case .ended:
            onEnded(true)
        case .cancelled, .failed:
            onEnded(false)
        default:
            break
        }
    }
}
