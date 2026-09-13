import DesignSystem
import Domain
import SwiftUI

/// The editing tools, one row under the picture, where a thumb already is.
///
/// They used to live in a toolbar below the timeline and the caption strip — below the bottom of
/// the phone on most projects, so the cut and trim tools simply were not there. Now they sit
/// directly above the timeline, and the tools that need more than a tap open *out of their own
/// button*: the chip grows into its panel while the rest of the row steps aside one after another,
/// and closing plays the same thing backwards, every tool settling back into its place.
struct ToolDock: View {
    @Bindable var model: EditorModel
    let onCaptions: () -> Void
    let onAddAudio: () -> Void
    let onMore: () -> Void
    /// Sends the editor's document and an instruction to a model; nil hides the AI tool.
    var aiRequest: ((EditDocument, String) async throws -> EditPlan)? = nil
    var onAddImage: () -> Void = {}

    enum Item: String, CaseIterable, Identifiable {
        case ai, split, trim, speed, text, image, captions, audio, duplicate, delete, more
        var id: String { rawValue }

        /// Whether the tool opens a panel rather than acting at once.
        var opensPanel: Bool { self == .trim || self == .speed || self == .ai }
    }

    /// The tool whose panel is open. Bound, so the picture above can make room for it.
    @Binding var open: Item?
    @State private var fired: [Item: Int] = [:]
    @Namespace private var morph
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The clip the tools act on: the one being inspected, or the one under the playhead.
    private var index: Int? {
        if let inspected = model.inspectedSegment,
           let found = model.project.segments.firstIndex(where: { $0.id == inspected }) {
            return found
        }
        return model.segmentAtPlayhead?.index
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            row
                .allowsHitTesting(open == nil)

            if let open {
                panel(for: open)
                    .matchedGeometryEffect(id: open.id, in: morph)
                    .transition(.asymmetric(insertion: .identity, removal: .opacity))
                    .zIndex(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(reduceMotion ? .easeOut(duration: 0.2) : DS.Motion.bloom, value: open)
        // A tool that acts on a clip closes when there is no clip to act on.
        .onChange(of: index == nil) { _, lost in
            // The AI works on the whole video, not the clip under the playhead.
            if lost, open != .ai { open = nil }
        }
    }

    // MARK: - Row

    private var row: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 7) {
                ForEach(Array(visibleItems.enumerated()), id: \.element.id) { position, item in
                    let hidden = open != nil
                    Group {
                        if open == item {
                            // Holds the chip's place while the chip itself is the panel.
                            Color.clear.frame(width: 64, height: 58)
                        } else {
                            chip(item)
                                .matchedGeometryEffect(id: item.id, in: morph)
                        }
                    }
                    // The others step aside in turn, outward from the tool that was opened, and
                    // come back in the same order when it closes.
                    .scaleEffect(hidden && open != item ? 0.6 : 1)
                    .opacity(hidden && open != item ? 0 : 1)
                    .offset(y: hidden && open != item ? 14 : 0)
                    .animation(
                        (reduceMotion ? Animation.easeOut(duration: 0.15) : DS.Motion.settle)
                            .delay(Double(distance(from: position)) * 0.035),
                        value: open
                    )
                }
            }
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
    }

    private var visibleItems: [Item] {
        Item.allCases.filter { $0 != .ai || aiRequest != nil }
    }

    private func distance(from position: Int) -> Int {
        guard let open, let origin = visibleItems.firstIndex(of: open) else { return position }
        return abs(position - origin)
    }

    private func isEnabled(_ item: Item) -> Bool {
        switch item {
        case .split: model.segmentAtPlayhead != nil
        case .trim, .speed, .duplicate: index != nil
        case .delete: index != nil && model.project.segments.count > 1
        case .captions, .audio, .more, .ai, .text, .image: true
        }
    }

