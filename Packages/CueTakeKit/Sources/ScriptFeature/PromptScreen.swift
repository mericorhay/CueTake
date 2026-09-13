import DesignSystem
import Domain
import Observation
import SwiftUI

/// Idea → blueprint. Two states: writing the brief, and the generation run.
@MainActor
@Observable
public final class PromptModel {
    /// 0 = idle, 1...4 = the step currently running.
    public private(set) var step = 0
    public var promptText: String
    /// Set when generation failed, so the user is told rather than dropped back with nothing.
    public private(set) var failure: String?

    /// How long the video should be, in seconds.
    public var lengthSeconds = 30
    public var tone: Tone = .energetic
    public var platform: TargetPlatform = .instagramReels

    public static let lengthChoices = [15, 30, 60, 90]
    public static let platformChoices: [TargetPlatform] = [.instagramReels, .tiktok, .youtubeShorts, .youtube]

    /// The voice of the script. Named in the user's language on screen, and in plain English in
    /// the brief, because English is what the model follows most reliably whatever language it is
    /// writing in.
    public enum Tone: String, CaseIterable, Sendable {
        case energetic, calm, funny, expert, story

        public var briefValue: String {
            switch self {
            case .energetic: "energetic and punchy"
            case .calm: "calm and warm"
            case .funny: "funny, light, a little self-aware"
            case .expert: "confident and expert, no fluff"
            case .story: "told as a short personal story"
            }
        }
    }

    /// `Bundle.module` is internal to the module, so the prefilled brief is resolved in the body
    /// rather than in a default argument, which would leak it into the public signature.
    public init(promptText: String? = nil) {
        self.promptText = promptText ?? String(localized: "prompt.default", bundle: .module)
    }

    public var isRunning: Bool { step > 0 }
    public var progress: Double { Double(step) * 0.25 }

    // The steps used to advance on a timer, because there was nothing to time. They are driven by
    // the work now: the screen draws them, and whoever owns the model moves them.

    public func begin() {
        failure = nil
        step = 1
    }

    public func advance(to next: Int) {
        guard next > step, next <= 4 else { return }
        step = next
    }

    public func finish() {
        step = 0
    }

    public func fail(_ reason: String) {
        failure = reason
        step = 0
    }

    /// Nothing ticks here any more. Kept so navigation can treat every model the same way.
    public func stopTimers() {}

    public func cancel() {
        step = 0
        failure = nil
    }
}

public struct PromptScreen: View {
    @Bindable private var model: PromptModel
    private let onBack: () -> Void
    private let onGenerated: () async -> Void

    public init(model: PromptModel, onBack: @escaping () -> Void, onGenerated: @escaping () async -> Void) {
        self.model = model
        self.onBack = onBack
        self.onGenerated = onGenerated
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                DSBackButton(action: onBack)
                Spacer(minLength: 0)
                DSKicker(String(localized: "prompt.kicker", bundle: .module))
            }

            if model.isRunning {
                running
            } else {
                idle
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 64)
        .padding(.bottom, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .dsScreenLayout()
        .background(DS.Palette.screen)
        .dsEnter(.screen())
    }

    // MARK: - Idle

