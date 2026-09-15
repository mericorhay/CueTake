import DesignSystem
import Domain
import SwiftUI

/// A compact camera ribbon. It makes automatic movement visible without exposing a graph editor or
/// stealing height from the picture. The lane is informational in this first slice; editing stays
/// in the Zoom panel directly above it.
struct CameraMotionLane: View {
    @Bindable var model: EditorModel
    let scale: Double

    static let height: CGFloat = 28

    private struct DisplayMove: Identifiable {
        var id: String
        var start: Double
        var duration: Double
        var kind: CameraMotionRecipe.Kind
    }

    var body: some View {
        ZStack(alignment: .leading) {
            Capsule()
                .fill(DS.Palette.hairline(0.045))
                .frame(height: Self.height)

            ForEach(moves) { move in
                HStack(spacing: 5) {
                    Image(systemName: symbol(move.kind))
                        .font(.system(size: 9, weight: .bold))
                    if move.duration * scale > 72 {
                        Text(title(move.kind), bundle: .module)
                            .dsFont(.sans, .semibold, 9)
                            .lineLimit(1)
                    }
                }
                .foregroundStyle(DS.Palette.inkInverse)
                .padding(.horizontal, 8)
                .frame(width: max(CGFloat(move.duration * scale) - 2, 24), height: Self.height - 4, alignment: .leading)
                .background(
                    Capsule().fill(
                        DS.gradient(100, [DS.Palette.lime, DS.Palette.accentWarm])
                    )
                )
                .offset(x: CGFloat(move.start * scale))
                .transition(.opacity.combined(with: .scale(scale: 0.92, anchor: .leading)))
            }
        }
        .frame(height: Self.height)
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("editor.cameraLane.accessibility \(moves.count)", bundle: .module))
        .animation(DS.Motion.settle, value: moves.map(\.id))
    }

    private var moves: [DisplayMove] {
        var timelineStart = 0.0
        var result: [DisplayMove] = []
        for segment in model.project.segments {
            defer { timelineStart += segment.barWeight }
            guard let take = segment.selectedTake,
                  let recording = model.project.recording(id: take.recordingID)
            else { continue }
            let takeStart = take.sourceRange.start.seconds
            let takeEnd = take.sourceRange.end.seconds
            let takeLength = take.sourceRange.duration.seconds
            for recipe in recording.cameraMotions ?? [] {
                let sourceStart = max(recipe.start, takeStart)
                let sourceEnd = min(recipe.end, takeEnd)
                guard sourceEnd - sourceStart > 0.01 else { continue }
                func localTimeline(_ source: Double) -> Double {
                    let offset = source - takeStart
                    let played = segment.playback.isReversed ? takeLength - offset : offset
                    return segment.playback.timelineSeconds(forSource: played)
                }
                let first = localTimeline(sourceStart)
                let last = localTimeline(sourceEnd)
                result.append(DisplayMove(
                    id: "\(segment.id.uuidString)-\(recipe.id.uuidString)",
                    start: timelineStart + min(first, last),
                    duration: abs(last - first),
                    kind: recipe.kind
                ))
            }
        }
        return result
    }

    private func symbol(_ kind: CameraMotionRecipe.Kind) -> String {
        switch kind {
        case .pushIn: "arrow.down.right"
        case .pullOut: "arrow.up.left"
        case .punch: "bolt.fill"
        }
    }

    private func title(_ kind: CameraMotionRecipe.Kind) -> LocalizedStringKey {
        switch kind {
        case .pushIn: "editor.zoom.push"
        case .pullOut: "editor.zoom.pull"
        case .punch: "editor.zoom.punch"
        }
    }
}
