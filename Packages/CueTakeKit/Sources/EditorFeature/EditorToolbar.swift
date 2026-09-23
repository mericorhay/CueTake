import DesignSystem
import Domain
import SwiftUI

/// The cutting tools, under the timeline where the hands already are.
///
/// Four of them, and no more. The split is the one that matters — everything a phone editor is for
/// comes down to putting a cut in the right place — and the other three are what you need once you
/// have made one. A toolbar with twelve buttons is a desktop app on a phone; these are the ones
/// that earn their width.
///
/// The row follows the selection. With a clip of footage selected these act on footage; with a
/// piece of music selected they act on the music, in the same four positions. That is deliberate:
/// the muscle memory is in the position, not in the icon, and a second row of audio-only tools
/// would double the toolbar to say the same four things twice.
///
/// Each tool is disabled when it cannot apply rather than hidden, so the row never changes shape
/// under the thumb and nothing moves out from under a tap in flight. Each also has its own piece
/// of motion when it fires — see `ToolFlourish`.
struct EditorToolbar: View {
    @Bindable var model: EditorModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var fired: [ToolKind: Int] = [:]

    private var index: Int? {
        if let inspected = model.inspectedSegment {
            return model.project.segments.firstIndex { $0.id == inspected }
        }
        return model.segmentAtPlayhead?.index
    }

    private var audio: AudioClip? { model.selectedAudioClip }

    var body: some View {
        HStack(spacing: 8) {
            if let audio {
                audioTools(audio)
            } else {
                videoTools
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
        .animation(DS.Motion.snap, value: model.inspectedSegment)
        .animation(DS.Motion.snap, value: model.selectedAudio)
    }

    // MARK: - Footage

    @ViewBuilder
    private var videoTools: some View {
        tool(.split, "scissors", "editor.tool.split", enabled: model.segmentAtPlayhead != nil) {
            model.splitAtPlayhead()
        }

        tool(
            .merge,
            "arrow.trianglehead.merge",
            "editor.tool.merge",
            enabled: index.map { model.canMerge(at: $0) } ?? false
        ) {
            if let index { model.mergeWithNext(at: index) }
        }

        tool(
            .delete,
            "trash",
            "editor.tool.delete",
            enabled: index != nil && model.project.segments.count > 1,
            isDestructive: true
        ) {
            if let index { model.deleteSegment(at: index) }
        }
    }

    // MARK: - Audio

    @ViewBuilder
    private func audioTools(_ clip: AudioClip) -> some View {
        tool(
            .split,
            "scissors",
            "editor.tool.split",
            enabled: model.audioAtPlayhead?.id == clip.id
        ) {
            model.splitAudioAtPlayhead(clip.id)
        }

        tool(
            .mute,
            clip.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
            clip.isMuted ? "editor.tool.unmute" : "editor.tool.mute",
            enabled: true
        ) {
            model.updateAudio(clip.id) { $0.isMuted.toggle() }
        }

        tool(.delete, "trash", "editor.tool.delete", enabled: true, isDestructive: true) {
            model.removeAudio(clip.id)
        }
    }

    // MARK: - A tool

    private func tool(
        _ kind: ToolKind,
        _ symbol: String,
        _ titleKey: String.LocalizationValue,
        enabled: Bool,
        isDestructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            fired[kind, default: 0] += 1
            model.pulse(kind)
            withAnimation(reduceMotion ? .easeOut(duration: 0.15) : DS.Motion.settle) { action() }
        } label: {
            VStack(spacing: 5) {
                icon(kind, symbol: symbol)
                Text(AppLocalization.string(titleKey, bundle: .module))
                    .dsFont(.sans, .medium, 10)
            }
            .foregroundStyle(
                enabled
                    ? (isDestructive ? DS.Palette.accent : DS.Palette.ink(0.85))
                    : DS.Palette.ink(0.22)
            )
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(DS.Palette.hairline(enabled ? 0.07 : 0.03))
            )
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.dsPress(radius: 14))
        .disabled(!enabled)
        .animation(DS.Motion.snap, value: enabled)
    }

    /// Each glyph answers in its own way.
    ///
    /// The system's symbol effects are built from the shape of the symbol itself — the scissors
    /// pivot on their own hinge, the trash lid shakes — which is why these are worth more than any
    /// generic scale-and-fade we could write over the top of them.
    @ViewBuilder
    private func icon(_ kind: ToolKind, symbol: String) -> some View {
        let glyph = Image(systemName: symbol)
            .font(.system(size: 15, weight: .medium))
            .contentTransition(.symbolEffect(.replace))
        let count = fired[kind] ?? 0

        switch kind {
        case .split:
            glyph.symbolEffect(.rotate, value: count)
        case .merge:
            glyph.symbolEffect(.bounce.byLayer, value: count)
        case .duplicate:
            glyph.symbolEffect(.bounce.up, value: count)
        case .delete:
            glyph.symbolEffect(.wiggle, value: count)
        case .mute, .speed, .undo, .redo:
            glyph.symbolEffect(.pulse, value: count)
        }
    }
}
