import DesignSystem
import Domain
import SwiftUI

/// Caption cue picker with live style and position preview over the video.
public struct CaptionsScreen: View {
    public enum Style: String, CaseIterable, Sendable {
        case pop = "Pop"
        case clean = "Clean"
        case karaoke = "Karaoke"
    }

    public enum Position: String, CaseIterable, Sendable {
        case top = "Top"
        case middle = "Middle"
        case bottom = "Bottom"
    }

    private let project: Project
    /// Reports the choice upward: the screen owns the picking, the project owns the decision.
    /// Without this the style is forgotten the moment the screen is left, which is exactly when
    /// the user believes they have set it.
    private let onStyleChange: (String, CaptionPosition) -> Void
    private let onBack: () -> Void
    private let onExport: () -> Void
    /// Runs speech transcription, which is where cues come from.
    private let onTranscribe: () -> Void

    @State private var cueIndex = 0
    @State private var style: Style = .pop
    @State private var position: Position = .bottom

    /// - Parameter style: the preset from Settings. `.off` has no screen of its own — the user
    ///   asked for no captions, not for a blank editor — so it opens on Pop like a fresh choice.
    public init(
        project: Project,
        style: CaptionPreference = .pop,
        onStyleChange: @escaping (String, CaptionPosition) -> Void = { _, _ in },
        onBack: @escaping () -> Void,
        onExport: @escaping () -> Void,
        onTranscribe: @escaping () -> Void = {}
    ) {
        self.project = project
        self.onStyleChange = onStyleChange
        self.onBack = onBack
        self.onExport = onExport
        self.onTranscribe = onTranscribe
        _style = State(initialValue: Style(style))
    }

    /// The project's real cues, once there are any.
    ///
    /// Falls back to chunking the script only for a project that has been written but not shot —
    /// there is nothing else to show, and an empty screen would suggest captions are broken rather
    /// than simply not recorded yet.
    private var cues: [String] {
        let transcribed = project.segments.flatMap(\.captions).map(\.text)
        guard transcribed.isEmpty else { return transcribed }

        return project.segments.flatMap { segment -> [String] in
            let words = ScriptText.words(in: segment.script).map(String.init)
            return stride(from: 0, to: words.count, by: 4).map { start in
                words[start..<min(start + 4, words.count)].joined(separator: " ")
            }
        }
    }

    private var visibleCues: [String] { Array(cues.prefix(9)) }

    /// True when the project has footage but nothing has listened to it yet.
    ///
    /// This is the state the screen used to show as a blank rectangle, which reads as "captions
    /// are broken" rather than "there is nothing to caption yet". The difference between those two
    /// is a sentence and a button.
    private var needsTranscription: Bool {
        project.segments.allSatisfy(\.captions.isEmpty)
            && project.segments.contains { $0.selectedTake != nil }
    }

