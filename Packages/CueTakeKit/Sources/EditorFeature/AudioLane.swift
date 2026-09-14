import DesignSystem
import Domain
import SwiftUI

/// The audio lanes, under the footage and on the same ruler.
///
/// Under, not beside, and on the same scale: sound is placed *against* picture, and the only
/// question anyone ever asks of an audio lane is whether this lands where that cut is. A separate
/// audio screen — which is how most phone editors ship it — answers that question by asking the
/// user to remember.
///
/// Clips stack into as many rows as they need. Overlap is the normal case, not an error: a sting
/// over a bed of music is two sounds at one moment, and a single row would have to refuse one.
struct AudioLane: View {
    @Bindable var model: EditorModel
    let scale: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private static let space = "audioLane"

    static let rowHeight: CGFloat = 32
    static let rowSpacing: CGFloat = 4

    /// Which row each clip sits in: the first row whose last clip has already finished.
    ///
    /// Greedy, which is the right answer here — it puts a clip in the row a user would have drawn
    /// it in, and never reshuffles rows that are already settled because a new clip arrived.
    /// `EditorModel.audioRowCount` counts the same rows for the playhead's height.
    private var rows: [AudioClip.ID: Int] {
        var ends: [Double] = []
        var result: [AudioClip.ID: Int] = [:]
        for clip in model.audioClips {
            let start = clip.start.seconds
            if let row = ends.firstIndex(where: { $0 <= start + 0.01 }) {
                ends[row] = clip.timelineRange.end.seconds
                result[clip.id] = row
            } else {
                ends.append(clip.timelineRange.end.seconds)
                result[clip.id] = ends.count - 1
            }
        }
        return result
    }

    var body: some View {
        let placement = rows
        let rowCount = max(1, (placement.values.max() ?? 0) + 1)
        let height = CGFloat(rowCount) * Self.rowHeight + CGFloat(rowCount - 1) * Self.rowSpacing

        return ZStack(alignment: .topLeading) {
            ForEach(model.audioClips) { clip in
                let row = placement[clip.id] ?? 0
                view(for: clip)
                    .frame(
                        width: max(CGFloat(clip.timelineDuration.seconds * scale) - 2, 14),
                        height: Self.rowHeight
                    )
                    .offset(
                        x: CGFloat(clip.start.seconds * scale),
                        y: CGFloat(row) * (Self.rowHeight + Self.rowSpacing)
                    )
                    .zIndex(model.selectedAudio == clip.id ? 1 : 0)
            }
        }
        .frame(height: height, alignment: .topLeading)
        .coordinateSpace(.named(Self.space))
        .animation(reduceMotion ? nil : DS.Motion.settle, value: model.project.audio.count)
    }

    private func view(for clip: AudioClip) -> some View {
        let isSelected = model.selectedAudio == clip.id
        let tint = Self.tint(for: clip.role)

        return ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(tint.opacity(clip.isMuted ? 0.1 : 0.24))

            waveform(for: clip, tint: tint)
                .padding(.horizontal, 4)
                .padding(.vertical, 5)
                .allowsHitTesting(false)

            HStack(spacing: 5) {
                Image(systemName: Self.symbol(for: clip))
                    .font(.system(size: 9, weight: .semibold))
                Text(clip.name)
                    .dsFont(.sans, .medium, 10)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
                // The level, always visible. It is the number people change most, and the one they
                // most need to compare between two clips at a glance.
                Text(Self.levelLabel(for: clip))
                    .dsFont(.mono, .medium, 9)
                    .opacity(0.6)
            }
            .foregroundStyle(DS.Palette.ink(clip.isMuted ? 0.35 : 0.92))
            .padding(.horizontal, 7)
            .allowsHitTesting(false)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(DS.Palette.ink(isSelected ? 0.9 : 0.08), lineWidth: isSelected ? 2 : 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .aiGlow(
            model.glowToken(.audio(clip.id)),
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
        .dsMotion(DS.Motion.snap, reduced: reduceMotion, value: isSelected)
        .timelineBarEditing(
            model: model,
            isSelected: isSelected,
            start: clip.start.seconds,
            end: clip.timelineRange.end.seconds,
            scale: scale,
            space: Self.space,
            edits: TimelineBarEdits(
                move: { start in model.moveAudio(clip.id, to: start) },
                trimStart: { start in model.setAudioStartEdge(clip.id, to: start) },
                trimEnd: { end in model.setAudioEnd(clip.id, to: end) }
            ),
            onTap: {
                withAnimation(DS.Motion.snap) {
                    model.selectedAudio = isSelected ? nil : clip.id
                    model.inspectedSegment = nil
                }
            }
        )
    }

    /// Peaks, drawn as bars.
    ///
    /// Only the part of the file this clip actually uses. A trimmed clip showing the whole song's
    /// waveform is worse than no waveform at all, because it points at the wrong moment
    /// confidently.
    private func waveform(for clip: AudioClip, tint: Color) -> some View {
        let peaks = model.waveforms[clip.id] ?? []

        return Canvas(opaque: false) { context, size in
            guard !peaks.isEmpty, size.width > 1, size.height > 1 else { return }

            // Peaks cover the whole file; this is the window the clip plays.
            let fileSeconds = max(clip.sourceRange.end.seconds, 0.001)
            let secondsPerPeak = fileSeconds / Double(peaks.count)
            let first = clip.sourceRange.start.seconds / max(0.0001, secondsPerPeak)
            let span = clip.sourceRange.duration.seconds / max(0.0001, secondsPerPeak)

            let step: CGFloat = 3
            let columns = max(1, Int(size.width / step))
            let middle = size.height / 2
            let colour = tint.opacity(clip.isMuted ? 0.25 : 0.75)

            for column in 0..<columns {
                let index = Int(first + span * Double(column) / Double(columns))
                guard index >= 0, index < peaks.count else { continue }
                let amplitude = CGFloat(peaks[index]) * middle
                let rect = CGRect(
                    x: CGFloat(column) * step,
                    y: middle - max(amplitude, 0.6),
                    width: 2,
                    height: max(amplitude * 2, 1.2)
                )
                context.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(colour))
            }
        }
    }

    // MARK: - Looks

    static func tint(for role: AudioClip.Role) -> Color {
        switch role {
        case .music: DS.Palette.lime
        case .voiceover: DS.Palette.accent
        case .effect: DS.Palette.ink(0.6)
        }
    }

    static func symbol(for clip: AudioClip) -> String {
        if clip.isMuted { return "speaker.slash.fill" }
        switch clip.role {
        case .music: return "music.note"
        case .voiceover: return "mic.fill"
        case .effect: return "waveform"
        }
    }

    static func levelLabel(for clip: AudioClip) -> String {
        clip.isMuted ? "—" : String(format: "%+.0f", clip.decibels)
    }
}
