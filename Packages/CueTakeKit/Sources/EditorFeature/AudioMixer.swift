import DesignSystem
import Domain
import SwiftUI

// MARK: - Rows

extension EditorModel {
    /// Which row of the audio lane each sound is drawn in.
    ///
    /// A sound the user moved to a row stays in it while that row is free at its moment; the rest
    /// take the first free row, in the order they start. The same answer serves the lane and the
    /// timeline's height.
    public var audioRows: [AudioClip.ID: Int] {
        var occupied: [[ClosedRange<Double>]] = []
        var result: [AudioClip.ID: Int] = [:]

        func isFree(_ row: Int, _ span: ClosedRange<Double>) -> Bool {
            guard occupied.indices.contains(row) else { return true }
            return !occupied[row].contains { $0.overlaps(span) }
        }
        func place(_ clip: AudioClip, in row: Int, _ span: ClosedRange<Double>) {
            while occupied.count <= row { occupied.append([]) }
            occupied[row].append(span)
            result[clip.id] = row
        }
        func span(_ clip: AudioClip) -> ClosedRange<Double> {
            let start = clip.start.seconds
            // A hair shorter, so sounds that touch end to end can share a row.
            return start...max(start, clip.timelineRange.end.seconds - 0.011)
        }

        let clips = audioClips
        for clip in clips {
            guard let lane = clip.lane, lane >= 0, lane < 12 else { continue }
            let range = span(clip)
            if isFree(lane, range) { place(clip, in: lane, range) }
        }
        for clip in clips where result[clip.id] == nil {
            let range = span(clip)
            var row = 0
            while !isFree(row, range) { row += 1 }
            place(clip, in: row, range)
        }
        return result
    }

    /// Moves a sound to another row of the lane: up is towards the pictures.
    public func moveAudio(_ id: AudioClip.ID, byRows offset: Int) {
        guard let row = audioRows[id] else { return }
        let target = max(0, min(row + offset, audioRowCount))
        guard target != row else { return }
        updateAudio(id) { $0.lane = target }
    }

    /// The level of the sound recorded with the footage, 0…1.
    public func setMainVideoVolume(_ volume: Double) {
        record("editor.change.audioAdjust", symbol: "slider.horizontal.3", coalescing: "main-volume")
        project.mainVideoVolume = min(max(volume, 0), 1)
        project.updatedAt = .now
    }

    /// Every added sound silent, or every one back.
    public func setAllAudioMuted(_ muted: Bool) {
        guard !project.audio.isEmpty else { return }
        record(muted ? "editor.tool.mute" : "editor.tool.unmute", symbol: muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
        for index in project.audio.indices { project.audio[index].isMuted = muted }
        project.updatedAt = .now
    }
}

// MARK: - Panel

/// Every sound in the project, in one list: the voice in the footage first, then each added
/// sound with its level, a mute switch and a way to open it.
///
/// Opened from the dock's audio tool once there is more than nothing to manage. Many sounds on
/// one timeline were only reachable one at a time, by finding each bar and tapping it.
struct AudioMixerPanel: View {
    @Bindable var model: EditorModel
    let onAdd: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("editor.mixer.count \(model.project.audio.count)", bundle: .module)
                    .dsFont(.mono, .medium, 10)
                    .foregroundStyle(DS.Palette.ink(0.5))
                    .contentTransition(.numericText())
                Spacer(minLength: 0)
                let allMuted = !model.project.audio.isEmpty && model.project.audio.allSatisfy(\.isMuted)
                Button {
                    withAnimation(DS.Motion.snap) { model.setAllAudioMuted(!allMuted) }
                } label: {
                    Label(
                        String(localized: allMuted ? "editor.mixer.unmuteAll" : "editor.mixer.muteAll", bundle: .module),
                        systemImage: allMuted ? "speaker.wave.2" : "speaker.slash"
                    )
                    .dsFont(.sans, .semibold, 11)
                    .foregroundStyle(DS.Palette.ink(0.75))
                    .padding(.horizontal, 10)
                    .frame(height: 32)
                    .background(Capsule().fill(DS.Palette.hairline(0.08)))
                }
                .buttonStyle(.dsPress(radius: 16))
                .disabled(model.project.audio.isEmpty)

