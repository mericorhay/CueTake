import AVKit
import DesignSystem
import PhotosUI
import Domain
import SwiftUI

/// Preview, transport, segment timeline and the inspector sheet.
public struct EditorScreen: View {
    @Bindable private var model: EditorModel

    private let onBack: () -> Void
    private let onExport: () -> Void
    private let onCaptions: () -> Void
    private let onRetake: (Segment.ID) -> Void
    /// Asks the layer that owns the file system to bring a piece of audio in.
    private let onAddAudio: () -> Void
    /// What the app layer says about the file on disk, and how to make it write now.
    private let saveLabel: String
    private let isSaving: Bool
    private let onSave: () -> Void
    /// Runs speech transcription for takes that have none.
    private let onTranscribe: () -> Void
    /// Asks the layer that knows where media lives to get playback ready.
    private let onPrepare: () async -> Void

    public init(
        model: EditorModel,
        onPrepare: @escaping () async -> Void = {},
        onBack: @escaping () -> Void,
        onExport: @escaping () -> Void,
        onCaptions: @escaping () -> Void,
        onRetake: @escaping (Segment.ID) -> Void,
        onAddAudio: @escaping () -> Void = {},
        saveLabel: String = "",
        isSaving: Bool = false,
        onSave: @escaping () -> Void = {},
        onTranscribe: @escaping () -> Void = {},
        onAIEdit: AIRequester? = nil
    ) {
        self.model = model
        self.onPrepare = onPrepare
        self.onBack = onBack
        self.onExport = onExport
        self.onCaptions = onCaptions
        self.onRetake = onRetake
        self.onAddAudio = onAddAudio
        self.saveLabel = saveLabel
        self.isSaving = isSaving
        self.onSave = onSave
        self.onTranscribe = onTranscribe
        self.onAIEdit = onAIEdit
    }

    private let onAIEdit: AIRequester?

    @State private var showsTools = false
    @State private var dockPanel: ToolDock.Item?
    @State private var pickingImage = false
    @State private var pickedImage: PhotosPickerItem?
    /// Set while the phone is on its side: the picture takes the height of the screen.
    @State private var landscapePreviewHeight: CGFloat?
    @State private var showsChanges = false
    @State private var showsAIChanges = false
    @State private var rebuild: Task<Void, Never>?
    /// The caption being edited on the picture, if any.
    @State private var editingCaption: CaptionCue.ID?
    @State private var previewExpanded = false
    @State private var showsTranscript = false

    /// Whatever the tools should act on: the inspected clip, or the one under the playhead.
    private var workingIndex: Int? {
        if let inspected = model.inspectedSegment {
            return model.project.segments.firstIndex { $0.id == inspected }
        }
        return model.segmentAtPlayhead?.index
    }

    /// The preview gives up its height to whichever panel is open, and takes it all back when the
    /// user asks for a proper look.
    ///
    /// This is the fix for the panel running off the bottom of the screen: the inspector grew real
    /// controls and there was nothing in the column willing to make room for them. A fixed 212pt
    /// picture above a panel that can be four hundred points tall is a layout that can only work
    /// by luck.
    private var previewHeight: CGFloat {
        if let landscapePreviewHeight { return landscapePreviewHeight }
        // An overlay or a caption being placed gets the big picture: both are placed by looking.
        if model.selectedOverlay != nil || editingCaption != nil { return 390 }
        if previewExpanded { return 430 }
        return isPanelOpen || dockPanel != nil ? 150 : 212
    }

    private var isPanelOpen: Bool {
        model.inspectedSegment != nil || model.selectedAudio != nil || model.selectedOverlay != nil || editingCaption != nil
    }

