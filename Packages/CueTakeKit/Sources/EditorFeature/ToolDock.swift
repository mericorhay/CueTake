import DesignSystem
import Domain
import SwiftUI

/// The editing tools, one row under the picture, where a thumb already is.
///
/// The row stays in place while a panel opens below it. Keeping the other tools visible gives
/// editing a stable home and makes switching tools a single tap.
struct ToolDock: View {
    @Bindable var model: EditorModel
    let onCaptions: () -> Void
    let onAddAudio: () -> Void
    let onAddVideo: () -> Void
    let onMore: () -> Void
    /// Sends the editor's document and an instruction to a model; nil hides the AI tool.
    var aiRequest: AIRequester? = nil
    var onAddImage: () -> Void = {}
    var onShowAIChanges: () -> Void = {}

    enum Item: String, CaseIterable, Identifiable {
        case ai, split, trim, speed, background, text, image, video, captions, audio, delete, more
        var id: String { rawValue }

        /// Whether the tool opens a panel rather than acting at once.
        var opensPanel: Bool { self == .trim || self == .speed || self == .ai || self == .background }
    }

    /// The tool whose panel is open. Bound, so the picture above can make room for it.
    @Binding var open: Item?
    @State private var fired: [Item: Int] = [:]
    /// The stretch of the clip a speed, reverse or freeze applies to, and the clip it belongs to.
    @State private var playbackRange: ClosedRange<Double>?
    @State private var playbackRangeClip: Segment.ID?
    /// Where a new background goes: this clip, from the playhead on, or the whole video.
    @State private var backgroundReach: BackgroundReach = .clip