                Button(action: onAdd) {
                    Label(String(localized: "editor.mixer.add", bundle: .module), systemImage: "plus")
                        .dsFont(.sans, .semibold, 11)
                        .foregroundStyle(DS.Palette.inkInverse)
                        .padding(.horizontal, 12)
                        .frame(height: 32)
                        .background(Capsule().fill(DS.Palette.lime))
                }
                .buttonStyle(.dsPress(radius: 16))
            }

            voiceRow

            ForEach(model.audioClips) { clip in
                row(clip)
                    .transition(reduceMotion ? .opacity : .asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .scale(scale: 0.9).combined(with: .opacity)
                    ))
            }
        }
        .animation(reduceMotion ? nil : DS.Motion.settle, value: model.project.audio.map(\.id))
    }

    private var voiceRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "person.wave.2.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(DS.Palette.inkInverse)
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(DS.Palette.ink(0.8)))
            VStack(alignment: .leading, spacing: 2) {
                Text("editor.mixer.voice", bundle: .module)
                    .dsFont(.sans, .semibold, 12)
                    .foregroundStyle(DS.Palette.ink)
                Slider(
                    value: Binding(get: { model.project.mainVideoVolume }, set: { model.setMainVideoVolume($0) }),
                    in: 0...1
                )
                .tint(DS.Palette.ink(0.8))
            }
            Text(verbatim: "\(Int((model.project.mainVideoVolume * 100).rounded()))%")
                .dsFont(.mono, .medium, 10)
                .foregroundStyle(DS.Palette.ink(0.6))
                .frame(width: 38, alignment: .trailing)
                .contentTransition(.numericText())
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(DS.Palette.hairline(0.05)))
    }

    private func row(_ clip: AudioClip) -> some View {
        let tint = AudioLane.tint(for: clip.role)
        return HStack(spacing: 10) {
            Button {
                model.pause()
                model.seek(to: clip.start.seconds + 0.01)
                withAnimation(DS.Motion.settle) {
                    model.selectedAudio = clip.id
                    model.inspectedSegment = nil
                }
            } label: {
                Image(systemName: AudioLane.symbol(for: clip))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DS.Palette.inkInverse)
                    .frame(width: 30, height: 30)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(tint.opacity(clip.isMuted ? 0.35 : 1)))
            }
            .buttonStyle(.dsPressIcon)
            .accessibilityLabel(Text("editor.mixer.open \(clip.name)", bundle: .module))

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(clip.name)
                        .dsFont(.sans, .semibold, 12)
                        .foregroundStyle(DS.Palette.ink(clip.isMuted ? 0.4 : 1))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(verbatim: "\(MediaTime(seconds: clip.start.seconds).timecode) · \(String(format: "%.1f s", clip.timelineDuration.seconds))")
                        .dsFont(.mono, .medium, 9)
                        .foregroundStyle(DS.Palette.ink(0.4))
                        .lineLimit(1)
                        .fixedSize()
                }
                Slider(
                    value: Binding(
                        get: { max(-30, clip.decibels) },
                        set: { value in model.updateAudio(clip.id) { $0.setDecibels(value <= -29.5 ? -60 : value) } }
                    ),
                    in: -30...6
                )
                .tint(tint)
                .disabled(clip.isMuted)
            }

            Text(AudioLane.levelLabel(for: clip))
                .dsFont(.mono, .medium, 10)
                .foregroundStyle(DS.Palette.ink(0.6))
                .frame(width: 30, alignment: .trailing)
                .contentTransition(.numericText())

            Button {
                withAnimation(DS.Motion.snap) { model.updateAudio(clip.id) { $0.isMuted.toggle() } }
            } label: {
                Image(systemName: clip.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(clip.isMuted ? DS.Palette.accent : DS.Palette.ink(0.7))
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(DS.Palette.hairline(0.08)))
            }
            .buttonStyle(.dsPressIcon)
            .accessibilityLabel(Text(clip.isMuted ? "editor.tool.unmute" : "editor.tool.mute", bundle: .module))
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(model.selectedAudio == clip.id ? tint.opacity(0.14) : DS.Palette.hairline(0.05)))
        .contextMenu {
            Button {
                model.duplicateAudio(clip.id)
            } label: {
                Label(String(localized: "editor.tool.duplicate", bundle: .module), systemImage: "plus.square.on.square")
            }
            Button(role: .destructive) {
                withAnimation(DS.Motion.settle) { model.removeAudio(clip.id) }
            } label: {
                Label(String(localized: "editor.tool.delete", bundle: .module), systemImage: "trash")
            }
        }
    }
}
