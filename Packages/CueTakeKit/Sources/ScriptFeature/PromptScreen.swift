import DesignSystem
import Observation
import SwiftUI

/// Idea → blueprint. Two states: writing the brief, and the four-step generation run.
@MainActor
@Observable
public final class PromptModel {
    /// 0 = idle, 1...4 = the step currently running.
    public private(set) var step = 0
    public var promptText: String

    private var task: Task<Void, Never>?

    public init(promptText: String = String(localized: "prompt.default", bundle: .module)) {
        self.promptText = promptText
    }

    public var isRunning: Bool { step > 0 }
    public var progress: Double { Double(step) * 0.25 }

    /// The design advances a step every 850ms, then opens the blueprint.
    public func generate(onFinish: @escaping @MainActor () -> Void) {
        guard task == nil else { return }
        step = 1
        task = Task { [weak self] in
            for next in 2...5 {
                try? await Task.sleep(for: .milliseconds(850))
                guard let self, !Task.isCancelled else { return }
                if next > 4 {
                    step = 0
                    task = nil
                    onFinish()
                    return
                }
                step = next
            }
        }
    }

    /// Cancels the running timer without touching what is already on screen, the way the design
    /// clears its intervals on every navigation.
    public func stopTimers() {
        task?.cancel()
        task = nil
    }

    public func cancel() {
        task?.cancel()
        task = nil
        step = 0
    }
}

public struct PromptScreen: View {
    @Bindable private var model: PromptModel
    private let onBack: () -> Void
    private let onGenerated: () -> Void

    public init(model: PromptModel, onBack: @escaping () -> Void, onGenerated: @escaping () -> Void) {
        self.model = model
        self.onBack = onBack
        self.onGenerated = onGenerated
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                DSCircleButton("←", action: onBack)
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
                .frame(minHeight: 132)
                .padding(17)
                .dsCard(radius: DS.Radius.card, border: DS.Palette.hairline(0.09))

            FlowLayout(horizontalSpacing: 8, verticalSpacing: 8) {
                ForEach(Self.chipKeys, id: \.self) { key in
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
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 16)

            HStack(spacing: 10) {
                option("prompt.option.length", "prompt.option.length.value")
                option("prompt.option.tone", "prompt.option.tone.value")
                option("prompt.option.format", "prompt.option.format.value")
            }
            .padding(.top, 26)

            Spacer(minLength: 0)

            DSPrimaryButton(
                String(localized: "prompt.generate", bundle: .module),
                radius: DS.Radius.cardLarge,
                verticalPadding: 19,
                fontSize: 16
            ) {
                model.generate(onFinish: onGenerated)
            }
        }
    }

    private static let chipKeys: [String.LocalizationValue] = [
        "prompt.chip.productReel",
        "prompt.chip.cameraComparison",
        "prompt.chip.tutorial",
        "prompt.chip.storytelling",
    ]

    private func option(_ key: String.LocalizationValue, _ valueKey: String.LocalizationValue) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(String(localized: key, bundle: .module))
                .dsFont(.mono, .medium, 9, letterSpacing: 0.12)
                .foregroundStyle(DS.Palette.ink(0.38))
            Text(String(localized: valueKey, bundle: .module))
                .dsFont(.sans, .semibold, 14)
                .foregroundStyle(DS.Palette.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .dsCard(radius: 15)
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
