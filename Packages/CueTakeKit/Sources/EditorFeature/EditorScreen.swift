import AVKit
import DesignSystem
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
    /// Asks the layer that knows where media lives to get playback ready.
    private let onPrepare: () async -> Void

    public init(
        model: EditorModel,
        onPrepare: @escaping () async -> Void = {},
        onBack: @escaping () -> Void,
        onExport: @escaping () -> Void,
        onCaptions: @escaping () -> Void,
        onRetake: @escaping (Segment.ID) -> Void,
        onAddAudio: @escaping () -> Void = {}
    ) {
        self.model = model
        self.onPrepare = onPrepare
        self.onBack = onBack
        self.onExport = onExport
        self.onCaptions = onCaptions
        self.onRetake = onRetake
        self.onAddAudio = onAddAudio
    }

    public var body: some View {
        VStack(spacing: 0) {
            topBar
            preview
            transport
            timelineBlock

            Spacer(minLength: 0)

            if let clip = model.selectedAudioClip {
                audioPanel(clip)
            } else if let id = model.inspectedSegment,
               let index = model.project.segments.firstIndex(where: { $0.id == id }) {
                inspector(at: index)
            } else {
                Text("editor.hint", bundle: .module)
                    .dsFont(.sans, .regular, 12)
                    .foregroundStyle(DS.Palette.ink(0.32))
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 18)
                    .padding(.bottom, 30)
            }
        }
        .padding(.top, 58)
        .task { await onPrepare() }
        // Speed, freeze and reverse change what the composition *is*, not just how it is drawn,
        // so the preview has to be rebuilt. Watched here rather than pushed from each control:
        // there are four of them and there will be more.
        .onChange(of: model.project.segments.map(\.playback)) {
            Task { await onPrepare() }
        }
        .dsScreenLayout()
        .background(DS.Palette.screen)
        .dsEnter(.screen())
    }

    private var topBar: some View {
        HStack {
            DSCircleButton("←", size: 34, fontSize: 15, action: onBack)

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

    /// The composition preview. AVPlayer lands here; until then it is the camera-dark plate.
    private var preview: some View {
        Group {
            if let player = model.player {
                // No AVKit chrome: the transport and the timeline below are the controls, and a
                // second set of them inside the frame would be two players arguing.
                VideoPlayer(player: player)
                    .disabled(true)
            } else {
                RoundedRectangle(cornerRadius: DS.Radius.cardLarge, style: .continuous)
                    .fill(DS.Palette.camera)
            }
        }
        .frame(height: 212)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.cardLarge, style: .continuous))
        .padding(.horizontal, 18)
        .padding(.top, 4)
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
            HStack {
                DSKicker(String(localized: "editor.timeline", bundle: .module), size: 9, color: DS.Palette.ink(0.38))
                Spacer(minLength: 0)
                Button(action: onAddAudio) {
                    HStack(spacing: 4) {
                        Image(systemName: "music.note")
                            .font(.system(size: 9, weight: .semibold))
                        Text("editor.audio.add", bundle: .module)
                            .dsFont(.sans, .medium, 11)
                    }
                    .foregroundStyle(DS.Palette.ink(0.7))
                    .padding(.horizontal, 11)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .fill(DS.Palette.hairline(0.07))
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .stroke(DS.Palette.hairline(0.1), lineWidth: 1)
                    }
                }
                .buttonStyle(.dsPress(radius: 13))
                .padding(.trailing, 7)

                Button(action: onCaptions) {
                    Text("editor.captions", bundle: .module)
                        .dsFont(.sans, .medium, 11)
                        .foregroundStyle(DS.Palette.lime)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .fill(DS.Palette.lime(0.1))
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .stroke(DS.Palette.lime(0.3), lineWidth: 1)
                        }
                }
                .buttonStyle(.dsPress)
            }
            .padding(.bottom, 9)

            EditorTimeline(model: model)

            captionStrip
                .padding(.top, 7)

            EditorToolbar(model: model)
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
    }



    private var captionStrip: some View {
        GeometryReader { proxy in
            let weights = model.project.segments.map(\.barWeight)
            let total = max(1, weights.reduce(0, +))
            let gaps = CGFloat(max(0, weights.count - 1)) * 4
            let usable = proxy.size.width - gaps

            HStack(spacing: 4) {
                ForEach(Array(model.project.segments.enumerated()), id: \.element.id) { index, segment in
                    Text(segment.captionPreview)
                        .dsFont(.sans, .regular, 9)
                        .foregroundStyle(DS.Palette.ink(0.4))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .padding(.horizontal, 7)
                        .frame(width: usable * (weights[index] / total), height: 22, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: DS.Radius.xs, style: .continuous)
                                .fill(DS.Palette.hairline(0.05))
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: DS.Radius.xs, style: .continuous)
                                .stroke(DS.Palette.hairline(0.07), lineWidth: 1)
                        }
                }
            }
        }
        .frame(height: 22)
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

            inspectorBody(for: segment, at: index)
                .frame(minHeight: 96, alignment: .top)

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

            AudioInspector(model: model, clip: clip)

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
        SegmentInspector(model: model, index: index)
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
