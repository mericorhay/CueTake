import DesignSystem
import Domain
import SwiftUI

/// What was applied where, under the clips: rows for backgrounds, filters, sound effects and
/// playback, each application a bar as long as the stretch it covers.
///
/// Before this a background, a speed-up or a freeze lived inside a panel and at most a badge on a
/// clip, so after a few edits nobody could tell what had been done to which seconds. Here it reads
/// like a sentence — "blur from 0:04 to 0:09, warm look over the example, echo on the last line" —
/// and every bar is the handle for changing it: tap to open it, drag to move it, pull an end.
struct EffectLane: View {
    @Bindable var model: EditorModel
    let scale: Double
    /// Opens a clip's playback tools.
    var onOpenPlayback: (Segment.ID) -> Void = { _ in }

    static let rowHeight: CGFloat = 24
    static let rowSpacing: CGFloat = 3
    private static let space = "effectLane"
    static let tint = Color(red: 0.4, green: 0.86, blue: 0.76)
    static let filterTint = Color(red: 1.0, green: 0.8, blue: 0.36)
    static let soundTint = Color(red: 0.74, green: 0.66, blue: 1.0)
    static let playbackTint = DS.Palette.accentWarm

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The kinds of effect, each in rows of its own.
    enum Group: CaseIterable {
        case background, filter, sound

        func contains(_ effect: TimelineEffect) -> Bool {
            switch self {
            case .background: effect.background != nil
            case .filter: effect.filter != nil
            case .sound: effect.sound != nil
            }
        }

        var tint: Color {
            switch self {
            case .background: EffectLane.tint
            case .filter: EffectLane.filterTint
            case .sound: EffectLane.soundTint
            }
        }

        var symbol: String {
            switch self {
            case .background: "person.crop.rectangle"
            case .filter: "camera.filters"
            case .sound: "waveform"
            }
        }

        static func of(_ effect: TimelineEffect) -> Group {
            allCases.first { $0.contains(effect) } ?? .background
        }
    }

    // MARK: Layout

    /// Effects stacked into as many rows as overlaps need.
    static func rows(for effects: [TimelineEffect]) -> [TimelineEffect.ID: Int] {
        var ends: [Double] = []
        var result: [TimelineEffect.ID: Int] = [:]
        for effect in effects.sorted(by: { $0.start < $1.start }) {
            if let row = ends.firstIndex(where: { $0 <= effect.start.seconds + 0.01 }) {
                ends[row] = effect.end
                result[effect.id] = row
            } else {
                ends.append(effect.end)
                result[effect.id] = ends.count - 1
            }
        }
        return result
    }

    static func rows(of group: Group, in project: Project) -> Int {
        let effects = project.effects.filter(group.contains)
        guard !effects.isEmpty else { return 0 }
        return (rows(for: effects).values.max() ?? 0) + 1
    }

    static func hasPlaybackRow(in project: Project) -> Bool {
        project.segments.contains { $0.playback.isModified }
    }

    static func rowCount(in project: Project) -> Int {
        Group.allCases.reduce(0) { $0 + rows(of: $1, in: project) } + (hasPlaybackRow(in: project) ? 1 : 0)
    }

    static func height(in project: Project) -> CGFloat {
        let count = rowCount(in: project)
        guard count > 0 else { return 0 }
        return CGFloat(count) * rowHeight + CGFloat(count - 1) * rowSpacing
    }

    /// Where each group's rows begin, and the playback row after them.
    static func firstRows(in project: Project) -> (groups: [Group: Int], playback: Int) {
        var first: [Group: Int] = [:]
        var next = 0
        for group in Group.allCases {
            first[group] = next
            next += rows(of: group, in: project)
        }
        return (first, next)
    }

