import DesignSystem
import Domain
import SwiftUI

/// A compact camera ribbon. Tap opens the move in the Zoom panel; once selected, the body moves it
/// and either edge changes its range. The visible bar stays slim while its interaction row is 44pt.
struct CameraMotionLane: View {
    @Bindable var model: EditorModel
    let scale: Double
    var onOpen: (Double) -> Void = { _ in }

    static let height: CGFloat = 44
    private static let space = "cameraMotionLane"
    @State private var selectedMove: String?

    private struct DisplayMove: Identifiable {
        var id: String
        var recipeID: CameraMotionRecipe.ID
        var recordingID: Recording.ID
        var start: Double
        var duration: Double
        var kind: CameraMotionRecipe.Kind
        var segmentStart: Double
        var segmentEnd: Double
        var takeStart: Double
        var takeLength: Double
        var playback: ClipPlayback
        var editable: Bool

        var end: Double { start + duration }
        var middle: Double { start + duration / 2 }

        func sourceTime(at timelineTime: Double) -> Double {
            let local = min(max(timelineTime - segmentStart, 0), segmentEnd - segmentStart)
            return takeStart + playback.sourceOffset(forTimeline: local, sourceLength: takeLength)
        }
    }

    var body: some View {
        ZStack(alignment: .leading) {
            Capsule()
                .fill(DS.Palette.hairline(0.045))
                .frame(height: 28)
                .frame(height: Self.height)

            ForEach(moves) { move in
                moveBar(move)
                // Draw the true time width. A forced minimum made two short adjacent moves paint
                // over each other and hid which one would actually render.
                .frame(width: max(CGFloat(move.duration * scale) - 2, 4), height: Self.height)
                .offset(x: CGFloat(move.start * scale))
                .zIndex(selectedMove == move.id ? 1 : 0)
                .transition(.opacity.combined(with: .scale(scale: 0.92, anchor: .leading)))
            }
        }
        .frame(width: max(CGFloat(model.timelineDuration * scale), 1), height: Self.height, alignment: .leading)
        .coordinateSpace(.named(Self.space))
        .animation(DS.Motion.settle, value: moves.map(\.id))
        .onChange(of: moves.map(\.id)) { _, ids in
            if let selectedMove, !ids.contains(selectedMove) { self.selectedMove = nil }
        }
    }

    @ViewBuilder
    private func moveBar(_ move: DisplayMove) -> some View {
        let selected = selectedMove == move.id
        let bar = HStack(spacing: 5) {
            Image(systemName: symbol(move.kind))
                .font(.system(size: 9, weight: .bold))
            if move.duration * scale > 72 {
                Text(title(move.kind), bundle: .module)
                    .dsFont(.sans, .semibold, 9)
                    .lineLimit(1)
            }
        }
        .foregroundStyle(DS.Palette.inkInverse)
        .padding(.horizontal, selected ? 12 : 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 28)
        .background(Capsule().fill(DS.gradient(100, [DS.Palette.lime, DS.Palette.accentWarm])))
        .overlay { Capsule().stroke(DS.Palette.ink, lineWidth: selected ? 2 : 0) }
        .clipped()
        .frame(height: Self.height)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)

