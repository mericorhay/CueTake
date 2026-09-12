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
    private let onBack: () -> Void
    private let onExport: () -> Void

    @State private var cueIndex = 0
    @State private var style: Style = .pop
    @State private var position: Position = .bottom

    public init(project: Project, onBack: @escaping () -> Void, onExport: @escaping () -> Void) {
        self.project = project
        self.onBack = onBack
        self.onExport = onExport
    }

    /// Every segment's words, chunked four at a time — the design's cue list.
    private var cues: [String] {
        project.segments.flatMap { segment -> [String] in
            let words = ScriptText.words(in: segment.script).map(String.init)
            return stride(from: 0, to: words.count, by: 4).map { start in
                words[start..<min(start + 4, words.count)].joined(separator: " ")
            }
        }
    }

    private var visibleCues: [String] { Array(cues.prefix(9)) }

    public var body: some View {
        ZStack {
            CaptionsBackdrop()

            VStack(spacing: 0) {
                header

                captionPreview
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, 24)

                controls
            }
            .padding(.top, 58)
            .padding(.bottom, 34)
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
            .buttonStyle(.plain)
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
            Text(text)
                .dsFont(.archivo, .extrabold, 30, lineHeight: 1.15, letterSpacing: -0.02)
                .foregroundStyle(DS.Palette.ink)
                .multilineTextAlignment(.center)
                .shadow(color: .black.opacity(0.9), radius: 12, y: 4)
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
            Text(text)
                .dsFont(.archivo, .bold, 26, lineHeight: 1.2)
                .foregroundStyle(DS.Palette.lime)
                .multilineTextAlignment(.center)
                .shadow(color: .black.opacity(0.85), radius: 9, y: 3)
        }
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
                        .buttonStyle(.plain)
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
                    DSPill(option.rawValue, isOn: style == option) { style = option }
                }
            }
            .padding(.bottom, 14)

            HStack(spacing: 7) {
                ForEach(Position.allCases, id: \.self) { option in
                    DSPill(option.rawValue, isOn: position == option) { position = option }
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
