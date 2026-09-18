import DesignSystem
import Domain
import SwiftUI

/// Where the picture follows a subject: one bar per clip, with a mark wherever the subject was
/// lost. Tap selects it; selected, either end shortens the stretch that follows.
struct SubjectTrackLane: View {
    @Bindable var model: EditorModel
    let scale: Double
    var onSeek: (Double) -> Void = { _ in }

    static let height: CGFloat = 36
    static let tint = DS.Palette.accent
    private static let space = "subjectTrackLane"

    var body: some View {
        let spans = model.subjectTrackSpans
        ZStack(alignment: .leading) {
            Capsule()
                .fill(DS.Palette.hairline(0.045))
                .frame(height: 24)
                .frame(height: Self.height)

            ForEach(spans) { span in
                bar(span)
                    .frame(width: max(CGFloat((span.end - span.start) * scale) - 2, 6), height: Self.height)
                    .offset(x: CGFloat(span.start * scale))
                    .zIndex(model.selectedSubjectTrack == span.segmentID ? 1 : 0)
                    .transition(.opacity)
            }
        }
        .frame(width: max(CGFloat(model.timelineDuration * scale), 1), height: Self.height, alignment: .leading)
        .coordinateSpace(.named(Self.space))
        .animation(DS.Motion.settle, value: spans.map(\.id))
    }

    private func bar(_ span: SubjectTrackSpan) -> some View {
        let selected = model.selectedSubjectTrack == span.segmentID
        return HStack(spacing: 5) {
            Image(systemName: "scope")
                .font(.system(size: 9, weight: .bold))
            if (span.end - span.start) * scale > 70 {
                Text("editor.trackLane.title", bundle: .module)
                    .dsFont(.sans, .semibold, 10)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if !span.issueTimes.isEmpty, (span.end - span.start) * scale > 40 {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(DS.Palette.accentWarm)
            }
        }
        .foregroundStyle(DS.Palette.ink)
        .padding(.horizontal, selected ? 12 : 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 24)
        .background(Capsule().fill(Self.tint.opacity(selected ? 0.55 : 0.32)))
        // Where the subject was lost, drawn where it happened.
        .overlay(alignment: .leading) {
            ZStack(alignment: .leading) {
                ForEach(span.issueTimes, id: \.self) { time in
                    Capsule()
                        .fill(DS.Palette.accentWarm)
                        .frame(width: 3, height: 14)
                        .offset(x: CGFloat((time - span.start) * scale))
                }
            }
            .allowsHitTesting(false)
        }
        .overlay { Capsule().stroke(DS.Palette.ink, lineWidth: selected ? 2 : 0) }
        .clipShape(Capsule())
        .frame(height: Self.height)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(Text("editor.trackLane.title", bundle: .module))
        .timelineBarEditing(
            model: model,
            isSelected: selected,
            start: span.start,
            end: span.end,
            scale: scale,
            space: Self.space,
            edits: TimelineBarEdits(
                move: nil,
                trimStart: { start in
                    model.setSubjectTrackRange(forSegment: span.segmentID, start: max(start, span.segmentStart), coalescing: "start")
                },
                trimEnd: { end in
                    model.setSubjectTrackRange(forSegment: span.segmentID, end: min(end, span.segmentEnd), coalescing: "end")
                }
            ),
            onTap: {
                withAnimation(DS.Motion.snap) {
                    model.select(subjectTrack: selected ? nil : span.segmentID)
                }
                if !selected { onSeek(span.issueTimes.first ?? span.start + 0.01) }
            }
        )
    }
}
