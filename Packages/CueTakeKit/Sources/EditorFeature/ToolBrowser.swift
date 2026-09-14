import DesignSystem
import Domain
import SwiftUI

/// Everything the editor can do, in one place, sorted by what it does to the video.
///
/// The toolbar under the timeline holds four tools because four is what a thumb can reach without
/// looking. That is the right answer for the tools used every few seconds and the wrong answer for
/// everything else, which until now was simply unreachable unless you already knew which tab it
/// was hiding behind. This is the other half: not a second toolbar, but a place to *find* things —
/// opened deliberately, read rather than tapped blind, and closed again.
///
/// Grouped by effect rather than by which engine implements it. "Reverse" sits next to "Speed"
/// because they are both about time, not because one of them happens to write a file.
struct ToolBrowser: View {
    @Bindable var model: EditorModel

    let onAddAudio: () -> Void
    let onCaptions: () -> Void
    let onExport: () -> Void
    let onTranscriptEdit: () -> Void
    let onClose: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    private var index: Int? {
        if let inspected = model.inspectedSegment {
            return model.project.segments.firstIndex { $0.id == inspected }
        }
        return model.segmentAtPlayhead?.index
    }

    private struct Item: Identifiable {
        var id: String
        var symbol: String
        var title: String.LocalizationValue
        var note: String.LocalizationValue
        var enabled: Bool
        var tint: Color
        var run: () -> Void
    }