    var body: some View {
        let project = model.project
        let layout = Self.firstRows(in: project)

        ZStack(alignment: .topLeading) {
            ForEach(Group.allCases, id: \.self) { group in
                let effects = project.effects.filter(group.contains)
                let placement = Self.rows(for: effects)
                ForEach(effects) { effect in
                    effectBar(effect, group: group)
                        .frame(width: max(CGFloat(effect.duration.seconds * scale) - 2, 18), height: Self.rowHeight)
                        .offset(
                            x: CGFloat(effect.start.seconds * scale),
                            y: CGFloat((layout.groups[group] ?? 0) + (placement[effect.id] ?? 0)) * (Self.rowHeight + Self.rowSpacing)
                        )
                        .zIndex(model.selectedEffect == effect.id ? 1 : 0)
                        .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .leading)))
                }
            }

            if Self.hasPlaybackRow(in: project) {
                ForEach(Array(project.segments.enumerated()), id: \.element.id) { index, segment in
                    if segment.playback.isModified {
                        playbackBar(segment, at: index)
                            .frame(width: max(CGFloat(segment.barWeight * scale) - 3, 18), height: Self.rowHeight)
                            .offset(
                                x: CGFloat(model.start(at: index) * scale),
                                y: CGFloat(layout.playback) * (Self.rowHeight + Self.rowSpacing)
                            )
                            .transition(.opacity)
                    }
                }
            }
        }
        .frame(height: Self.height(in: project), alignment: .topLeading)
        .coordinateSpace(.named(Self.space))
        .animation(reduceMotion ? nil : DS.Motion.settle, value: project.effects.count)
    }

    // MARK: Effects

    private func effectBar(_ effect: TimelineEffect, group: Group) -> some View {
        let selected = model.selectedEffect == effect.id
        let rendering = group == .background && model.backgroundProgress != nil
            && (effect.background.map(model.isRenderingBackground) ?? false)

        return HStack(spacing: 5) {
            Image(systemName: group.symbol)
                .font(.system(size: 9, weight: .bold))
            Text(Self.summary(of: effect))
                .dsFont(.sans, .semibold, 10)
                .lineLimit(1)
            Spacer(minLength: 0)
            if rendering {
                ProgressView()
                    .controlSize(.mini)
                    .tint(DS.Palette.inkInverse)
            }
        }
        .foregroundStyle(DS.Palette.inkInverse)
        .padding(.horizontal, selected ? 12 : 7)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(group.tint.opacity(selected ? 1 : 0.72)))
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(DS.Palette.ink, lineWidth: selected ? 2 : 0)
        }
        .aiGlow(model.glowToken(.effect(effect.id)), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .timelineBarEditing(
            model: model,
            isSelected: selected,
            start: effect.start.seconds,
            end: effect.end,
            scale: scale,
            space: Self.space,
            edits: TimelineBarEdits(
                move: { start in
                    model.updateEffect(effect.id, coalescing: "effect-move") { $0.start = MediaTime(seconds: start) }
                },
                trimStart: { start in model.setEffectEdge(effect.id, start: start, coalescing: "effect-start") },
                trimEnd: { end in model.setEffectEdge(effect.id, end: end, coalescing: "effect-end") }
            ),
            onTap: {
                withAnimation(DS.Motion.snap) {
                    model.select(effect: selected ? nil : effect.id)
                }
            }
        )
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    // MARK: Playback

    private func playbackBar(_ segment: Segment, at index: Int) -> some View {
        let selected = model.inspectedSegment == segment.id
        return HStack(spacing: 5) {
            Image(systemName: Self.playbackSymbol(segment.playback))
                .font(.system(size: 9, weight: .bold))
            Text(Self.playbackSummary(segment.playback))
                .dsFont(.mono, .medium, 10)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .foregroundStyle(DS.Palette.inkInverse)
        .padding(.horizontal, 7)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Self.playbackTint.opacity(selected ? 1 : 0.7)))
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(DS.Palette.ink, lineWidth: selected ? 2 : 0)
        }
        .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .onTapGesture {
            withAnimation(DS.Motion.snap) { onOpenPlayback(segment.id) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    // MARK: Labels

    static func summary(of effect: TimelineEffect) -> String {
        if let settings = effect.background { return summary(of: settings) }
        if let filter = effect.filter {
            let name = FilterPresets.label(filter.look)
            return filter.look == .natural || filter.intensity > 0.999 ? name : "\(name) · %\(Int((filter.intensity * 100).rounded()))"
        }
        if let sound = effect.sound {
            let name = SoundPresets.label(sound.preset)
            return abs(sound.volume) > 0.05 ? "\(name) · \(String(format: "%+.0f dB", sound.volume))" : name
        }
        return ""
    }

    static func summary(of settings: BackgroundSettings) -> String {
        let name = ToolDock.label(settings.style)
        guard settings.usesStrength else { return name }
        return "\(name) · %\(Int((settings.strength * 100).rounded()))"
    }

    static func playbackSymbol(_ playback: ClipPlayback) -> String {
        if playback.freeze != nil { return "snowflake" }
        if playback.isReversed { return "backward.fill" }
        return "gauge.with.dots.needle.67percent"
    }

    static func playbackSummary(_ playback: ClipPlayback) -> String {
        if let freeze = playback.freeze { return String(format: "%.1fs", freeze.seconds) }
        return playback.badge ?? ""
    }
}
