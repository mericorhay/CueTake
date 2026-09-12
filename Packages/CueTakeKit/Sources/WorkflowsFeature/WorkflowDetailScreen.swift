import DesignSystem
import Domain
import Observation
import SwiftUI

/// One workflow, its inputs and its steps, with a run that walks down the list.
///
/// The steps here mirror `WorkflowDefinition`; when WorkflowEngine's handlers are wired up,
/// `WorkflowRunner` drives this state instead of the timer.
@MainActor
@Observable
public final class WorkflowRunModel {
    /// -1 = not started, 0...4 = the step in progress, 5 = finished.
    public private(set) var step = -1
    private var task: Task<Void, Never>?

    public init() {}

    public var isRunning: Bool { step >= 0 && step < 5 }
    public var isFinished: Bool { step >= 5 }

    /// The design advances a step every 900ms.
    public func run() {
        guard task == nil else { return }
        step = 0
        task = Task { [weak self] in
            for next in 1...6 {
                try? await Task.sleep(for: .milliseconds(900))
                guard let self, !Task.isCancelled else { return }
                if next > 5 {
                    task = nil
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

    public func reset()() {
        task?.cancel()
        task = nil
        step = -1
    }
}

public struct WorkflowDetailScreen: View {
    @Bindable private var model: WorkflowRunModel
    private let onBack: () -> Void
    private let onOpenResult: () -> Void

    public init(model: WorkflowRunModel, onBack: @escaping () -> Void, onOpenResult: @escaping () -> Void) {
        self.model = model
        self.onBack = onBack
        self.onOpenResult = onOpenResult
    }

    private struct Step {
        var titleKey: String.LocalizationValue
        var noteKey: String.LocalizationValue
    }

    private static let steps: [Step] = [
        Step(titleKey: "workflow.step.idea", noteKey: "workflow.step.idea.note"),
        Step(titleKey: "workflow.step.script", noteKey: "workflow.step.script.note"),
        Step(titleKey: "workflow.step.record", noteKey: "workflow.step.record.note"),
        Step(titleKey: "workflow.step.captions", noteKey: "workflow.step.captions.note"),
        Step(titleKey: "workflow.step.export", noteKey: "workflow.step.export.note"),
    ]

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DSCircleButton("←", size: 34, fontSize: 15, action: onBack)

            DSHeadline(String(localized: "workflow.title", bundle: .module), size: 30)
                .padding(.top, 18)
                .padding(.bottom, 7)

            Text("workflow.description", bundle: .module)
                .dsFont(.sans, .regular, 13, lineHeight: 1.5)
                .foregroundStyle(DS.Palette.ink(0.45))

            HStack(spacing: 8) {
                input("workflow.input.kicker", "workflow.input.product")
                input("workflow.input.kicker", "workflow.input.feature")
            }
            .padding(.top, 14)

            VStack(spacing: 0) {
                ForEach(Array(Self.steps.enumerated()), id: \.offset) { index, step in
                    stepRow(step, at: index, isLast: index == Self.steps.count - 1)
                }
            }
            .padding(.top, 20)
            .frame(maxHeight: .infinity, alignment: .top)

            DSPrimaryButton(
                runLabel,
                fill: model.isRunning ? DS.Palette.lime : DS.Palette.accent,
                verticalPadding: 18,
                fontSize: 16,
                glow: false
            ) {
                if model.isFinished {
                    onOpenResult()
                } else if !model.isRunning {
                    model.run()
                }
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 60)
        .padding(.bottom, 34)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.Palette.screen)
        .dsEnter(.screen())
    }

    private var runLabel: String {
        if model.isFinished {
            return String(localized: "workflow.run.open", bundle: .module)
        }
        if model.isRunning {
            return String(localized: "workflow.run.running", bundle: .module)
        }
        return String(localized: "workflow.run.start", bundle: .module)
    }

    private func input(_ kicker: String.LocalizationValue, _ value: String.LocalizationValue) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(String(localized: kicker, bundle: .module))
                .dsFont(.mono, .medium, 9, letterSpacing: 0.12)
                .foregroundStyle(DS.Palette.ink(0.35))
            Text(String(localized: value, bundle: .module))
                .dsFont(.sans, .medium, 13)
                .foregroundStyle(DS.Palette.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(11)
        .dsCard(radius: DS.Radius.m)
    }

    private func stepRow(_ step: Step, at index: Int, isLast: Bool) -> some View {
        let isDone = model.step > index
        let isActive = model.step == index

        return HStack(alignment: .top, spacing: 13) {
            VStack(spacing: 0) {
                Text(isDone ? "✓" : (isActive ? "●" : "○"))
                    .dsFont(.mono, .medium, 11)
                    .foregroundStyle(isDone || isActive ? DS.Palette.inkInverse : DS.Palette.ink(0.35))
                    .frame(width: 26, height: 26)
                    .background(
                        Circle().fill(
                            isDone
                                ? DS.Palette.accent
                                : (isActive ? DS.Palette.lime : DS.Palette.hairline(0.07))
                        )
                    )
                    .modifier(PulseWhileActive(isActive: isActive))

                if !isLast {
                    Rectangle()
                        .fill(isDone ? DS.Palette.accent : DS.Palette.hairline(0.1))
                        .frame(width: 1.5)
                        .frame(minHeight: 18)
                        .animation(DS.Easing.ease(0.4), value: isDone)
                }
            }
            .frame(width: 26)

            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: step.titleKey, bundle: .module))
                    .dsFont(.sans, .semibold, 15)
                    .foregroundStyle(
                        isActive ? DS.Palette.ink : (isDone ? DS.Palette.ink(0.55) : DS.Palette.ink(0.3))
                    )
                Text(String(localized: step.noteKey, bundle: .module))
                    .dsFont(.sans, .regular, 11)
                    .foregroundStyle(DS.Palette.ink(0.35))
            }
            .padding(.bottom, 11)

            Spacer(minLength: 0)
        }
        .animation(DS.Easing.ease(0.4), value: model.step)
    }
}

private struct PulseWhileActive: ViewModifier {
    let isActive: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isActive {
            content.dsPulse(duration: 1)
        } else {
            content
        }
    }
}
