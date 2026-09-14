import DesignSystem
import Domain
import SwiftUI

/// What was applied where, under the clips: one row per kind of tool, each application a bar as
/// long as the stretch it covers.
///
/// Before this a background, a speed-up or a freeze lived inside a panel and at most a badge on a
/// clip, so after a few edits nobody could tell what had been done to which seconds. Here it reads
/// like a sentence — "blur from 0:04 to 0:09, 1.5× over the example" — and every bar is the handle
/// for changing it: tap to open it, drag to move it, pull an end to stretch it.
struct EffectLane: View {
    @Bindable var model: EditorModel
    let scale: Double
    /// Opens a clip's playback tools.
    var onOpenPlayback: (Segment.ID) -> Void = { _ in }

    static let rowHeight: CGFloat = 24
    private static let space = "effectLane"
    static let rowSpacing: CGFloat = 3
    static let tint = Color(red: 0.4, green: 0.86, blue: 0.76)
    static let playbackTint = DS.Palette.accentWarm

    @State private var origin: (id: TimelineEffect.ID, start: Double, end: Double)?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: Layout

    /// Background effects stacked into as many rows as overlaps need.
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

    static func backgroundRows(in project: Project) -> Int {
        let effects = project.effects.filter { $0.background != nil }
        guard !effects.isEmpty else { return 0 }
        return (rows(for: effects).values.max() ?? 0) + 1
    }

    static func hasPlaybackRow(in project: Project) -> Bool {
        project.segments.contains { $0.playback.isModified }
    }

    static func rowCount(in project: Project) -> Int {
        backgroundRows(in: project) + (hasPlaybackRow(in: project) ? 1 : 0)
    }

    static func height(in project: Project) -> CGFloat {
        let count = rowCount(in: project)
        guard count > 0 else { return 0 }
        return CGFloat(count) * rowHeight + CGFloat(count - 1) * rowSpacing
    }

    var body: some View {
        let backgrounds = model.project.effects.filter { $0.background != nil }
        let placement = Self.rows(for: backgrounds)
        let backgroundRows = Self.backgroundRows(in: model.project)

        ZStack(alignment: .topLeading) {
            ForEach(backgrounds) { effect in
                backgroundBar(effect)
                    .frame(width: max(CGFloat(effect.duration.seconds * scale) - 2, 18), height: Self.rowHeight)
                    .offset(
                        x: CGFloat(effect.start.seconds * scale),
                        y: CGFloat(placement[effect.id] ?? 0) * (Self.rowHeight + Self.rowSpacing)
                    )
                    .zIndex(model.selectedEffect == effect.id ? 1 : 0)
                    .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .leading)))
            }

            if Self.hasPlaybackRow(in: model.project) {
                ForEach(Array(model.project.segments.enumerated()), id: \.element.id) { index, segment in
                    if segment.playback.isModified {
                        playbackBar(segment, at: index)
                            .frame(width: max(CGFloat(segment.barWeight * scale) - 3, 18), height: Self.rowHeight)
                            .offset(
                                x: CGFloat(model.start(at: index) * scale),
                                y: CGFloat(backgroundRows) * (Self.rowHeight + Self.rowSpacing)
                            )
                            .transition(.opacity)
                    }
                }
            }
        }
        .frame(height: Self.height(in: model.project), alignment: .topLeading)
        .coordinateSpace(.named(Self.space))
        .animation(reduceMotion ? nil : DS.Motion.settle, value: model.project.effects.count)
    }

    // MARK: Backgrounds

    private func backgroundBar(_ effect: TimelineEffect) -> some View {
        let selected = model.selectedEffect == effect.id
        let settings = effect.background ?? BackgroundSettings(style: .blur)
        let width = max(CGFloat(effect.duration.seconds * scale) - 2, 18)

        return HStack(spacing: 5) {
            Image(systemName: "person.crop.rectangle")
                .font(.system(size: 9, weight: .bold))
            Text(Self.summary(of: settings))
                .dsFont(.sans, .semibold, 10)
                .lineLimit(1)
            Spacer(minLength: 0)
            if model.backgroundProgress != nil, isRendering(effect) {
                ProgressView()
                    .controlSize(.mini)
                    .tint(DS.Palette.inkInverse)
            }
        }
        .foregroundStyle(DS.Palette.inkInverse)
        .padding(.horizontal, selected ? 12 : 7)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Self.tint.opacity(selected ? 1 : 0.72)))
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(DS.Palette.ink, lineWidth: selected ? 2 : 0)
        }
        .overlay {
            if selected {
                HStack {
                    handle
                    Spacer(minLength: 0)
                    handle
                }
                .padding(.horizontal, 3)
                .allowsHitTesting(false)
            }
        }
        .aiGlow(model.glowToken(.effect(effect.id)), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .onTapGesture {
            withAnimation(DS.Motion.snap) {
                model.select(effect: selected ? nil : effect.id)
            }
        }
        .highPriorityGesture(drag(effect, width: width), including: selected ? .all : .subviews)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    private var handle: some View {
        Capsule()
            .fill(DS.Palette.inkInverse)
            .frame(width: 3, height: 13)
    }

    private func isRendering(_ effect: TimelineEffect) -> Bool {
        guard let settings = effect.background else { return false }
        return model.isRenderingBackground(settings)
    }

    /// From either end's last 22 points it moves that end; from anywhere else it moves the whole
    /// effect. One gesture, because two could not both win against the timeline's scrolling.
    private func drag(_ effect: TimelineEffect, width: CGFloat) -> some Gesture {
        // Measured in the lane, which stays put, not in the bar, which moves under the finger.
        DragGesture(minimumDistance: 3, coordinateSpace: .named(Self.space))
            .onChanged { value in
                if origin?.id != effect.id {
                    origin = (effect.id, effect.start.seconds, effect.end)
                }
                guard let origin else { return }
                let delta = Double(value.translation.width) / scale
                let touch = value.startLocation.x - CGFloat(origin.start * scale)
                if touch < 22 {
                    model.setEffectEdge(effect.id, start: origin.start + delta, coalescing: "effect-start")
                } else if touch > width - 22 {
                    model.setEffectEdge(effect.id, end: origin.end + delta, coalescing: "effect-end")
                } else {
                    model.updateEffect(effect.id, coalescing: "effect-move") {
                        $0.start = MediaTime(seconds: max(0, origin.start + delta))
                    }
                }
            }
            .onEnded { _ in origin = nil }
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
