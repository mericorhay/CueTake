import DesignSystem
import Domain
import SwiftUI

/// Every caption on the timeline, to scale under the clips: the one on screen lit, a tap goes to it,
/// a long press opens it for editing.
///
/// It used to be a separate strip, stretched to the width of the screen and blind to zoom and
/// scroll, showing the first words of each clip's script rather than its captions — so it pointed
/// at nothing and a tap did nothing.
struct CaptionLane: View {
    @Bindable var model: EditorModel
    let scale: Double
    let onSeek: (Double) -> Void
    let onEdit: (CaptionCue.ID) -> Void

    static let height: CGFloat = 26

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let cues = model.project.captionCues
        let now = MediaTime(seconds: model.playhead)
        let active = cues.first { $0.range.contains(now) }?.id

        ZStack(alignment: .topLeading) {
            ForEach(cues) { cue in
                let isOn = cue.id == active
                let width = max(CGFloat(cue.range.duration.seconds * scale) - 2, 8)
                Text(cue.text)
                    .dsFont(.sans, isOn ? .semibold : .medium, 10)
                    .foregroundStyle(isOn ? DS.Palette.inkInverse : DS.Palette.ink(0.72))
                    .lineLimit(1)
                    .padding(.horizontal, 6)
                    .frame(width: width, height: Self.height, alignment: .leading)
                    .clipped()
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(isOn ? DS.Palette.lime : DS.Palette.hairline(0.07))
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(DS.Palette.hairline(isOn ? 0 : 0.08), lineWidth: 1)
                    }
                    .scaleEffect(isOn && !reduceMotion ? 1.04 : 1, anchor: .bottom)
                    .shadow(color: DS.Palette.lime.opacity(isOn ? 0.35 : 0), radius: 6)
                    .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .onTapGesture { onSeek(cue.range.start.seconds + 0.01) }
                    .onLongPressGesture(minimumDuration: 0.35) { onEdit(cue.id) }
                    .offset(x: CGFloat(cue.range.start.seconds * scale))
                    .zIndex(isOn ? 1 : 0)
            }
        }
        .frame(height: Self.height, alignment: .topLeading)
        .animation(reduceMotion ? nil : DS.Motion.snap, value: active)
        .aiGlow(
            model.glowToken(.captionStyle) + model.glowToken(.captionWindow),
            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
        )
    }
}