    private func chip(_ item: Item) -> some View {
        let enabled = isEnabled(item)
        let destructive = item == .delete
        let accent = item == .captions || item == .ai

        return Button {
            fired[item, default: 0] += 1
            activate(item)
        } label: {
            VStack(spacing: 5) {
                icon(item)
                Text(title(item))
                    .dsFont(.sans, .medium, 10)
                    .lineLimit(1)
            }
            .foregroundStyle(
                !enabled ? DS.Palette.ink(0.22)
                    : destructive ? DS.Palette.accent
                    : accent ? DS.Palette.lime
                    : DS.Palette.ink(0.88)
            )
            .frame(width: 64, height: 58)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(accent ? DS.Palette.lime(0.1) : DS.Palette.hairline(enabled ? 0.07 : 0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(accent ? DS.Palette.lime(0.3) : DS.Palette.hairline(0.08), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.dsPress(radius: 16))
        .disabled(!enabled)
    }

    @ViewBuilder
    private func icon(_ item: Item) -> some View {
        let count = fired[item] ?? 0
        let glyph = Image(systemName: symbol(item)).font(.system(size: 16, weight: .medium))
        switch item {
        case .split: glyph.symbolEffect(.rotate, value: count)
        case .trim: glyph.symbolEffect(.bounce.byLayer, value: count)
        case .speed: glyph.symbolEffect(.variableColor.iterative, value: count)
        case .duplicate: glyph.symbolEffect(.bounce.up, value: count)
        case .delete: glyph.symbolEffect(.wiggle, value: count)
        case .ai: glyph.symbolEffect(.breathe, options: .repeating)
        case .text, .image: glyph.symbolEffect(.bounce.up, value: count)
        case .captions, .audio, .more: glyph.symbolEffect(.bounce, value: count)
        }
    }

    private func symbol(_ item: Item) -> String {
        switch item {
        case .ai: "sparkles"
        case .text: "textformat"
        case .image: "photo.badge.plus"
        case .split: "scissors"
        case .trim: "arrow.left.and.right.square"
        case .speed: "gauge.with.dots.needle.67percent"
        case .captions: "captions.bubble"
        case .audio: "music.note"
        case .duplicate: "plus.square.on.square"
        case .delete: "trash"
        case .more: "square.grid.2x2"
        }
    }

    private func title(_ item: Item) -> String {
        switch item {
        case .ai: String(localized: "editor.dock.ai", bundle: .module)
        case .text: String(localized: "editor.dock.text", bundle: .module)
        case .image: String(localized: "editor.dock.image", bundle: .module)
        case .split: String(localized: "editor.tool.split", bundle: .module)
        case .trim: String(localized: "editor.dock.trim", bundle: .module)
        case .speed: String(localized: "editor.dock.speed", bundle: .module)
        case .captions: String(localized: "editor.captions", bundle: .module)
        case .audio: String(localized: "editor.dock.audio", bundle: .module)
        case .duplicate: String(localized: "editor.tool.duplicate", bundle: .module)
        case .delete: String(localized: "editor.tool.delete", bundle: .module)
        case .more: String(localized: "editor.dock.more", bundle: .module)
        }
    }

    private func activate(_ item: Item) {
        if item.opensPanel {
            open = item
            return
        }
        let settle = reduceMotion ? Animation.easeOut(duration: 0.15) : DS.Motion.settle
        switch item {
        case .split:
            model.pulse(.split)
            withAnimation(settle) { model.splitAtPlayhead() }
        case .duplicate:
            guard let index else { return }
            model.pulse(.duplicate)
            withAnimation(settle) { model.duplicateSegment(at: index) }
        case .delete:
            guard let index else { return }
            model.pulse(.delete)
            withAnimation(settle) { model.deleteSegment(at: index) }
        case .text: withAnimation(settle) { model.addTextOverlay() }
        case .image: onAddImage()
        case .captions: onCaptions()
        case .audio: onAddAudio()
        case .more: onMore()
        case .trim, .speed, .ai: break
        }
    }

    // MARK: - Panels

    private func panel(for item: Item) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: symbol(item))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DS.Palette.accent)
                Text(title(item))
                    .dsFont(.sans, .semibold, 14)
                    .foregroundStyle(DS.Palette.ink)
                if let index {
                    Text(model.project.segments[index].role.displayLabel)
                        .dsFont(.mono, .medium, 10)
                        .foregroundStyle(DS.Palette.ink(0.4))
                }
                Spacer(minLength: 0)
                Button {
                    open = nil
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(DS.Palette.ink)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(DS.Palette.hairline(0.1)))
                }
                .buttonStyle(.dsPressIcon)
            }

            Group {
                if item == .ai, let aiRequest {
                    AIEditPanel(model: model, request: aiRequest)
                } else if let index {
                    switch item {
                    case .trim: trimPanel(at: index)
                    case .speed: speedPanel(at: index)
                    default: EmptyView()
                    }
                }
            }
            .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsGlass(
            tint: DS.Palette.glassSheet(0.92),
            in: RoundedRectangle(cornerRadius: 22, style: .continuous),
            border: DS.Palette.accent(0.35)
        )
    }

    private func trimPanel(at index: Int) -> some View {
        let segment = model.project.segments[index]
        let take = segment.selectedTake
        let total = model.recordingLength(at: index) ?? max(segment.sourceSeconds, 0.01)
        let start = take?.sourceRange.start.seconds ?? 0
        let end = take?.sourceRange.end.seconds ?? segment.sourceSeconds

        return VStack(alignment: .leading, spacing: 12) {
            // The whole recording, with the part in the video lit. Trimming is choosing a window,
            // and this is the window.
            GeometryReader { proxy in
                let width = proxy.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(DS.Palette.hairline(0.08))
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(DS.Palette.segment(at: segment.role.paletteIndex).opacity(0.85))
                        .frame(width: max(6, width * CGFloat((end - start) / total)))
                        .offset(x: width * CGFloat(start / total))
                        .animation(DS.Motion.snap, value: start)
                        .animation(DS.Motion.snap, value: end)
                }
            }
            .frame(height: 18)

            HStack(spacing: 8) {
                trimStepper("editor.dock.trim.start", value: start) { delta in
                    model.trimStart(by: delta, at: index)
                }
                trimStepper("editor.dock.trim.end", value: end) { delta in
                    model.trimEnd(by: delta, at: index)
                }
            }
            .disabled(take == nil || segment.playback.freeze != nil)

            Text("editor.dock.trim.hint", bundle: .module)
                .dsFont(.sans, .regular, 11)
                .foregroundStyle(DS.Palette.ink(0.4))
        }
    }

    private func trimStepper(_ key: String.LocalizationValue, value: Double, onStep: @escaping (Double) -> Void) -> some View {
        HStack(spacing: 0) {
            stepButton("minus") { onStep(-0.1) }
            VStack(spacing: 1) {
                Text(String(localized: key, bundle: .module))
                    .dsFont(.mono, .medium, 8)
                    .foregroundStyle(DS.Palette.ink(0.4))
                Text(verbatim: String(format: "%.1f s", value))
                    .dsFont(.mono, .medium, 13)
                    .foregroundStyle(DS.Palette.ink)
                    .contentTransition(.numericText(value: value))
                    .animation(DS.Motion.snap, value: value)
            }
            .frame(maxWidth: .infinity)
            stepButton("plus") { onStep(0.1) }
        }
        .padding(4)
        .background(Capsule().fill(DS.Palette.hairline(0.06)))
    }

    private func stepButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(DS.Palette.ink)
                .frame(width: 34, height: 34)
                .background(Circle().fill(DS.Palette.hairline(0.08)))
        }
        .buttonRepeatBehavior(.enabled)
        .buttonStyle(.dsPressIcon)
    }

    private func speedPanel(at index: Int) -> some View {
        let playback = model.project.segments[index].playback
        let choices: [Double] = [0.5, 0.75, 1, 1.25, 1.5, 2]

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                ForEach(choices, id: \.self) { speed in
                    let isOn = abs(playback.speed - speed) < 0.001 && playback.freeze == nil
                    Button {
                        model.pulse(.speed)
                        model.updatePlayback(at: index) {
                            $0.speed = speed
                            $0.freeze = nil
                        }
                    } label: {
                        Text(verbatim: speed == floor(speed) ? "\(Int(speed))×" : String(format: "%.2g×", speed))
                            .dsFont(.mono, .medium, 12)
                            .foregroundStyle(isOn ? DS.Palette.inkInverse : DS.Palette.ink(0.75))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 11, style: .continuous)
                                    .fill(isOn ? DS.Palette.accent : DS.Palette.hairline(0.07))
                            )
                    }
                    .buttonStyle(.dsPress(radius: 11))
                    .animation(DS.Motion.snap, value: isOn)
                }
            }

            HStack(spacing: 8) {
                toggle("editor.dock.reverse", symbol: "backward.fill", isOn: playback.isReversed, enabled: playback.freeze == nil) {
                    model.updatePlayback(at: index) { $0.isReversed.toggle() }
                }
                toggle("editor.dock.freeze", symbol: "snowflake", isOn: playback.freeze != nil, enabled: true) {
                    model.updatePlayback(at: index) {
                        $0.freeze = $0.freeze == nil ? MediaTime(seconds: 2) : nil
                    }
                }
            }
        }
    }

    private func toggle(
        _ key: String.LocalizationValue,
        symbol: String,
        isOn: Bool,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .symbolEffect(.bounce, value: isOn)
                Text(String(localized: key, bundle: .module))
                    .dsFont(.sans, .medium, 12)
            }
            .foregroundStyle(isOn ? DS.Palette.inkInverse : DS.Palette.ink(0.8))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(Capsule().fill(isOn ? DS.Palette.lime : DS.Palette.hairline(0.07)))
        }
        .buttonStyle(.dsPress(radius: 20))
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
        .animation(DS.Motion.snap, value: isOn)
    }
}