    /// Shown over the preview when there is nothing to preview.
    private var transcribePrompt: some View {
        VStack(spacing: 14) {
            Text("captions.empty.title", bundle: .module)
                .dsFont(.archivo, .bold, 20)
                .foregroundStyle(DS.Palette.ink)
                .multilineTextAlignment(.center)

            Text("captions.empty.note", bundle: .module)
                .dsFont(.sans, .regular, 13, lineHeight: 1.45)
                .foregroundStyle(DS.Palette.ink(0.5))
                .multilineTextAlignment(.center)

            Button {
                onTranscribe()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "waveform.and.person.filled")
                        .font(.system(size: 13, weight: .semibold))
                    Text("captions.empty.action", bundle: .module)
                        .dsFont(.sans, .semibold, 15)
                }
                .foregroundStyle(DS.Palette.inkInverse)
                .padding(.horizontal, 22)
                .padding(.vertical, 15)
                .background(
                    Capsule().fill(DS.Palette.accent)
                )
            }
            .buttonStyle(.dsPress(radius: 30))
        }
        .padding(26)
        .frame(maxWidth: 320)
        .dsGlass(
            tint: DS.Palette.glassSheet(0.93),
            in: RoundedRectangle(cornerRadius: DS.Radius.sheet, style: .continuous),
            border: DS.Palette.hairline(0.12)
        )
        .dsEnter(.rise(duration: 0.4))
    }

    public var body: some View {
        ZStack {
            CaptionsBackdrop()

            VStack(spacing: 0) {
                header

                captionPreview
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, 24)
                    .overlay {
                        if needsTranscription { transcribePrompt }
                    }

                controls
            }
            .padding(.top, 58)
            .padding(.bottom, 34)
            .dsScreenLayout(scrolls: true)
        }
        .dsEnter(.screen())
    }

    private var header: some View {
        HStack(spacing: 10) {
            DSCircleButton("←", size: 34, fontSize: 15, style: .glass, action: onBack)
            DSKicker(String(localized: "captions.kicker", bundle: .module), color: DS.Palette.ink(0.55))
            Spacer(minLength: 0)
            Button(action: onExport) {
                Text("captions.export", bundle: .module)
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
    }

    private var captionPreview: some View {
        VStack {
            if position != .top { Spacer(minLength: 0) }

            cueText
                .containerRelativeFrame(.horizontal) { width, _ in width * 0.88 }

            if position != .bottom { Spacer(minLength: 0) }
        }
        .animation(DS.Easing.ease(0.3), value: position)
        .animation(DS.Easing.ease(0.3), value: style)
    }

    @ViewBuilder
    private var cueText: some View {
        let text = visibleCues.indices.contains(cueIndex) ? visibleCues[cueIndex] : (visibleCues.first ?? "")

        switch style {
        case .pop:
            // 30px/1.15 with text-shadow: 0 4px 24px rgba(0,0,0,.9)
            TightText(
                text,
                .archivo,
                .extrabold,
                30,
                lineHeight: 1.15,
                letterSpacing: -0.02,
                alignment: .center,
                shadow: .init(color: .black.opacity(0.9), offset: CGSize(width: 0, height: 4), blur: 24)
            )
        case .clean:
            Text(text)
                .dsFont(.sans, .medium, 20, lineHeight: 1.4)
                .foregroundStyle(DS.Palette.ink)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .dsGlass(
                    tint: DS.Palette.inkInverse(0.55),
                    in: RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous),
                    border: nil
                )
        case .karaoke:
            // 26px/1.2 with text-shadow: 0 3px 18px rgba(0,0,0,.85)
            TightText(
                text,
                .archivo,
                .bold,
                26,
                lineHeight: 1.2,
                color: DS.Palette.lime,
                alignment: .center,
                shadow: .init(color: .black.opacity(0.85), offset: CGSize(width: 0, height: 3), blur: 18)
            )
        }
    }

    private func report() {
        onStyleChange(style.rawValue.lowercased(), position.captionPosition)
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView(.horizontal) {
                HStack(spacing: 5) {
                    ForEach(Array(visibleCues.enumerated()), id: \.offset) { index, cue in
                        let isOn = cueIndex == index
                        Button {
                            cueIndex = index
                        } label: {
                            Text(cue.split(separator: " ").prefix(2).joined(separator: " "))
                                .dsFont(.sans, .medium, 11)
                                .foregroundStyle(isOn ? DS.Palette.inkInverse : DS.Palette.ink(0.6))
                                .lineLimit(1)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: DS.Radius.s, style: .continuous)
                                        .fill(isOn ? DS.Palette.ink : DS.Palette.hairline(0.07))
                                )
                        }
                        .buttonStyle(.dsPress)
                    }
                }
            }
            .scrollIndicators(.hidden)
            .padding(.bottom, 14)

            Text("captions.style", bundle: .module)
                .dsFont(.mono, .medium, 9, letterSpacing: 0.14)
                .foregroundStyle(DS.Palette.ink(0.35))
                .padding(.bottom, 8)

            HStack(spacing: 7) {
                ForEach(Style.allCases, id: \.self) { option in
                    DSPill(option.label, isOn: style == option) {
                        style = option
                        report()
                    }
                }
            }
            .padding(.bottom, 14)

            HStack(spacing: 7) {
                ForEach(Position.allCases, id: \.self) { option in
                    DSPill(option.label, isOn: position == option) {
                        position = option
                        report()
                    }
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 8)
        .background {
            UnevenRoundedRectangle(
                topLeadingRadius: DS.Radius.sheet,
                topTrailingRadius: DS.Radius.sheet,
                style: .continuous
            )
            .fill(.ultraThinMaterial)
            .overlay(
                UnevenRoundedRectangle(
                    topLeadingRadius: DS.Radius.sheet,
                    topTrailingRadius: DS.Radius.sheet,
                    style: .continuous
                )
                .fill(DS.Palette.glassSheet(0.9))
            )
        }
        .overlay(alignment: .top) {
            Rectangle().fill(DS.Palette.hairline(0.1)).frame(height: 1)
        }
    }
}

/// Same plate the studio uses, so captions are judged against the footage.
private struct CaptionsBackdrop: View {
    var body: some View {
        DS.Palette.camera
            .overlay {
                LinearGradient(
                    stops: [
                        .init(color: Color(hex: 0x0B0B0D, alpha: 0.55), location: 0),
                        .init(color: Color(hex: 0x0B0B0D, alpha: 0.15), location: 0.35),
                        .init(color: Color(hex: 0x0B0B0D, alpha: 0.82), location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .ignoresSafeArea()
    }
}

extension CaptionsScreen.Style {
    init(_ preference: CaptionPreference) {
        switch preference {
        case .off, .pop: self = .pop
        case .clean: self = .clean
        case .karaoke: self = .karaoke
        }
    }

    var label: String {
        switch self {
        case .pop: String(localized: "captions.style.pop", bundle: .module)
        case .clean: String(localized: "captions.style.clean", bundle: .module)
        case .karaoke: String(localized: "captions.style.karaoke", bundle: .module)
        }
    }
}

extension CaptionsScreen.Position {
    /// Normalised placement in the frame. Centred horizontally in every case; only the height
    /// changes, because a caption that drifts sideways reads as a mistake rather than a choice.
    var captionPosition: CaptionPosition {
        switch self {
        case .top: CaptionPosition(x: 0.5, y: 0.12)
        case .middle: CaptionPosition(x: 0.5, y: 0.5)
        case .bottom: CaptionPosition(x: 0.5, y: 0.86)
        }
    }

    var label: String {
        switch self {
        case .top: String(localized: "captions.position.top", bundle: .module)
        case .middle: String(localized: "captions.position.middle", bundle: .module)
        case .bottom: String(localized: "captions.position.bottom", bundle: .module)
        }
    }
}