    private struct Category: Identifiable {
        var id: String
        var title: String.LocalizationValue
        var symbol: String
        var items: [Item]
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ForEach(Array(categories.enumerated()), id: \.element.id) { order, category in
                        section(category, order: order)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 6)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
        }
        .background(DS.Palette.screen)
        .onAppear {
            guard !reduceMotion else {
                shown = true
                return
            }
            withAnimation(DS.Motion.settle) { shown = true }
        }
    }

    private var header: some View {
        HStack {
            DSKicker(String(localized: "editor.tools.title", bundle: .module))
            Spacer(minLength: 0)
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(DS.Palette.ink(0.6))
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(DS.Palette.hairline(0.08)))
            }
            .buttonStyle(.dsPressIcon)
        }
        .padding(.horizontal, 20)
        .padding(.top, 22)
        .padding(.bottom, 12)
    }

    /// Each category fades up a beat after the one above it.
    ///
    /// Staggering is not decoration here: it gives the eye an order to read the sheet in. Six
    /// groups appearing at once is a wall; six arriving in sequence is a list.
    private func section(_ category: Category, order: Int) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 7) {
                Image(systemName: category.symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DS.Palette.ink(0.45))
                Text(String(localized: category.title, bundle: .module))
                    .dsFont(.archivo, .bold, 15)
                    .foregroundStyle(DS.Palette.ink)
            }

            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)],
                spacing: 8
            ) {
                ForEach(category.items) { item in
                    card(item)
                }
            }
        }
        .opacity(shown ? 1 : 0)
        .offset(y: shown ? 0 : 14)
        .animation(
            reduceMotion ? nil : DS.Motion.settle.delay(Double(order) * 0.05),
            value: shown
        )
    }

    private func card(_ item: Item) -> some View {
        Button {
            item.run()
            onClose()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: item.symbol)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(item.enabled ? item.tint : DS.Palette.ink(0.2))
                    .frame(width: 32, height: 32)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(DS.Palette.hairline(item.enabled ? 0.08 : 0.03))
                    )

                VStack(alignment: .leading, spacing: 1) {
                    Text(String(localized: item.title, bundle: .module))
                        .dsFont(.sans, .semibold, 13)
                        .foregroundStyle(item.enabled ? DS.Palette.ink : DS.Palette.ink(0.25))
                    Text(String(localized: item.note, bundle: .module))
                        .dsFont(.sans, .regular, 10)
                        .foregroundStyle(DS.Palette.ink(0.35))
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .padding(9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(DS.Palette.hairline(0.045))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .stroke(DS.Palette.hairline(0.07), lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        }
        .buttonStyle(.dsPress(radius: 15))
        .disabled(!item.enabled)
    }

    // MARK: - The catalogue

    private var categories: [Category] {
        [cutting, time, sound, words, delivery]
    }

    private var cutting: Category {
        Category(
            id: "cut",
            title: "editor.tools.cut",
            symbol: "scissors",
            items: [
                Item(
                    id: "split",
                    symbol: "scissors",
                    title: "editor.tool.split",
                    note: "editor.tools.split.note",
                    enabled: model.segmentAtPlayhead != nil,
                    tint: DS.Palette.lime
                ) { model.pulse(.split); model.splitAtPlayhead() },

                Item(
                    id: "merge",
                    symbol: "arrow.trianglehead.merge",
                    title: "editor.tool.merge",
                    note: "editor.tools.merge.note",
                    enabled: index.map { model.canMerge(at: $0) } ?? false,
                    tint: DS.Palette.lime
                ) {
                    if let index { model.pulse(.merge); model.mergeWithNext(at: index) }
                },

                Item(
                    id: "delete",
                    symbol: "trash",
                    title: "editor.tool.delete",
                    note: "editor.tools.delete.note",
                    enabled: index != nil && model.project.segments.count > 1,
                    tint: DS.Palette.accent
                ) {
                    if let index { model.pulse(.delete); model.deleteSegment(at: index) }
                },
            ]
        )
    }

    private var time: Category {
        Category(
            id: "time",
            title: "editor.tools.time",
            symbol: "clock",
            items: [
                Item(
                    id: "speed",
                    symbol: "gauge.with.dots.needle.67percent",
                    title: "editor.timing.speed",
                    note: "editor.tools.speed.note",
                    enabled: index != nil,
                    tint: DS.Palette.lime
                ) { open(.timing) },

                Item(
                    id: "reverse",
                    symbol: "arrow.uturn.backward",
                    title: "editor.timing.reverse",
                    note: "editor.tools.reverse.note",
                    enabled: index != nil,
                    tint: DS.Palette.lime
                ) {
                    if let index { model.updatePlayback(at: index) { $0.isReversed.toggle() } }
                    open(.timing)
                },

                Item(
                    id: "freeze",
                    symbol: "snowflake",
                    title: "editor.timing.freeze",
                    note: "editor.tools.freeze.note",
                    enabled: index != nil,
                    tint: DS.Palette.lime
                ) {
                    if let index {
                        model.updatePlayback(at: index) { playback in
                            playback.freeze = playback.freeze == nil ? MediaTime(seconds: 2) : nil
                        }
                    }
                    open(.timing)
                },

                Item(
                    id: "trim",
                    symbol: "arrow.left.and.right",
                    title: "editor.timing.duration",
                    note: "editor.tools.trim.note",
                    enabled: index != nil,
                    tint: DS.Palette.lime
                ) { open(.timing) },
            ]
        )
    }

    private var sound: Category {
        let clip = model.selectedAudioClip

        return Category(
            id: "sound",
            title: "editor.tools.sound",
            symbol: "waveform",
            items: [
                Item(
                    id: "add",
                    symbol: "music.note",
                    title: "editor.audio.add",
                    note: "editor.tools.audioAdd.note",
                    enabled: true,
                    tint: DS.Palette.lime
                ) { onAddAudio() },

                Item(
                    id: "voice",
                    symbol: "person.wave.2",
                    title: model.isVoiceCleaned ? "editor.tools.voice.off" : "editor.tools.voice",
                    note: "editor.tools.voice.note",
                    enabled: model.project.segments.contains { $0.selectedTake != nil },
                    tint: DS.Palette.lime
                ) { model.toggleVoiceCleanup() },

                Item(
                    id: "duck",
                    symbol: "waveform.badge.mic",
                    title: "editor.audio.duck",
                    note: "editor.tools.duck.note",
                    enabled: clip != nil,
                    tint: DS.Palette.lime
                ) {
                    if let clip { model.updateAudio(clip.id) { $0.ducksUnderVoice.toggle() } }
                },

                Item(
                    id: "denoise",
                    symbol: "wind",
                    title: "editor.audio.denoise",
                    note: "editor.tools.denoise.note",
                    enabled: clip != nil,
                    tint: DS.Palette.lime
                ) {
                    if let clip { model.updateAudio(clip.id) { $0.effects.noiseReduction.toggle() } }
                },

                Item(
                    id: "enhance",
                    symbol: "person.wave.2",
                    title: "editor.audio.enhance",
                    note: "editor.tools.enhance.note",
                    enabled: clip != nil,
                    tint: DS.Palette.lime
                ) {
                    if let clip { model.updateAudio(clip.id) { $0.effects.voiceEnhance.toggle() } }
                },

                Item(
                    id: "mute",
                    symbol: "speaker.slash.fill",
                    title: "editor.tool.mute",
                    note: "editor.tools.mute.note",
                    enabled: clip != nil,
                    tint: DS.Palette.accent
                ) {
                    if let clip {
                        model.pulse(.mute)
                        model.updateAudio(clip.id) { $0.isMuted.toggle() }
                    }
                },
            ]
        )
    }

    private var words: Category {
        Category(
            id: "words",
            title: "editor.tools.words",
            symbol: "textformat",
            items: [
                Item(
                    id: "script",
                    symbol: "text.alignleft",
                    title: "editor.tab.script",
                    note: "editor.tools.script.note",
                    enabled: index != nil,
                    tint: DS.Palette.lime
                ) { open(.script) },

                Item(
                    id: "transcript",
                    symbol: "waveform.and.person.filled",
                    title: "editor.tools.transcript",
                    note: "editor.tools.transcript.note",
                    enabled: index != nil,
                    tint: DS.Palette.accent
                ) { onTranscriptEdit() },

                Item(
                    id: "cues",
                    symbol: "text.bubble",
                    title: "editor.tab.caption",
                    note: "editor.tools.cues.note",
                    enabled: index != nil,
                    tint: DS.Palette.lime
                ) { open(.caption) },

                Item(
                    id: "captionStyle",
                    symbol: "textformat.size",
                    title: "editor.captions",
                    note: "editor.tools.captionStyle.note",
                    enabled: true,
                    tint: DS.Palette.lime
                ) { onCaptions() },

                Item(
                    id: "notes",
                    symbol: "note.text",
                    title: "editor.style.notes",
                    note: "editor.tools.notes.note",
                    enabled: index != nil,
                    tint: DS.Palette.lime
                ) { open(.style) },
            ]
        )
    }

    private var delivery: Category {
        Category(
            id: "delivery",
            title: "editor.tools.delivery",
            symbol: "square.and.arrow.up",
            items: [
                Item(
                    id: "takes",
                    symbol: "film.stack",
                    title: "editor.tab.take",
                    note: "editor.tools.takes.note",
                    enabled: index != nil,
                    tint: DS.Palette.lime
                ) { open(.take) },

                Item(
                    id: "export",
                    symbol: "square.and.arrow.up",
                    title: "editor.export",
                    note: "editor.tools.export.note",
                    enabled: true,
                    tint: DS.Palette.accent
                ) { onExport() },
            ]
        )
    }

    /// Opens the panel a tool lives in, selecting a segment first if none is.
    ///
    /// Without this half the catalogue would be greyed out for the most common state there is —
    /// nothing selected — and the user would have to learn that tapping a clip is a prerequisite.
    private func open(_ tab: EditorModel.InspectorTab) {
        if model.inspectedSegment == nil, let index {
            model.inspectedSegment = model.project.segments[index].id
        }
        model.selectedAudio = nil
        model.inspectorTab = tab
    }
}