    public var body: some View {
        GeometryReader { proxy in
            if proxy.size.width > proxy.size.height {
                // Landscape gets its own arrangement: the picture on the left at the height of the
                // screen, the tools and the timeline beside it. A portrait column centred in a wide
                // window wasted half the phone and hid the rest below the fold.
                HStack(alignment: .top, spacing: 16) {
                    VStack(spacing: 0) {
                        topBar
                        preview
                        transport
                    }
                    .frame(width: min(proxy.size.width * 0.46, 560))

                    ScrollView {
                        VStack(spacing: 0) {
                            statusStrip
                            timelineBlock
                        }
                        .padding(.bottom, 30)
                    }
                    .scrollIndicators(.hidden)
                }
                .padding(.top, 14)
                .padding(.horizontal, 44)
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
                .onAppear { landscapePreviewHeight = max(160, proxy.size.height - 150) }
                .onChange(of: proxy.size) { _, size in landscapePreviewHeight = max(160, size.height - 150) }
            } else {
                VStack(spacing: 0) {
                    topBar
                    statusStrip
                    preview
                    transport
                    timelineBlock

                    Spacer(minLength: 0)
                }
                .padding(.top, 58)
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
                .onAppear { landscapePreviewHeight = nil }
            }
        }
        // The panels sit *over* the column rather than in it.
        //
        // In the column they were one more thing competing for a fixed 874 points, and the loser
        // was whatever came last — which is why the reverse and freeze buttons were under the
        // bottom edge of the phone. A panel that covers the timeline while it is open is the
        // normal behaviour of a sheet, and it is the only version of this that cannot run out of
        // room.
        .overlay(alignment: .bottom) {
            if let captionID = editingCaption {
                CaptionQuickPanel(
                    model: model,
                    captionID: captionID,
                    onClose: { withAnimation(DS.Motion.settle) { editingCaption = nil } },
                    onOpenAll: {
                        editingCaption = nil
                        onCaptions()
                    }
                )
            } else if let clip = model.selectedAudioClip {
                audioPanel(clip)
            } else if let overlay = model.selectedOverlayValue {
                OverlayInspector(model: model, overlay: overlay) {
                    withAnimation(DS.Motion.settle) { model.select(overlay: nil) }
                }
            } else if let id = model.inspectedSegment,
                      let index = model.project.segments.firstIndex(where: { $0.id == id }) {
                inspector(at: index)
            }
        }
        .animation(DS.Motion.settle, value: isPanelOpen)
        .animation(DS.Motion.settle, value: dockPanel)
        // The AI has the studio: light around the screen, its voice at the top.
        .overlay {
            AIAuroraBorder(active: model.isAIDriving)
        }
        .overlay(alignment: .top) {
            AIDirectorHUD(model: model) {
                model.dismissAISession()
                showsAIChanges = true
            }
            .padding(.top, landscapePreviewHeight == nil ? 50 : 8)
        }
        .sheet(isPresented: $showsAIChanges) {
            AIChangesSheet(model: model) { showsAIChanges = false }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sensoryFeedback(.impact(weight: .light, intensity: 0.7), trigger: model.aiBeat)
        .sheet(isPresented: $showsTools) {
            ToolBrowser(
                model: model,
                onAddAudio: onAddAudio,
                onCaptions: onCaptions,
                onExport: onExport,
                onTranscriptEdit: { showsTranscript = true },
                onClose: { showsTools = false }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showsTranscript) {
            if let index = workingIndex {
                TranscriptPanel(
                    model: model,
                    index: index,
                    onTranscribe: onTranscribe,
                    onClose: { showsTranscript = false }
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
        }
        .sheet(isPresented: $showsChanges) {
            ChangesSheet(
                model: model,
                saveLabel: saveLabel,
                isSaving: isSaving,
                onSave: onSave,
                onClose: { showsChanges = false }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .task { await onPrepare() }
        // Speed, freeze and reverse change what the composition *is*, not just how it is drawn,
        // so the preview has to be rebuilt. Watched here rather than pushed from each control:
        // there are four of them and there will be more.
        // Any change to what the preview plays rebuilds it, a moment after the last change so a
        // run of edits is one rebuild.
        .onChange(of: model.compositionSignature) {
            guard !model.isAIDriving else { return }
            // Only the wait is cancelled by a newer change, never a build under way: cancelling one
            // half-built used to take the player down with it and leave the preview black.
            rebuild?.cancel()
            rebuild = Task {
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled else { return }
                let prepare = onPrepare
                await Task { await prepare() }.value
            }
        }
        .onChange(of: model.isAIDriving) { _, driving in
            // Everything the AI changed, rebuilt in one go: picture, sound, frames for new clips.
            guard !driving, model.aiSession != nil else { return }
            Task { await onPrepare() }
        }
        .photosPicker(isPresented: $pickingImage, selection: $pickedImage, matching: .images)
        .onChange(of: pickedImage) { _, item in
            guard let item else { return }
            pickedImage = nil
            Task {
                guard let data = try? await item.loadTransferable(type: Data.self) else { return }
                withAnimation(DS.Motion.bloom) { _ = model.addImageOverlay(from: data) }
            }
        }
        // Undo can bring back an overlay whose picture is not in memory.
        .onChange(of: model.project.overlays.count) { model.loadOverlayImages() }
        .animation(DS.Motion.settle, value: model.selectedOverlay)
        .onChange(of: model.inspectedSegment) { _, id in if id != nil { editingCaption = nil } }
        .onChange(of: model.selectedOverlay) { _, id in if id != nil { editingCaption = nil } }
        .onChange(of: model.isPlaying) { _, playing in if playing { editingCaption = nil } }
        .animation(DS.Motion.settle, value: editingCaption)
        .background(DS.Palette.screen)
        .dsEnter(.screen())
    }

    private var topBar: some View {
        HStack {
            DSBackButton(size: 34, fontSize: 15, action: onBack)

            Text(model.project.title)
                .dsFont(.sans, .semibold, 13)
                .foregroundStyle(DS.Palette.ink)
                .frame(maxWidth: .infinity)

            Button(action: onExport) {
                Text("editor.export", bundle: .module)
                    .dsFont(.sans, .semibold, 13)
                    .foregroundStyle(DS.Palette.inkInverse)
                    .padding(.horizontal, 15)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(DS.Palette.accent)
                    )
            }
            .buttonStyle(.dsPress)
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 10)
    }

    /// Undo, redo, what has changed, and whether it is saved.
    ///
    /// A strip of its own rather than icons crowded into the title bar. These four say one thing
    /// together — *your work is safe and reversible* — and that is a sentence worth its own line
    /// on a screen where everything else is about changing something.
    private var statusStrip: some View {
        HStack(spacing: 7) {
            historyButton("arrow.uturn.backward", enabled: model.canUndo && !model.isAIDriving) { model.undo() }
            historyButton("arrow.uturn.forward", enabled: model.canRedo && !model.isAIDriving) { model.redo() }

            Button {
                showsChanges = true
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: model.canUndo ? "clock.arrow.circlepath" : "checkmark")
                        .font(.system(size: 10, weight: .semibold))
                        .contentTransition(.symbolEffect(.replace))

                    Text(
                        model.lastChange?.label
                            ?? String(localized: "editor.changes.none", bundle: .module)
                    )
                    .dsFont(.sans, .medium, 11)
                    .lineLimit(1)
                    .truncationMode(.tail)
                }
                .foregroundStyle(DS.Palette.ink(0.6))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    Capsule().fill(DS.Palette.hairline(0.06))
                )
                .contentShape(Capsule())
            }
            .buttonStyle(.dsPress(radius: 20))
            // Undoing from the history while the AI is mid-run would land between its steps.
            .disabled(model.isAIDriving)
            // The pill changes text as edits land, so it animates rather than snapping.
            .animation(DS.Motion.snap, value: model.changes.count)

            // Saving is a dot, not a sentence. It is only worth a sentence when someone goes
            // looking, and there is a whole panel for that a tap away.
            Circle()
                .fill(isSaving ? DS.Palette.ink(0.3) : DS.Palette.lime)
                .frame(width: 6, height: 6)
                .dsPulseIfSaving(isSaving)
                .padding(.trailing, 2)

            if !model.aiChanges.isEmpty {
                Button {
                    showsAIChanges = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(AIPalette.linear)
                        Text(verbatim: "\(model.aiChanges.reduce(0) { $0 + $1.activeCount })")
                            .dsFont(.mono, .medium, 10)
                            .foregroundStyle(DS.Palette.ink(0.8))
                            .contentTransition(.numericText())
                    }
                    .padding(.horizontal, 9)
                    .frame(height: 30)
                    .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(DS.Palette.hairline(0.08)))
                    .overlay { AIRing(shape: RoundedRectangle(cornerRadius: 11, style: .continuous), active: model.isAIDriving) }
                }
                .buttonStyle(.dsPressIcon)
                .disabled(model.isAIDriving)
                .transition(.scale.combined(with: .opacity))
            }

            Button {
                showsTools = true
            } label: {
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DS.Palette.ink(0.75))
                    .frame(width: 30, height: 30)
                    .background(
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .fill(DS.Palette.hairline(0.08))
                    )
            }
            .buttonStyle(.dsPressIcon)
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 8)
        .animation(DS.Motion.bloom, value: model.aiChanges.isEmpty)
    }

    private func historyButton(
        _ symbol: String,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(enabled ? DS.Palette.ink(0.8) : DS.Palette.ink(0.2))
                .frame(width: 30, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(DS.Palette.hairline(enabled ? 0.08 : 0.03))
                )
        }
        .buttonStyle(.dsPressIcon)
        .disabled(!enabled)
        .animation(DS.Motion.snap, value: enabled)
    }

    /// The composition preview. AVPlayer lands here; until then it is the camera-dark plate.
    private var preview: some View {
        Group {
            if let player = model.player {
                // No AVKit chrome: the transport and the timeline below are the controls, and a
                // second set of them inside the frame would be two players arguing.
                VideoPlayer(player: player)
                    .disabled(true)
                    // A different player (another project) gets a fresh video view: the old view
                    // would keep drawing the player it was made with.
                    .id(ObjectIdentifier(player))
            } else {
                RoundedRectangle(cornerRadius: DS.Radius.cardLarge, style: .continuous)
                    .fill(DS.Palette.camera)
                    .overlay {
                        if let problem = model.playbackProblem {
                            VStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(DS.Palette.accent)
                                Text("editor.preview.failed", bundle: .module)
                                    .dsFont(.sans, .semibold, 13)
                                    .foregroundStyle(DS.Palette.ink)
                                Text(verbatim: problem)
                                    .dsFont(.mono, .medium, 9)
                                    .foregroundStyle(DS.Palette.ink(0.45))
                                    .lineLimit(3)
                                    .multilineTextAlignment(.center)
                                Button {
                                    Task { await onPrepare() }
                                } label: {
                                    Text("editor.ai.retry", bundle: .module)
                                        .dsFont(.sans, .semibold, 12)
                                        .foregroundStyle(DS.Palette.inkInverse)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 7)
                                        .background(Capsule().fill(DS.Palette.ink))
                                }
                                .buttonStyle(.dsPress(radius: 20))
                            }
                            .padding(16)
                        }
                    }
            }
        }
        .frame(height: previewHeight)
        // Captions, over the picture, where they will be in the finished file. The export burns
        // them in with a layer tool the preview player cannot run, so the preview draws its own
        // from the same numbers — see `CaptionOverlay`.
        .overlay {
            // Inside the video's own rectangle, sized from its height — the same numbers the
            // export uses. Laid out against the whole preview box, captions slid about whenever
            // the box changed shape: a bigger preview, a panel opening, the phone turning.
            GeometryReader { box in
                let frame = OverlayCanvas.videoRect(in: box.size, render: model.project.format.renderSize)
                ZStack {
            if let cue = model.project.caption(at: model.playhead) {
                CaptionOverlay(
                    cue: cue,
                    style: model.project.captionStyle,
                    locale: model.project.locale,
                    time: model.playhead,
                    glowToken: model.captionGlowToken,
                    isEditing: editingCaption == cue.id,
                    onTap: {
                        guard !model.isAIDriving else { return }
                        model.pause()
                        withAnimation(DS.Motion.settle) {
                            model.inspectedSegment = nil
                            model.selectedAudio = nil
                            model.select(overlay: nil)
                            dockPanel = nil
                            editingCaption = editingCaption == cue.id ? nil : cue.id
                        }
                    },
                    onMove: { y in
                        model.updateCaptionStyle(coalescing: "caption-move") { style in
                            // Settles on the usual places — top, middle, lower third, bottom — when close.
                            let marks = [0.12, 0.5, 0.72, 0.86]
                            let near = marks.first { abs($0 - y) < 0.025 }
                            style.position = CaptionPosition(x: style.position.x, y: near ?? y)
                        }
                    }
                )
                .id(cue.id)
                .transition(CaptionOverlay.transition(for: model.project.captionStyle))
            }
                }
                .frame(width: frame.width, height: frame.height)
                .position(x: frame.midX, y: frame.midY)
            }
        }
        // Pictures and text, over the captions, moved with the fingers.
        .overlay { OverlayCanvas(model: model) }
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.cardLarge, style: .continuous))
        .aiGlow(model.aiBeat, in: RoundedRectangle(cornerRadius: DS.Radius.cardLarge, style: .continuous))
        .allowsHitTesting(!model.isAIDriving)
        .overlay(alignment: .topLeading) {
            if let progress = model.backgroundProgress {
                HStack(spacing: 7) {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                        .tint(DS.Palette.lime)
                        .frame(width: 54)
                    Text("editor.background.progress \(Int(progress * 100))", bundle: .module)
                        .dsFont(.mono, .medium, 10)
                        .foregroundStyle(DS.Palette.ink)
                        .contentTransition(.numericText())
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Capsule().fill(DS.Palette.inkInverse(0.6)))
                .padding(10)
                .transition(.opacity.combined(with: .move(edge: .top)))
            } else if model.backgroundFailed {
                Label {
                    Text("editor.background.failed", bundle: .module)
                        .dsFont(.sans, .medium, 11)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(DS.Palette.accent)
                }
                .foregroundStyle(DS.Palette.ink)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Capsule().fill(DS.Palette.inkInverse(0.7)))
                .padding(10)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(DS.Motion.settle, value: model.backgroundProgress == nil)
        .animation(DS.Motion.settle, value: model.backgroundFailed)
        .overlay(alignment: .topTrailing) {
            // Discoverable rather than a secret tap. The whole picture is the target, but nobody
            // taps a video expecting it to grow unless something says it will.
            Button {
                withAnimation(DS.Motion.settle) {
                    previewExpanded.toggle()
                    if previewExpanded {
                        // Opening the picture closes the panel: they are competing for the same
                        // column, and pretending otherwise is what put controls off-screen.
                        model.inspectedSegment = nil
                        model.selectedAudio = nil
                    }
                }
            } label: {
                Image(systemName: previewExpanded
                    ? "arrow.down.right.and.arrow.up.left"
                    : "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(DS.Palette.ink(0.85))
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(DS.Palette.inkInverse(0.45)))
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.dsPressIcon)
            .padding(9)
        }
        .padding(.horizontal, 18)
        .padding(.top, 4)
        .animation(DS.Motion.settle, value: previewHeight)
    }

    private var transport: some View {
        HStack(spacing: 18) {
            // Given a surface of its own. A bare glyph on a dark background is a target you have
            // to aim at, and this is the control people reach for most after the playhead.
            Button(action: model.skipToStart) {
                // A symbol, not an emoji. Emoji are pictures of things — they carry a colour, a
                // platform's house style, and a font the rest of the interface does not use. This
                // one inherits weight and size from the type around it, which is why it sits in a
                // control instead of on top of one.
                Image(systemName: "backward.end.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(DS.Palette.ink(0.75))
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(DS.Palette.hairline(0.08)))
                    .overlay(Circle().stroke(DS.Palette.hairline(0.1), lineWidth: 1))
            }
            .buttonStyle(.dsPressIcon)

            Button(action: model.togglePlayback) {
                Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(DS.Palette.inkInverse)
                    // The play triangle sits visually left of centre inside a circle; the pause
                    // bars do not. Nudging only the triangle is the difference between a button
                    // that looks centred and one that looks almost centred.
                    .offset(x: model.isPlaying ? 0 : 2)
                    .frame(width: 52, height: 52)
                    .background(Circle().fill(DS.Palette.ink))
                    .shadow(color: DS.Palette.ink(0.25), radius: 12, y: 6)
                    .contentTransition(.symbolEffect(.replace))
                    .animation(DS.Motion.snap, value: model.isPlaying)
            }
            .buttonStyle(.dsPressIcon)

            VStack(alignment: .leading, spacing: 1) {
                Text(model.playheadLabel)
                    .dsFont(.mono, .medium, 14)
                    .foregroundStyle(DS.Palette.ink)
                    .contentTransition(.numericText())
                Text(model.durationLabel)
                    .dsFont(.mono, .medium, 10)
                    .foregroundStyle(DS.Palette.ink(0.38))
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, 6)
    }

    // MARK: - Timeline

    private var timelineBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            // The tools first, straight under the picture. Below the timeline they ran off the
            // bottom of the phone.
            if model.selectedAudioClip == nil {
                ToolDock(
                    model: model,
                    onCaptions: onCaptions,
                    onAddAudio: onAddAudio,
                    onMore: { showsTools = true },
                    aiRequest: onAIEdit,
                    onAddImage: { pickingImage = true },
                    onShowAIChanges: { showsAIChanges = true },
                    open: $dockPanel
                )
                .padding(.bottom, 10)
            } else {
                EditorToolbar(model: model)
                    .padding(.horizontal, -18)
                    .padding(.bottom, 10)
            }

            DSKicker(String(localized: "editor.timeline", bundle: .module), size: 9, color: DS.Palette.ink(0.38))
                .padding(.bottom, 6)

            EditorTimeline(model: model) { id in
                model.pause()
                withAnimation(DS.Motion.settle) {
                    model.inspectedSegment = nil
                    model.selectedAudio = nil
                    model.select(overlay: nil)
                    dockPanel = nil
                    editingCaption = id
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
        .allowsHitTesting(!model.isAIDriving)
    }

    // MARK: - Inspector

    private func inspector(at index: Int) -> some View {
        let segment = model.project.segments[index]

        return VStack(alignment: .leading, spacing: 0) {
            Capsule()
                .fill(DS.Palette.hairline(0.2))
                .frame(width: 36, height: 4)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 14)

            HStack(spacing: 9) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(DS.Palette.segment(at: segment.role.paletteIndex))
                    .frame(width: 9, height: 9)

                Text(segment.role.displayLabel)
                    .dsFont(.archivo, .bold, 19)
                    .foregroundStyle(DS.Palette.ink)

                Text(model.rangeLabel(at: index))
                    .dsFont(.mono, .medium, 10)
                    .foregroundStyle(DS.Palette.ink(0.35))

                Spacer(minLength: 0)

                Button {
                    withAnimation(DS.Easing.standard(0.38)) { model.inspectedSegment = nil }
                } label: {
                    Text("✕")
                        .font(.system(size: 16))
                        .foregroundStyle(DS.Palette.ink(0.45))
                }
                .buttonStyle(.dsPress)
            }
            .padding(.bottom, 14)

            HStack(spacing: 6) {
                ForEach(EditorModel.InspectorTab.allCases, id: \.self) { tab in
                    let isOn = model.inspectorTab == tab
                    Button {
                        model.inspectorTab = tab
                    } label: {
                        Text(tab.label)
                            .dsFont(.sans, .medium, 12)
                            .foregroundStyle(isOn ? DS.Palette.inkInverse : DS.Palette.ink(0.6))
                            .padding(.horizontal, 11)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(isOn ? DS.Palette.ink : DS.Palette.hairline(0.07))
                            )
                    }
                    .buttonStyle(.dsPress)
                    .animation(DS.Easing.ease(0.25), value: isOn)
                }
            }
            .padding(.bottom, 14)

            // Scrolls, and is bounded. The timing tab alone is taller than the space this panel
            // used to assume it had, which is how "reverse" and "freeze" ended up under the
            // bottom edge of the phone.
            ScrollView {
                inspectorBody(for: segment, at: index)
                    .padding(.bottom, 2)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxHeight: 236)

            // Pinned under the scroll area rather than inside it: these two are how the panel is
            // left, and a way out that scrolls away is not a way out.
            HStack(spacing: 9) {
                Button {
                    onRetake(segment.id)
                } label: {
                    Text("editor.retakeSegment", bundle: .module)
                        .dsFont(.sans, .semibold, 14)
                        .foregroundStyle(DS.Palette.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(DS.Palette.accent(0.14))
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(DS.Palette.accent(0.4), lineWidth: 1)
                        }
                }
                .buttonStyle(.dsPress)

                Button {
                    withAnimation(DS.Easing.standard(0.38)) { model.inspectedSegment = nil }
                } label: {
                    Text("editor.done", bundle: .module)
                        .dsFont(.sans, .semibold, 14)
                        .foregroundStyle(DS.Palette.inkInverse)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(DS.Palette.ink)
                        )
                }
                .buttonStyle(.dsPress)
            }
            .padding(.top, 14)
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 30)
        .frame(maxWidth: .infinity)
        .background {
            UnevenRoundedRectangle(
                topLeadingRadius: DS.Radius.hero,
                topTrailingRadius: DS.Radius.hero,
                style: .continuous
            )
            .fill(.ultraThinMaterial)
            .overlay(
                UnevenRoundedRectangle(
                    topLeadingRadius: DS.Radius.hero,
                    topTrailingRadius: DS.Radius.hero,
                    style: .continuous
                )
                .fill(DS.Palette.glassSheet(0.94))
            )
        }
        .overlay(alignment: .top) {
            Rectangle()
                .fill(DS.Palette.hairline(0.1))
                .frame(height: 1)
        }
        .dsEnter(.rise(duration: 0.38))
    }

    /// The audio panel.
    ///
    /// Same chrome as the segment inspector on purpose: it is the same place on the screen doing
    /// the same job for a different selection, and giving it its own look would make it read as a
    /// different mode rather than a different object.
    private func audioPanel(_ clip: AudioClip) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Capsule()
                .fill(DS.Palette.hairline(0.2))
                .frame(width: 36, height: 4)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 14)

            ScrollView {
                AudioInspector(model: model, clip: clip)
                    .padding(.bottom, 2)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxHeight: 268)

            Button {
                withAnimation(DS.Motion.snap) { model.selectedAudio = nil }
            } label: {
                Text("editor.done", bundle: .module)
                    .dsFont(.sans, .semibold, 14)
                    .foregroundStyle(DS.Palette.inkInverse)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(DS.Palette.ink)
                    )
            }
            .buttonStyle(.dsPress(radius: 16))
            .padding(.top, 16)
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 30)
        .frame(maxWidth: .infinity)
        .background {
            UnevenRoundedRectangle(
                topLeadingRadius: DS.Radius.hero,
                topTrailingRadius: DS.Radius.hero,
                style: .continuous
            )
            .fill(.ultraThinMaterial)
            .overlay(
                UnevenRoundedRectangle(
                    topLeadingRadius: DS.Radius.hero,
                    topTrailingRadius: DS.Radius.hero,
                    style: .continuous
                )
                .fill(DS.Palette.glassSheet(0.94))
            )
        }
        .overlay(alignment: .top) {
            Rectangle()
                .fill(DS.Palette.hairline(0.1))
                .frame(height: 1)
        }
        .dsEnter(.rise(duration: 0.38))
    }

    @ViewBuilder
    private func inspectorBody(for segment: Segment, at index: Int) -> some View {
        SegmentInspector(model: model, segmentID: segment.id, onOpenCaptions: onCaptions)
    }
}