        if move.editable {
            bar.timelineBarEditing(
                model: model,
                isSelected: selected,
                start: move.start,
                end: move.end,
                scale: scale,
                space: Self.space,
                edits: TimelineBarEdits(
                    move: { start in moveRecipe(move, to: start) },
                    trimStart: { start in trim(move, visibleStart: start) },
                    trimEnd: { end in trim(move, visibleEnd: end) }
                ),
                onTap: { select(move) }
            )
            .accessibilityHint(Text("editor.cameraLane.editHint", bundle: .module))
        } else {
            bar
                .contentShape(Rectangle())
                .onTapGesture { select(move) }
        }
    }

    private func select(_ move: DisplayMove) {
        withAnimation(DS.Motion.snap) { selectedMove = move.id }
        onOpen(move.middle)
    }

    private func moveRecipe(_ move: DisplayMove, to proposedStart: Double) {
        let start = min(max(proposedStart, move.segmentStart), max(move.segmentStart, move.segmentEnd - move.duration))
        let first = move.sourceTime(at: start)
        let last = move.sourceTime(at: start + move.duration)
        model.setCameraMotionRange(
            recordingID: move.recordingID,
            motionID: move.recipeID,
            sourceStart: min(first, last),
            sourceEnd: max(first, last),
            coalescing: "move"
        )
    }

    private func trim(_ move: DisplayMove, visibleStart: Double) {
        let edge = min(max(visibleStart, move.segmentStart), move.end - 0.1)
        let source = move.sourceTime(at: edge)
        model.setCameraMotionEdge(
            recordingID: move.recordingID,
            motionID: move.recipeID,
            sourceStart: move.playback.isReversed ? nil : source,
            sourceEnd: move.playback.isReversed ? source : nil,
            coalescing: "start"
        )
    }

    private func trim(_ move: DisplayMove, visibleEnd: Double) {
        let edge = max(min(visibleEnd, move.segmentEnd), move.start + 0.1)
        let source = move.sourceTime(at: edge)
        model.setCameraMotionEdge(
            recordingID: move.recordingID,
            motionID: move.recipeID,
            sourceStart: move.playback.isReversed ? source : nil,
            sourceEnd: move.playback.isReversed ? nil : source,
            coalescing: "end"
        )
    }

    private var moves: [DisplayMove] {
        var timelineStart = 0.0
        var result: [DisplayMove] = []
        for segment in model.project.segments {
            defer { timelineStart += segment.barWeight }
            guard let take = segment.selectedTake,
                  let recording = model.project.recording(id: take.recordingID),
                  segment.playback.freeze == nil
            else { continue }
            let takeStart = take.sourceRange.start.seconds
            let takeEnd = take.sourceRange.end.seconds
            let takeLength = take.sourceRange.duration.seconds
            for recipe in recording.cameraMotions ?? [] {
                let sourceStart = max(recipe.start, takeStart)
                let sourceEnd = min(recipe.end, takeEnd)
                guard sourceEnd - sourceStart > 0.01 else { continue }
                func localTimeline(_ source: Double) -> Double? {
                    let offset = source - takeStart
                    return segment.playback.timelineOffset(forSourceOffset: offset, sourceLength: takeLength)
                }
                guard let first = localTimeline(sourceStart), let last = localTimeline(sourceEnd) else { continue }
                result.append(DisplayMove(
                    id: "\(segment.id.uuidString)-\(recipe.id.uuidString)",
                    recipeID: recipe.id,
                    recordingID: recording.id,
                    start: timelineStart + min(first, last),
                    duration: abs(last - first),
                    kind: recipe.kind.facingTimeline(isReversed: segment.playback.isReversed),
                    segmentStart: timelineStart,
                    segmentEnd: timelineStart + segment.barWeight,
                    takeStart: takeStart,
                    takeLength: takeLength,
                    playback: segment.playback,
                    // A recipe crossing a split appears as two clipped ribbons. It remains
                    // selectable, but neither fragment pretends it can move the whole range.
                    editable: recipe.start >= takeStart - 0.0001 && recipe.end <= takeEnd + 0.0001
                ))
            }
        }
        return result
    }

    static func hasVisibleMoves(in project: Project) -> Bool {
        project.segments.contains { segment in
            guard segment.playback.freeze == nil,
                  let take = segment.selectedTake,
                  let recording = project.recording(id: take.recordingID)
            else { return false }
            return (recording.cameraMotions ?? []).contains {
                $0.end > take.sourceRange.start.seconds + 0.0001
                    && $0.start < take.sourceRange.end.seconds - 0.0001
            }
        }
    }

    private func symbol(_ kind: CameraMotionRecipe.Kind) -> String {
        switch kind {
        case .hold: "viewfinder.circle"
        case .pushIn: "arrow.down.right"
        case .pullOut: "arrow.up.left"
        case .punch: "bolt.fill"
        }
    }

    private func title(_ kind: CameraMotionRecipe.Kind) -> LocalizedStringKey {
        switch kind {
        case .hold: "editor.zoom.static"
        case .pushIn: "editor.zoom.push"
        case .pullOut: "editor.zoom.pull"
        case .punch: "editor.zoom.punch"
        }
    }
}
