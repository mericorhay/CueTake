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

    public init(
        model: EditorModel,
        onBack: @escaping () -> Void,
        onExport: @escaping () -> Void,
        onCaptions: @escaping () -> Void,
        onRetake: @escaping (Segment.ID) -> Void
    ) {
        self.model = model
        self.onBack = onBack
        self.onExport = onExport
        self.onCaptions = onCaptions
        self.onRetake = onRetake
    }

    public var body: some View {
        VStack(spacing: 0) {
            topBar
            preview
            transport
            timelineBlock

            Spacer(minLength: 0)

            if let id = model.inspectedSegment,
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
        RoundedRectangle(cornerRadius: DS.Radius.cardLarge, style: .continuous)
            .fill(DS.Palette.camera)
            .frame(height: 212)
            .padding(.horizontal, 18)
            .padding(.top, 4)
    }

    private var transport: some View {
        HStack(spacing: 20) {
            Button(action: model.skipToStart) {
                Text("⏮")
                    .font(.system(size: 18))
                    .foregroundStyle(DS.Palette.ink(0.55))
            }
            .buttonStyle(.dsPress)

            Button(action: model.togglePlayback) {
                Text(model.isPlaying ? "❚❚" : "▶")
                    .font(.system(size: 17))
                    .foregroundStyle(DS.Palette.inkInverse)
                    .frame(width: 52, height: 52)
                    .background(Circle().fill(DS.Palette.ink))
            }
            .buttonStyle(.dsPress)

            Text("\(model.playheadLabel) / \(model.durationLabel)")
                .dsFont(.mono, .medium, 12)
                .foregroundStyle(DS.Palette.ink(0.55))
        }
        .padding(.top, 14)
        .padding(.bottom, 6)
    }

    // MARK: - Timeline

    private var timelineBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                DSKicker(String(localized: "editor.timeline", bundle: .module), size: 9, color: DS.Palette.ink(0.38))
                Spacer(minLength: 0)
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

            GeometryReader { proxy in
                let weights = model.project.segments.map(\.barWeight)
                let total = max(1, weights.reduce(0, +))
                let gaps = CGFloat(max(0, weights.count - 1)) * 4
                let usable = proxy.size.width - gaps

                ZStack(alignment: .topLeading) {
                    HStack(spacing: 4) {
                        ForEach(Array(model.project.segments.enumerated()), id: \.element.id) { index, segment in
                            clip(segment, at: index)
                                .frame(width: usable * (weights[index] / total))
                        }
                    }

                    playhead(in: proxy.size)
                }
            }
            .frame(height: 74)

            captionStrip
                .padding(.top, 7)
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
    }

    private func clip(_ segment: Segment, at index: Int) -> some View {
        let isActive = model.isActive(at: index)
        let isSelected = model.inspectedSegment == segment.id
        let highlighted = isActive || isSelected

        return VStack(alignment: .leading, spacing: 0) {
            Text(segment.role.displayLabel)
                .dsFont(.archivo, .bold, 12)
                .foregroundStyle(DS.Palette.inkInverse)
            Text("\(Int(segment.barWeight))s")
                .dsFont(.mono, .medium, 9)
                .foregroundStyle(DS.Palette.inkInverse(0.55))
                .padding(.top, 2)

            Spacer(minLength: 0)

            Text(String(localized: "editor.take \(segment.takes.count + 1)", bundle: .module))
                .dsFont(.mono, .medium, 8)
                .foregroundStyle(DS.Palette.inkInverse(0.55))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 9)
        .padding(.top, 9)
        .padding(.bottom, 8)
        .frame(maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(DS.Palette.segment(at: segment.role.paletteIndex))
        )
        .opacity(highlighted ? 1 : 0.55)
        .scaleEffect(y: highlighted ? 1 : 0.86)
        .shadow(color: isActive ? .black.opacity(0.5) : .clear, radius: 15, y: 10)
        .animation(DS.Easing.standard(0.35), value: highlighted)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(DS.Easing.standard(0.38)) {
                model.inspectedSegment = segment.id
                model.inspectorTab = .script
            }
        }
    }

    private func playhead(in size: CGSize) -> some View {
        Rectangle()
            .fill(DS.Palette.ink)
            .frame(width: 2)
            .frame(height: size.height + 12)
            .shadow(color: DS.Palette.ink(0.7), radius: 6)
            .overlay(alignment: .top) {
                Circle()
                    .fill(DS.Palette.ink)
                    .frame(width: 9, height: 9)
                    .offset(y: -4)
            }
            .offset(x: size.width * model.playheadFraction, y: -6)
            .allowsHitTesting(false)
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

    @ViewBuilder
    private func inspectorBody(for segment: Segment, at index: Int) -> some View {
        switch model.inspectorTab {
        case .script:
            infoCard(
                segment.script,
                sub: String(localized: "editor.info.words \(segment.wordCount) \(Int(segment.barWeight))", bundle: .module)
            )
        case .caption:
            infoCard(
                segment.captionPreview + " …",
                sub: String(localized: "editor.info.caption", bundle: .module)
            )
        case .timing:
            infoCard(
                "\(model.rangeLabel(at: index))  ·  \(String(format: "%.1f", segment.barWeight))s",
                sub: String(localized: "editor.info.pace \(segment.wordsPerMinute)", bundle: .module)
            )
        case .take:
            infoCard(
                String(localized: "editor.info.takeSelected", bundle: .module),
                sub: String(localized: "editor.info.recorded", bundle: .module)
            )
        case .style:
            infoCard(
                String(localized: "editor.info.style", bundle: .module),
                sub: String(localized: "editor.info.styleSub", bundle: .module)
            )
        }
    }

    private func infoCard(_ text: String, sub: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(text)
                .dsFont(.sans, .regular, 14, lineHeight: 1.5)
                .foregroundStyle(DS.Palette.ink)
            Text(sub)
                .dsFont(.mono, .medium, 10)
                .foregroundStyle(DS.Palette.ink(0.35))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(DS.Palette.hairline(0.04))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(DS.Palette.hairline(0.07), lineWidth: 1)
        }
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