extension Segment {
    /// First four words, as the design previews captions under the timeline.
    var captionPreview: String {
        ScriptText.words(in: script).prefix(4).joined(separator: " ")
    }

    var wordCount: Int {
        ScriptText.words(in: script).count
    }

    var wordsPerMinute: Int {
        Int((Double(wordCount) / max(1, barWeight) * 60).rounded())
    }
}

extension EditorModel.InspectorTab {
    var label: String {
        switch self {
        case .script: String(localized: "editor.tab.script", bundle: .module)
        case .caption: String(localized: "editor.tab.caption", bundle: .module)
        case .timing: String(localized: "editor.tab.timing", bundle: .module)
        case .take: String(localized: "editor.tab.take", bundle: .module)
        case .style: String(localized: "editor.tab.style", bundle: .module)
        }
    }
}

/// The save dot breathes while a write is in flight, and holds still when there is nothing to say.
///
/// Applied conditionally rather than with a zero-amplitude animation: an animation that is always
/// running costs a redraw a frame forever, on a screen that is already drawing a video.
private struct PulseWhileSaving: ViewModifier {
    let isSaving: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isSaving {
            content.dsPulse(duration: 1)
        } else {
            content
        }
    }
}

extension View {
    fileprivate func dsPulseIfSaving(_ isSaving: Bool) -> some View {
        modifier(PulseWhileSaving(isSaving: isSaving))
    }
}