    enum BackgroundReach: Hashable {
        case clip, fromHere, whole
    }
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
        VStack(alignment: .leading, spacing: 10) {
            row

            if let open {
                panel(for: open)
                    .transition(.opacity)
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
                ForEach(visibleItems) { item in
                    chip(item)
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

    private func isEnabled(_ item: Item) -> Bool {
        switch item {
        case .split: model.canSplitAtPlayhead || (model.selectedVideoLayer.map(model.canSplitVideoLayer) ?? false)
        case .trim: index.map { model.project.segments[$0].selectedTake != nil && model.project.segments[$0].playback.freeze == nil } ?? false
        case .speed, .background: index != nil
        case .delete: index != nil && model.project.segments.count > 1
        case .captions, .audio, .video, .more, .ai, .text, .image: true
        }
    }

    private func chip(_ item: Item) -> some View {
        let enabled = isEnabled(item)
        let destructive = item == .delete
        let accent = item == .captions
        let ai = item == .ai

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
                ai ? AnyShapeStyle(AIPalette.blue)
                    : !enabled ? AnyShapeStyle(DS.Palette.ink(0.22))
                    : destructive ? AnyShapeStyle(DS.Palette.accent)
                    : accent ? AnyShapeStyle(DS.Palette.lime)
                    : AnyShapeStyle(DS.Palette.ink(0.88))
            )
            .frame(width: 64, height: 58)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(accent ? DS.Palette.lime(0.1) : DS.Palette.hairline(enabled ? 0.07 : 0.03))
            )
            .overlay {
                if ai {
                    AIRing(shape: RoundedRectangle(cornerRadius: 16, style: .continuous), active: model.isAIDriving)
                } else {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(accent ? DS.Palette.lime(0.3) : DS.Palette.hairline(0.08), lineWidth: 1)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.dsPress(radius: 16))
        .disabled(!enabled)
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(open == item ? (ai ? AIPalette.blue : DS.Palette.lime) : .clear, lineWidth: 2)
                .allowsHitTesting(false)
        }
        .accessibilityAddTraits(open == item ? .isSelected : [])
    }

    @ViewBuilder
    private func icon(_ item: Item) -> some View {
        let count = fired[item] ?? 0
        let glyph = Image(systemName: symbol(item)).font(.system(size: 16, weight: .medium))
        switch item {
        case .split: glyph.symbolEffect(.rotate, value: count)
        case .trim: glyph.symbolEffect(.bounce.byLayer, value: count)
        case .speed: glyph.symbolEffect(.variableColor.iterative, value: count)
        case .delete: glyph.symbolEffect(.wiggle, value: count)
        case .ai: glyph.symbolEffect(.breathe, options: .repeating)
        case .background: glyph.symbolEffect(.bounce, value: count)
        case .text, .image, .video: glyph.symbolEffect(.bounce.up, value: count)
        case .captions, .audio, .more: glyph.symbolEffect(.bounce, value: count)
        }
    }

    private func symbol(_ item: Item) -> String {
        switch item {
        case .ai: "sparkles"
        case .background: "person.crop.rectangle"
        case .text: "textformat"
        case .image: "photo.badge.plus"
        case .video: "rectangle.split.2x1"
        case .split: "scissors"
        case .trim: "arrow.left.and.right.square"
        case .speed: "gauge.with.dots.needle.67percent"
        case .captions: "captions.bubble"
        case .audio: "music.note"
        case .delete: "trash"
        case .more: "square.grid.2x2"
        }
    }

    private func title(_ item: Item) -> String {
        switch item {
        case .ai: String(localized: "editor.dock.ai", bundle: .module)
        case .background: String(localized: "editor.dock.background", bundle: .module)
        case .text: String(localized: "editor.dock.text", bundle: .module)
        case .image: String(localized: "editor.dock.image", bundle: .module)
        case .video: String(localized: "editor.dock.video", bundle: .module)
        case .split: String(localized: "editor.tool.split", bundle: .module)
        case .trim: String(localized: "editor.dock.trim", bundle: .module)
        case .speed: String(localized: "editor.dock.speed", bundle: .module)
        case .captions: String(localized: "editor.captions", bundle: .module)
        case .audio: String(localized: "editor.dock.audio", bundle: .module)
        case .delete: String(localized: "editor.tool.delete", bundle: .module)
        case .more: String(localized: "editor.dock.more", bundle: .module)
        }
    }

    private func activate(_ item: Item) {
        model.pause()
        if item.opensPanel {
            // Preserve the chosen clip by moving the playhead before dismissing its inspector.
            if let index, model.inspectedSegment != nil {
                model.seek(to: model.start(at: index) + 0.01)
            }
            model.inspectedSegment = nil
            model.selectedAudio = nil
            model.select(overlay: nil)
            model.select(effect: nil)
        }
        // A background already under the playhead opens for editing rather than stacking another.
        if item == .background, let existing = model.backgroundAtPlayhead {
            withAnimation(DS.Motion.settle) { model.select(effect: existing.id) }
            return
        }
        if item.opensPanel {
            open = open == item ? nil : item
            return
        }
        let settle = reduceMotion ? Animation.easeOut(duration: 0.15) : DS.Motion.settle
        switch item {
        case .split:
            model.pulse(.split)
            // With an added video selected the razor cuts that video; otherwise the clip.
            if let layer = model.selectedVideoLayer, model.canSplitVideoLayer(layer) {
                withAnimation(settle) { model.splitVideoLayer(layer) }
            } else {
                withAnimation(settle) { model.splitAtPlayhead() }
            }
        case .delete:
            guard let index else { return }
            model.pulse(.delete)
            withAnimation(settle) { model.deleteSegment(at: index) }
        case .text: withAnimation(settle) { model.addTextOverlay() }
        case .image: onAddImage()
        case .video: onAddVideo()
        case .captions: onCaptions()
        case .audio: onAddAudio()
        case .more: onMore()
        case .trim, .speed, .ai, .background: break
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
                if item != .ai, let index {
                    Text(String(localized: "editor.tool.target \(index + 1)", bundle: .module))
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
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(DS.Palette.hairline(0.1)))
                }
                .buttonStyle(.dsPressIcon)
                .accessibilityLabel(Text("editor.panel.close", bundle: .module))
            }

            Group {
                if item == .ai, let aiRequest {
                    AIEditPanel(
                        model: model,
                        request: aiRequest,
                        onStart: { open = nil },
                        onShowChanges: {
                            open = nil
                            onShowAIChanges()
                        }
                    )
                } else if let index {
                    switch item {
                    case .trim: trimPanel(at: index)
                    case .speed: speedPanel(at: index)
                    case .background: backgroundPanel(at: index)
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

    /// The part of the clip playback changes apply to, reset whenever the clip changes.
    private func playbackRangeBinding(at index: Int) -> Binding<ClosedRange<Double>> {
        let segment = model.project.segments[index]
        let whole = 0...segment.barWeight
        return Binding(
            get: {
                guard playbackRangeClip == segment.id, let range = playbackRange,
                      range.upperBound <= segment.barWeight + 0.001
                else { return whole }
                return range
            },
            set: { value in
                playbackRangeClip = segment.id
                playbackRange = value
            }
        )
    }

    private func playbackPlayhead(at index: Int) -> Double? {
        guard let here = model.segmentAtPlayhead, here.index == index else { return nil }
        return here.offset
    }

    /// Applies a playback change to the chosen stretch, and then forgets the stretch: after a split
    /// the clip under the tools is the stretch itself.
    private func applyPlayback(at index: Int, _ change: @escaping (inout ClipPlayback) -> Void) {
        let range = playbackRangeBinding(at: index).wrappedValue
        let segment = model.project.segments[index]
        let isWhole = range.lowerBound < 0.05 && segment.barWeight - range.upperBound < 0.05
        model.pulse(.speed)
        withAnimation(DS.Motion.settle) {
            model.updatePlayback(at: index, range: isWhole ? nil : range, change)
        }
        playbackRange = nil
        playbackRangeClip = nil
    }

    private func speedPanel(at index: Int) -> some View {
        let segment = model.project.segments[index]
        let playback = segment.playback
        let choices: [Double] = [0.5, 0.75, 1, 1.25, 1.5, 2]
        // Frozen and reversed clips are changed whole: their footage does not run forwards under
        // the playhead, so there is no honest place to cut them.
        let canPickRange = playback.freeze == nil && !playback.isReversed && segment.barWeight > 0.8

        return VStack(alignment: .leading, spacing: 10) {
            if canPickRange {
                ClipRangeBar(
                    range: playbackRangeBinding(at: index),
                    length: segment.barWeight,
                    playhead: playbackPlayhead(at: index),
                    tint: EffectLane.playbackTint
                )
            }

            HStack(spacing: 6) {
                ForEach(choices, id: \.self) { speed in
                    let isOn = abs(playback.speed - speed) < 0.001 && playback.freeze == nil
                    Button {
                        applyPlayback(at: index) {
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
                    applyPlayback(at: index) { $0.isReversed.toggle() }
                }
                toggle("editor.dock.freeze", symbol: "snowflake", isOn: playback.freeze != nil, enabled: true) {
                    applyPlayback(at: index) {
                        $0.freeze = $0.freeze == nil ? MediaTime(seconds: 2) : nil
                    }
                }
            }
        }
    }

    static let backgroundChoices: [ClipBackground] = [.blur, .dim, .studio, .black, .white, .green, .color]

    /// Where a new background goes, on the finished video.
    private func backgroundSpan(at index: Int) -> ClosedRange<Double> {
        switch backgroundReach {
        case .clip:
            return model.timelineRange(ofSegmentAt: index)
        case .fromHere:
            let start = model.playhead
            return start...min(model.duration, start + 3)
        case .whole:
            return 0...model.duration
        }
    }

    /// What goes behind the person, and over which stretch: the look is chosen here, and the new
    /// background lands on the timeline selected, ready to be moved, stretched and fine-tuned.
    private func backgroundPanel(at index: Int) -> some View {
        let span = backgroundSpan(at: index)

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                reachChip(.clip, "editor.background.reach.clip")
                reachChip(.fromHere, "editor.background.reach.here")
                reachChip(.whole, "editor.background.reach.whole")
            }

            Text(verbatim: "\(MediaTime(seconds: span.lowerBound).preciseTimecode) – \(MediaTime(seconds: span.upperBound).preciseTimecode)")
                .dsFont(.mono, .medium, 10)
                .foregroundStyle(DS.Palette.ink(0.5))
                .contentTransition(.numericText())

            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(Self.backgroundChoices, id: \.self) { choice in
                        Button {
                            let range = backgroundSpan(at: index)
                            open = nil
                            withAnimation(DS.Motion.settle) {
                                model.addBackground(
                                    BackgroundSettings(style: choice, color: choice == .color ? EffectInspector.colors[0] : nil),
                                    from: range.lowerBound,
                                    to: range.upperBound
                                )
                            }
                        } label: {
                            VStack(spacing: 6) {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Self.swatch(choice))
                                    .frame(width: 52, height: 52)
                                    .overlay {
                                        Image(systemName: "person.fill")
                                            .font(.system(size: 20, weight: .semibold))
                                            .foregroundStyle(choice == .white ? Color.black.opacity(0.75) : Color.white.opacity(0.9))
                                    }
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .strokeBorder(DS.Palette.hairline(0.12), lineWidth: 1)
                                    }
                                Text(Self.label(choice))
                                    .dsFont(.sans, .medium, 10)
                                    .foregroundStyle(DS.Palette.ink(0.6))
                            }
                        }
                        .buttonStyle(.dsPress(radius: 10))
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)
            .scrollClipDisabled()

            Text("editor.background.hint", bundle: .module)
                .dsFont(.sans, .regular, 11, lineHeight: 1.35)
                .foregroundStyle(DS.Palette.ink(0.45))
        }
    }

    private func reachChip(_ reach: BackgroundReach, _ key: String.LocalizationValue) -> some View {
        let isOn = backgroundReach == reach
        return Button {
            withAnimation(DS.Motion.snap) { backgroundReach = reach }
        } label: {
            Text(String(localized: key, bundle: .module))
                .dsFont(.sans, .medium, 12)
                .foregroundStyle(isOn ? DS.Palette.inkInverse : DS.Palette.ink(0.8))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(Capsule().fill(isOn ? EffectLane.tint : DS.Palette.hairline(0.07)))
        }
        .buttonStyle(.dsPress(radius: 20))
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    static func swatch(_ background: ClipBackground?, color: RGBAColor? = nil) -> AnyShapeStyle {
        switch background {
        case nil: AnyShapeStyle(LinearGradient(colors: [Color(red: 0.35, green: 0.3, blue: 0.25), Color(red: 0.2, green: 0.24, blue: 0.3)], startPoint: .topLeading, endPoint: .bottomTrailing))
        case .blur: AnyShapeStyle(LinearGradient(colors: [Color(red: 0.5, green: 0.45, blue: 0.4).opacity(0.8), Color(red: 0.3, green: 0.36, blue: 0.45).opacity(0.8)], startPoint: .top, endPoint: .bottom))
        case .dim: AnyShapeStyle(LinearGradient(colors: [Color(red: 0.22, green: 0.2, blue: 0.18), Color(red: 0.1, green: 0.11, blue: 0.14)], startPoint: .top, endPoint: .bottom))
        case .studio: AnyShapeStyle(RadialGradient(colors: [Color(red: 0.22, green: 0.23, blue: 0.27), Color(red: 0.03, green: 0.03, blue: 0.04)], center: .center, startRadius: 2, endRadius: 40))
        case .black: AnyShapeStyle(Color.black)
        case .white: AnyShapeStyle(Color.white)
        case .green: AnyShapeStyle(Color(red: 0, green: 0.8, blue: 0.25))
        case .color:
            if let color {
                AnyShapeStyle(Color(red: color.red, green: color.green, blue: color.blue))
            } else {
                AnyShapeStyle(AngularGradient(colors: [.red, .yellow, .green, .blue, .purple, .red], center: .center))
            }
        }
    }

    static func label(_ background: ClipBackground?) -> String {
        switch background {
        case nil: String(localized: "editor.background.none", bundle: .module)
        case .blur: String(localized: "editor.background.blur", bundle: .module)
        case .dim: String(localized: "editor.background.dim", bundle: .module)
        case .studio: String(localized: "editor.background.studio", bundle: .module)
        case .black: String(localized: "editor.background.black", bundle: .module)
        case .white: String(localized: "editor.background.white", bundle: .module)
        case .green: String(localized: "editor.background.green", bundle: .module)
        case .color: String(localized: "editor.background.color", bundle: .module)
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
