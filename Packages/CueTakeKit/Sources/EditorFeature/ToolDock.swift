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
    /// What is being written to the AI, and the bar at the top where it is written.
    var aiDraft: Binding<String> = .constant("")
    var onComposeAI: () -> Void = {}
    /// The prompt for a generated video, and the bar at the top where it is written.
    var generateDraft: Binding<String> = .constant("")
    var onComposeGenerate: () -> Void = {}
    /// Turns cloud AI on from the AI panel. Nil in a build without the assistant.
    var onAllowCloudAI: (() -> Void)? = nil
    var onAddImage: () -> Void = {}
    var onShowAIChanges: () -> Void = {}
    /// Opens the direct-on-picture subject picker owned by the editor screen.
    var onTrack: () -> Void = {}
    /// The timeline stays between the stable tool row and whichever inspector the row opens. This
    /// keeps the edit visible while its controls grow below it instead of pushing it off-screen.
    var inlineTimeline: AnyView? = nil

    enum Item: String, CaseIterable, Identifiable {
        case ai, generate, split, reframe, zoom, trim, speed, background, filter, sound, text, image, video, captions, audio, delete, more
        var id: String { rawValue }

        /// Whether the tool opens a panel rather than acting at once.
        var opensPanel: Bool { [.trim, .speed, .generate, .zoom, .background, .filter, .sound].contains(self) }
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

            if let inlineTimeline {
                inlineTimeline
            }

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

    /// Generating needs the app's help; a build without it shows no such tool.
    private var visibleItems: [Item] { Item.allCases.filter { $0 != .generate || model.canGenerate } }

    private func isEnabled(_ item: Item) -> Bool {
        switch item {
        case .split: model.canSplitAtPlayhead || (model.selectedVideoLayer.map(model.canSplitVideoLayer) ?? false)
        case .trim: index.map { model.project.segments[$0].selectedTake != nil && model.project.segments[$0].playback.freeze == nil } ?? false
        case .speed, .background: index != nil
        case .reframe:
            index.map { model.project.segments[$0].selectedTake != nil && model.project.segments[$0].playback.freeze == nil } ?? false
        case .zoom:
            index.map { model.project.segments[$0].selectedTake != nil } ?? false
        case .filter, .sound: !model.project.segments.isEmpty
        case .delete: index != nil && model.project.segments.count > 1
        case .captions, .audio, .video, .more, .ai, .generate, .text, .image: true
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
        .overlay(alignment: .topTrailing) {
            let working = model.generationJobs.filter { $0.phase == .working }.count
            if item == .generate, working > 0 {
                Text(verbatim: "\(working)")
                    .dsFont(.mono, .semibold, 9)
                    .foregroundStyle(DS.Palette.inkInverse)
                    .frame(minWidth: 16, minHeight: 16)
                    .background(Circle().fill(DS.Palette.lime))
                    .contentTransition(.numericText(value: Double(working)))
                    .offset(x: 4, y: -4)
                    .transition(.scale.combined(with: .opacity))
                    .allowsHitTesting(false)
            }
        }
        .animation(DS.Motion.snap, value: model.generationJobs.filter { $0.phase == .working }.count)
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
        case .generate:
            glyph
                .symbolEffect(.bounce, value: count)
                .symbolEffect(.variableColor.iterative, options: .repeating, isActive: !model.generationJobs.filter { $0.phase == .working }.isEmpty)
        case .background, .reframe, .zoom: glyph.symbolEffect(.bounce, value: count)
        case .text, .image, .video: glyph.symbolEffect(.bounce.up, value: count)
        case .filter: glyph.symbolEffect(.bounce, value: count)
        case .sound: glyph.symbolEffect(.variableColor.iterative, value: count)
        case .captions, .audio, .more: glyph.symbolEffect(.bounce, value: count)
        }
    }

    private func symbol(_ item: Item) -> String {
        switch item {
        case .ai: "sparkles"
        case .generate: "wand.and.stars"
        case .background: "person.crop.rectangle"
        case .reframe: "viewfinder"
        case .zoom: "plus.magnifyingglass"
        case .text: "textformat"
        case .image: "photo.badge.plus"
        case .video: "rectangle.split.2x1"
        case .filter: "camera.filters"
        case .sound: "waveform.badge.plus"
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
        case .generate: String(localized: "editor.dock.generate", bundle: .module)
        case .background: String(localized: "editor.dock.background", bundle: .module)
        case .reframe: String(localized: "editor.track.title", bundle: .module)
        case .zoom: String(localized: "editor.zoom.title", bundle: .module)
        case .text: String(localized: "editor.dock.text", bundle: .module)
        case .image: String(localized: "editor.dock.image", bundle: .module)
        case .video: String(localized: "editor.dock.video", bundle: .module)
        case .filter: String(localized: "editor.dock.filter", bundle: .module)
        case .sound: String(localized: "editor.dock.sound", bundle: .module)
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
        if item.opensPanel || item == .reframe {
            // Preserve the chosen clip by moving the playhead before dismissing its inspector.
            if let index, model.inspectedSegment != nil {
                model.seek(to: model.start(at: index) + 0.01)
            }
        }
        if item.opensPanel {
            model.inspectedSegment = nil
            model.selectedAudio = nil
            model.select(overlay: nil)
            model.select(effect: nil)
        }
        // An effect of the same kind already under the playhead opens for editing rather than
        // stacking another on top of it.
        let existing: TimelineEffect? = switch item {
        case .background: model.backgroundAtPlayhead
        case .filter: model.project.effects.last { $0.filter != nil && $0.start.seconds <= model.playhead + 0.001 && model.playhead < $0.end - 0.001 }
        case .sound: model.project.effects.last { $0.sound != nil && $0.start.seconds <= model.playhead + 0.001 && model.playhead < $0.end - 0.001 }
        default: nil
        }
        if let existing {
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
        case .reframe: onTrack()
        case .ai:
            open = nil
            onComposeAI()
        case .trim, .speed, .generate, .zoom, .background, .filter, .sound: break
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
                if item != .ai, item != .generate, let index {
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
                if item == .generate {
                    GeneratePanel(model: model, draft: generateDraft, onCompose: onComposeGenerate)
                } else if item == .reframe {
                    mainReframePanel
                } else if item == .zoom {
                    zoomPanel
                } else if let index {
                    switch item {
                    case .trim: trimPanel(at: index)
                    case .speed: speedPanel(at: index)
                    case .background: backgroundPanel(at: index)
                    case .filter: filterPanel(at: index)
                    case .sound: soundPanel(at: index)
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

    private var zoomPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("editor.zoom.hint", bundle: .module)
                .dsFont(.sans, .regular, 11, lineHeight: 1.35)
                .foregroundStyle(DS.Palette.ink(0.58))

            HStack(spacing: 7) {
                zoomRecipeButton(.pushIn, title: "editor.zoom.push", symbol: "arrow.down.right")
                zoomRecipeButton(.punch, title: "editor.zoom.punch", symbol: "bolt.fill")
                zoomRecipeButton(.pullOut, title: "editor.zoom.pull", symbol: "arrow.up.left")
            }

            if let recipe = model.cameraMotionAtPlayhead {
                VStack(alignment: .leading, spacing: 9) {
                    HStack(spacing: 8) {
                        Image(systemName: "waveform.path")
                            .foregroundStyle(DS.Palette.lime)
                        Text(zoomRecipeTitle(recipe.kind), bundle: .module)
                            .dsFont(.sans, .semibold, 11)
                            .foregroundStyle(DS.Palette.ink(0.75))
                        Spacer(minLength: 0)
                        Button {
                            withAnimation(DS.Motion.settle) { model.removeCameraMotionAtPlayhead() }
                        } label: {
                            Label(String(localized: "editor.zoom.remove", bundle: .module), systemImage: "xmark")
                                .dsFont(.sans, .semibold, 10)
                                .foregroundStyle(DS.Palette.ink(0.55))
                                .frame(height: 36)
                        }
                        .buttonStyle(.dsPress(radius: 18))
                    }

                    HStack(spacing: 6) {
                        Text("editor.zoom.feel", bundle: .module)
                            .dsFont(.sans, .medium, 10)
                            .foregroundStyle(DS.Palette.ink(0.46))
                        Spacer(minLength: 4)
                        ForEach(CameraMotionRecipe.Feel.allCases, id: \.self) { feel in
                            let active = recipe.feel == feel
                            Button {
                                withAnimation(DS.Motion.snap) { model.setCameraMotionFeel(feel) }
                            } label: {
                                Text(zoomFeelTitle(feel), bundle: .module)
                                    .dsFont(.sans, .semibold, 10)
                                    .foregroundStyle(active ? DS.Palette.inkInverse : DS.Palette.ink(0.62))
                                    .padding(.horizontal, 10)
                                    .frame(height: 32)
                                    .background(Capsule().fill(active ? DS.Palette.lime : DS.Palette.hairline(0.06)))
                            }
                            .buttonStyle(.dsPress(radius: 16))
                            .accessibilityAddTraits(active ? .isSelected : [])
                        }
                    }

                    HStack(spacing: 9) {
                        Image(systemName: "minus.magnifyingglass")
                            .foregroundStyle(DS.Palette.ink(0.45))
                        Slider(
                            value: Binding(
                                get: { 1 + (model.cameraMotionAtPlayhead?.amount ?? 0.15) },
                                set: { model.setCameraMotionAmount($0 - 1) }
                            ),
                            in: 1.02...2.0
                        )
                        .tint(DS.Palette.lime)
                        Text(verbatim: "+%\(Int(((model.cameraMotionAtPlayhead?.amount ?? 0.15) * 100).rounded()))")
                            .dsFont(.mono, .medium, 10)
                            .foregroundStyle(DS.Palette.ink(0.72))
                            .frame(width: 38, alignment: .trailing)
                    }
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(DS.Palette.lime(0.08)))
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            DSKicker(String(localized: "editor.zoom.static", bundle: .module), size: 9, color: DS.Palette.ink(0.38))

            HStack(spacing: 7) {
                ForEach([1.0, 1.10, 1.15, 1.20], id: \.self) { value in
                    let active = abs(model.mainVideoZoom - value) < 0.006
                    Button {
                        withAnimation(DS.Motion.settle) { model.setMainVideoZoom(value) }
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: value == 1 ? "arrow.counterclockwise" : "viewfinder.circle")
                                .font(.system(size: 14, weight: .semibold))
                            Text(verbatim: value == 1 ? "1×" : "+%\(Int(((value - 1) * 100).rounded()))")
                                .dsFont(.mono, .medium, 10)
                        }
                        .foregroundStyle(active ? DS.Palette.inkInverse : DS.Palette.ink(0.76))
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(active ? DS.Palette.lime : DS.Palette.hairline(0.07))
                        )
                    }
                    .buttonStyle(.dsPress(radius: 14))
                    .accessibilityLabel(Text("editor.zoom.amount \(Int((value * 100).rounded()))", bundle: .module))
                }
            }

            HStack(spacing: 10) {
                Image(systemName: "minus.magnifyingglass")
                    .foregroundStyle(DS.Palette.ink(0.45))
                Slider(
                    value: Binding(
                        get: { model.mainVideoZoom },
                        set: { model.setMainVideoZoom($0) }
                    ),
                    in: 1...1.5
                )
                .tint(DS.Palette.lime)
                Text(verbatim: String(format: "%.2f×", model.mainVideoZoom))
                    .dsFont(.mono, .medium, 11)
                    .foregroundStyle(DS.Palette.ink(0.75))
                    .frame(width: 42, alignment: .trailing)
            }
        }
    }

    private func zoomRecipeButton(
        _ kind: CameraMotionRecipe.Kind,
        title: LocalizedStringKey,
        symbol: String
    ) -> some View {
        let active = model.cameraMotionAtPlayhead?.kind == kind
        return Button {
            withAnimation(DS.Motion.settle) {
                model.applyCameraMotion(
                    kind,
                    amount: model.cameraMotionAtPlayhead?.amount ?? max(0.15, model.mainVideoZoom - 1)
                )
            }
        } label: {
            VStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .semibold))
                Text(title, bundle: .module)
                    .dsFont(.sans, .semibold, 10)
                    .lineLimit(1)
            }
            .foregroundStyle(active ? DS.Palette.inkInverse : DS.Palette.ink(0.74))
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(active ? DS.Palette.lime : DS.Palette.hairline(0.07))
            )
        }
        .buttonStyle(.dsPress(radius: 15))
        .disabled(!model.canApplyCameraMotion)
        .opacity(model.canApplyCameraMotion ? 1 : 0.4)
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    private func zoomRecipeTitle(_ kind: CameraMotionRecipe.Kind) -> LocalizedStringKey {
        switch kind {
        case .hold: "editor.zoom.static"
        case .pushIn: "editor.zoom.push"
        case .pullOut: "editor.zoom.pull"
        case .punch: "editor.zoom.punch"
        }
    }

    private func zoomFeelTitle(_ feel: CameraMotionRecipe.Feel) -> LocalizedStringKey {
        switch feel {
        case .calm: "editor.zoom.feel.calm"
        case .natural: "editor.zoom.feel.natural"
        case .energetic: "editor.zoom.feel.energetic"
        }
    }

    private var mainReframePanel: some View {
        VStack(spacing: 8) {
            mainReframeButton
            if model.isMainVideoReframed, !isMainAnalyzing {
                Button {
                    withAnimation(DS.Motion.settle) { model.removeMainReframe() }
                } label: {
                    Label {
                        Text("editor.video.smartReframe.remove", bundle: .module)
                    } icon: {
                        Image(systemName: "xmark.circle")
                    }
                    .dsFont(.sans, .medium, 12)
                    .foregroundStyle(DS.Palette.ink(0.6))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.dsPress(radius: 14))
            }
        }
    }

    private var isMainAnalyzing: Bool {
        if case .analyzing = model.mainSubjectTracking { return true }
        return false
    }

    private var mainReframeButton: some View {
        let analyzing = isMainAnalyzing
        return Button {
            Task { await model.smartReframeMainVideo() }
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(VideoLayerLane.tint.opacity(0.16))
                    Image(systemName: "viewfinder")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(VideoLayerLane.tint)
                        .symbolEffect(.breathe, options: .repeating, isActive: analyzing)
                }
                .frame(width: 42, height: 42)
                VStack(alignment: .leading, spacing: 3) {
                    Text("editor.video.smartReframe", bundle: .module)
                        .dsFont(.sans, .semibold, 13)
                    Text(mainTrackingDetail)
                        .dsFont(.sans, .regular, 10)
                        .foregroundStyle(DS.Palette.ink(0.5))
                        .contentTransition(.numericText())
                }
                Spacer(minLength: 8)
                switch model.mainSubjectTracking {
                case .analyzing(let progress):
                    ProgressView(value: progress).progressViewStyle(.circular).tint(VideoLayerLane.tint)
                case .applied:
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(VideoLayerLane.tint)
                        .symbolEffect(.bounce, value: model.mainSubjectTracking)
                case .failed, .noFace:
                    Image(systemName: "arrow.clockwise").foregroundStyle(DS.Palette.accentWarm)
                case .idle:
                    Image(systemName: "chevron.right").foregroundStyle(DS.Palette.ink(0.35))
                }
            }
            .padding(11)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(DS.Palette.hairline(0.07)))
        }
        .buttonStyle(.dsPress(radius: 16))
        .disabled(analyzing)
        .animation(DS.Motion.snap, value: model.mainSubjectTracking)
    }

    private var mainTrackingDetail: String {
        switch model.mainSubjectTracking {
        case .idle: String(localized: "editor.video.smartReframe.mainHint", bundle: .module)
        case .analyzing(let progress): String(localized: "editor.video.smartReframe.progress \(Int((progress * 100).rounded()))", bundle: .module)
        case .applied(let points): String(localized: "editor.video.smartReframe.done \(points)", bundle: .module)
        case .noFace: String(localized: "editor.video.smartReframe.noFace", bundle: .module)
        case .failed: String(localized: "editor.video.smartReframe.failed", bundle: .module)
        }
    }

    private func trimPanel(at index: Int) -> some View {
        let segment = model.project.segments[index]

        return VStack(alignment: .leading, spacing: 10) {
            if let take = segment.selectedTake, segment.playback.freeze == nil {
                // The whole recording, with the part in the video held between two handles.
                FootageTrimStrip(
                    model: model,
                    recordingID: take.recordingID,
                    from: take.sourceRange.start.seconds,
                    to: take.sourceRange.end.seconds,
                    tint: DS.Palette.segment(at: segment.role.paletteIndex),
                    onStart: { wanted in
                        guard let current = model.project.segments[safe: index]?.selectedTake else { return }
                        model.trimStart(by: wanted - current.sourceRange.start.seconds, at: index)
                    },
                    onEnd: { wanted in
                        guard let current = model.project.segments[safe: index]?.selectedTake else { return }
                        model.trimEnd(by: wanted - current.sourceRange.end.seconds, at: index)
                    },
                    moment: { seconds in
                        guard let fresh = model.project.segments[safe: index], let current = fresh.selectedTake else { return nil }
                        let offset = fresh.playback.timelineSeconds(forSource: max(0, seconds - current.sourceRange.start.seconds))
                        return model.start(at: index) + min(offset, fresh.barWeight)
                    }
                )
            }

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

    /// Where a new effect goes and when: the same three choices for every effect.
    private func reachRow(at index: Int, tint: Color) -> some View {
        let span = backgroundSpan(at: index)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                reachChip(.clip, "editor.background.reach.clip", tint: tint)
                reachChip(.fromHere, "editor.background.reach.here", tint: tint)
                reachChip(.whole, "editor.background.reach.whole", tint: tint)
            }
            Text(verbatim: "\(MediaTime(seconds: span.lowerBound).preciseTimecode) – \(MediaTime(seconds: span.upperBound).preciseTimecode)")
                .dsFont(.mono, .medium, 10)
                .foregroundStyle(DS.Palette.ink(0.5))
                .contentTransition(.numericText())
        }
    }

    /// A colour look over a stretch: pick one, it lands on the timeline selected.
    private func filterPanel(at index: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            reachRow(at: index, tint: EffectLane.filterTint)
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(FilterPresets.looks.filter { $0 != .natural } + [.natural], id: \.self) { look in
                        Button {
                            let range = backgroundSpan(at: index)
                            open = nil
                            withAnimation(DS.Motion.settle) {
                                model.addEffect(.filter(FilterSettings(look: look)), from: range.lowerBound, to: range.upperBound)
                            }
                        } label: {
                            VStack(spacing: 6) {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(FilterPresets.swatch(look))
                                    .frame(width: 52, height: 52)
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .strokeBorder(DS.Palette.hairline(0.12), lineWidth: 1)
                                    }
                                Text(FilterPresets.label(look))
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
            Text("editor.filter.hint", bundle: .module)
                .dsFont(.sans, .regular, 11, lineHeight: 1.35)
                .foregroundStyle(DS.Palette.ink(0.45))
        }
    }

    /// A sound effect on the voice over a stretch.
    private func soundPanel(at index: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            reachRow(at: index, tint: EffectLane.soundTint)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 7), count: 4), spacing: 7) {
                ForEach(SoundPresets.presets, id: \.self) { preset in
                    Button {
                        let range = backgroundSpan(at: index)
                        open = nil
                        withAnimation(DS.Motion.settle) {
                            model.addEffect(.sound(SoundSettings(preset: preset)), from: range.lowerBound, to: range.upperBound)
                        }
                    } label: {
                        VStack(spacing: 5) {
                            Image(systemName: SoundPresets.symbol(preset))
                                .font(.system(size: 15, weight: .medium))
                            Text(SoundPresets.label(preset))
                                .dsFont(.sans, .medium, 10)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        .foregroundStyle(DS.Palette.ink(0.85))
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(DS.Palette.hairline(0.07)))
                    }
                    .buttonStyle(.dsPress(radius: 13))
                }
            }
            Text("editor.sound.hint", bundle: .module)
                .dsFont(.sans, .regular, 11, lineHeight: 1.35)
                .foregroundStyle(DS.Palette.ink(0.45))
        }
    }

    private func reachChip(_ reach: BackgroundReach, _ key: String.LocalizationValue, tint: Color = EffectLane.tint) -> some View {
        let isOn = backgroundReach == reach
        return Button {
            withAnimation(DS.Motion.snap) { backgroundReach = reach }
        } label: {
            Text(String(localized: key, bundle: .module))
                .dsFont(.sans, .medium, 12)
                .foregroundStyle(isOn ? DS.Palette.inkInverse : DS.Palette.ink(0.8))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(Capsule().fill(isOn ? tint : DS.Palette.hairline(0.07)))
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