    private var idle: some View {
        VStack(alignment: .leading, spacing: 0) {
            DSHeadline(String(localized: "prompt.title", bundle: .module), size: 32)
                .padding(.top, 24)
                .padding(.bottom, 18)

            TextEditor(text: $model.promptText)
                .dsFont(.sans, .regular, 16, lineHeight: 1.45)
                .foregroundStyle(DS.Palette.ink)
                .scrollContentBackground(.hidden)
                // `TextEditor` is greedy vertically and a minimum does not hold it back: left
                // alone it eats the whole column and pushes the chips and options off the
                // bottom. The design's textarea is a fixed 132pt box that scrolls its content.
                .frame(height: 132)
                .padding(17)
                .dsCard(radius: DS.Radius.card, border: DS.Palette.hairline(0.09))

            FlowLayout(horizontalSpacing: 8, verticalSpacing: 8) {
                ForEach(Array(Self.chipKeys.enumerated()), id: \.offset) { _, key in
                    let label = String(localized: key, bundle: .module)
                    Button {
                        model.promptText = label
                    } label: {
                        Text(label)
                            .dsFont(.sans, .regular, 12)
                            .foregroundStyle(DS.Palette.ink(0.72))
                            .padding(.horizontal, 13)
                            .padding(.vertical, 9)
                            .background(
                                Capsule().fill(DS.Palette.hairline(0.055))
                            )
                            .overlay(Capsule().stroke(DS.Palette.hairline(0.08), lineWidth: 1))
                    }
                    .buttonStyle(.dsPress)
                }
            }
            .padding(.top, 16)

            // Three real choices. They used to be three labels showing fixed values, which read as
            // settings and did nothing: the script was always thirty seconds, energetic, a Reel.
            HStack(spacing: 10) {
                choice("prompt.option.length", value: Self.lengthLabel(model.lengthSeconds)) {
                    ForEach(PromptModel.lengthChoices, id: \.self) { seconds in
                        Button(Self.lengthLabel(seconds)) { model.lengthSeconds = seconds }
                    }
                }
                choice("prompt.option.tone", value: Self.toneLabel(model.tone)) {
                    ForEach(PromptModel.Tone.allCases, id: \.self) { tone in
                        Button(Self.toneLabel(tone)) { model.tone = tone }
                    }
                }
                choice("prompt.option.format", value: Self.platformLabel(model.platform)) {
                    ForEach(PromptModel.platformChoices, id: \.self) { platform in
                        Button(Self.platformLabel(platform)) { model.platform = platform }
                    }
                }
            }
            .padding(.top, 26)

            Spacer(minLength: 0)

            DSPrimaryButton(
                String(localized: "prompt.generate", bundle: .module),
                radius: DS.Radius.cardLarge,
                verticalPadding: 19,
                fontSize: 16
            ) {
                Task { await onGenerated() }
            }

            if let failure = model.failure {
                Text(failure)
                    .dsFont(.sans, .regular, 12)
                    .foregroundStyle(DS.Palette.accent)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 10)
            }
        }
    }

    private static let chipKeys: [String.LocalizationValue] = [
        "prompt.chip.productReel",
        "prompt.chip.cameraComparison",
        "prompt.chip.tutorial",
        "prompt.chip.storytelling",
    ]

    private func choice<Options: View>(
        _ key: String.LocalizationValue,
        value: String,
        @ViewBuilder options: () -> Options
    ) -> some View {
        Menu {
            options()
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 3) {
                    Text(String(localized: key, bundle: .module))
                        .dsFont(.mono, .medium, 9, letterSpacing: 0.12)
                        .foregroundStyle(DS.Palette.ink(0.38))
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(DS.Palette.ink(0.3))
                }
                Text(value)
                    .dsFont(.sans, .semibold, 14)
                    .foregroundStyle(DS.Palette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .contentTransition(.opacity)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .dsCard(radius: 15)
            .contentShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        }
        .animation(DS.Motion.snap, value: value)
    }

    static func lengthLabel(_ seconds: Int) -> String {
        String(localized: "prompt.length.seconds \(seconds)", bundle: .module)
    }

    static func toneLabel(_ tone: PromptModel.Tone) -> String {
        switch tone {
        case .energetic: String(localized: "prompt.tone.energetic", bundle: .module)
        case .calm: String(localized: "prompt.tone.calm", bundle: .module)
        case .funny: String(localized: "prompt.tone.funny", bundle: .module)
        case .expert: String(localized: "prompt.tone.expert", bundle: .module)
        case .story: String(localized: "prompt.tone.story", bundle: .module)
        }
    }

    static func platformLabel(_ platform: TargetPlatform) -> String {
        switch platform {
        case .instagramReels: "Reels · 9:16"
        case .tiktok: "TikTok · 9:16"
        case .youtubeShorts: "Shorts · 9:16"
        case .youtube: "YouTube · 16:9"
        case .generic: "9:16"
        }
    }

    // MARK: - Running

    private var running: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 0)

            Text(model.promptText)
                .dsFont(.sans, .regular, 13, lineHeight: 1.5)
                .foregroundStyle(DS.Palette.ink(0.5))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .dsCard(radius: 16)

            VStack(spacing: 3) {
                ForEach(Array(Self.steps.enumerated()), id: \.offset) { index, step in
                    stepRow(index: index, step: step)
                }
            }
            .padding(.top, 32)
            .padding(.bottom, 8)

            // Progress bar, 2pt, filling in 0.7s with the standard curve.
            ZStack(alignment: .leading) {
                Capsule().fill(DS.Palette.hairline(0.08))
                GeometryReader { proxy in
                    Capsule()
                        .fill(DS.Palette.accent)
                        .frame(width: proxy.size.width * model.progress)
                }
            }
            .frame(height: 2)
            .padding(.top, 20)
            .animation(DS.Easing.standard(0.7), value: model.progress)

            Spacer(minLength: 0)
        }
        .dsEnter(.screen(duration: 0.4))
    }

    private struct GenerationStep {
        var labelKey: String.LocalizationValue
        var noteKey: String.LocalizationValue
    }

    private static let steps: [GenerationStep] = [
        GenerationStep(labelKey: "prompt.step.intent", noteKey: "prompt.step.intent.note"),
        GenerationStep(labelKey: "prompt.step.beats", noteKey: "prompt.step.beats.note"),
        GenerationStep(labelKey: "prompt.step.writing", noteKey: "prompt.step.writing.note"),
        GenerationStep(labelKey: "prompt.step.timing", noteKey: "prompt.step.timing.note"),
    ]

    private func stepRow(index: Int, step: GenerationStep) -> some View {
        let isDone = model.step > index + 1
        let isActive = model.step == index + 1

        return HStack(spacing: 12) {
            Group {
                if isDone {
                    Circle().fill(DS.Palette.accent)
                } else if isActive {
                    Circle()
                        .strokeBorder(DS.Palette.accent, lineWidth: 2)
                        .dsPulse()
                } else {
                    Circle().fill(DS.Palette.hairline(0.1))
                }
            }
            .frame(width: 18, height: 18)
            .animation(DS.Easing.ease(0.4), value: model.step)

            Text(String(localized: step.labelKey, bundle: .module))
                .dsFont(.archivo, .semibold, 17)
                .foregroundStyle(
                    isDone ? DS.Palette.ink(0.4) : (isActive ? DS.Palette.ink : DS.Palette.ink(0.18))
                )
                .animation(DS.Easing.ease(0.4), value: model.step)

            Spacer(minLength: 0)

            Text(String(localized: step.noteKey, bundle: .module))
                .dsFont(.mono, .medium, 10)
                .foregroundStyle(DS.Palette.ink(0.3))
        }
        .padding(.vertical, 13)
        .padding(.horizontal, 2)
    }
}
