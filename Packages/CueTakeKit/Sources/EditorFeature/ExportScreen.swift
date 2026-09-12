import DesignSystem
import Observation
import SwiftUI

/// Render progress as four staged cards, then the share sheet.
@MainActor
@Observable
public final class ExportModel {
    /// 0 = not started, 1...4 = the stage currently running, 4 = finished.
    public private(set) var stage = 0
    private var task: Task<Void, Never>?

    public init() {}

    public var isIdle: Bool { stage == 0 }
    public var isDone: Bool { stage >= 4 }

    /// The design advances a stage every 1150ms. VideoExporting replaces this with real progress.
    public func run() {
        guard task == nil else { return }
        stage = 1
        task = Task { [weak self] in
            for next in 2...5 {
                try? await Task.sleep(for: .milliseconds(1150))
                guard let self, !Task.isCancelled else { return }
                if next > 4 {
                    task = nil
                    return
                }
                stage = next
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
        stage = 0
    }
}

public struct ExportScreen: View {
    @Bindable private var model: ExportModel
    private let captionStyleName: String
    private let onBack: () -> Void
    private let onDone: () -> Void

    public init(
        model: ExportModel,
        captionStyleName: String = "pop",
        onBack: @escaping () -> Void,
        onDone: @escaping () -> Void
    ) {
        self.model = model
        self.captionStyleName = captionStyleName
        self.onBack = onBack
        self.onDone = onDone
    }

    private struct Stage {
        var titleKey: String.LocalizationValue
        var note: String
    }

    private var stages: [Stage] {
        [
            Stage(titleKey: "export.stage.timeline", note: String(localized: "export.stage.timeline.note", bundle: .module)),
            Stage(titleKey: "export.stage.render", note: String(localized: "export.stage.render.note", bundle: .module)),
            Stage(titleKey: "export.stage.captions", note: String(localized: "export.stage.captions.note \(captionStyleName)", bundle: .module)),
            Stage(titleKey: "export.stage.final", note: String(localized: "export.stage.final.note", bundle: .module)),
        ]
    }

    public var body: some View {
        VStack(spacing: 0) {
            header

            VStack(spacing: 0) {
                ForEach(Array(stages.enumerated()), id: \.offset) { index, stage in
                    stageCard(stage, at: index)
                }
            }
            .frame(maxHeight: .infinity)

            if model.isDone {
                finished
            } else if model.isIdle {
                DSPrimaryButton(
                    String(localized: "export.render", bundle: .module),
                    radius: DS.Radius.cardLarge,
                    verticalPadding: 19,
                    fontSize: 16
                ) {
                    model.run()
                }
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 60)
        .padding(.bottom, 36)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DS.Palette.screen)
        .dsEnter(.screen())
    }

    private var header: some View {
        HStack {
            DSCircleButton("←", size: 34, fontSize: 15, action: onBack)
            Spacer(minLength: 0)
            DSKicker(String(localized: "export.kicker", bundle: .module))
            Spacer(minLength: 0)
            Color.clear.frame(width: 34, height: 34)
        }
    }

    private func stageCard(_ stage: Stage, at index: Int) -> some View {
        let isDone = model.stage > index + 1
        let isActive = model.stage == index + 1
        let isIdle = model.isIdle

        let ink: Color = isIdle
            ? DS.Palette.ink(0.35)
            : (isDone ? DS.Palette.ink(0.45) : (isActive ? DS.Palette.ink : DS.Palette.ink(0.2)))

        return HStack(spacing: 13) {
            Text(isDone ? "✓" : String(index + 1))
                .dsFont(.mono, .medium, 13)
                .foregroundStyle(isDone || isActive ? DS.Palette.inkInverse : DS.Palette.ink(0.4))
                .frame(width: 34, height: 34)
                .background(
                    RoundedRectangle(cornerRadius: DS.Radius.s, style: .continuous)
                        .fill(isDone ? DS.Palette.accent : (isActive ? DS.Palette.lime : DS.Palette.hairline(0.07)))
                )
                .modifier(PulseIfActive(isActive: isActive))

            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: stage.titleKey, bundle: .module))
                    .dsFont(.archivo, .bold, 18)
                    .foregroundStyle(ink)
                Text(stage.note)
                    .dsFont(.sans, .regular, 11)
                    .foregroundStyle(DS.Palette.ink(0.3))
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                .fill(isActive ? DS.Palette.surfaceActive : DS.Palette.surface)
        )
        .overlay {
            RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                .stroke(isActive ? DS.Palette.lime(0.4) : DS.Palette.hairline(0.06), lineWidth: 1)
        }
        .scaleEffect(isActive ? 1.03 : 0.97)
        .rotation3DEffect(
            .degrees(isActive ? 0 : 6),
            axis: (x: 1, y: 0, z: 0),
            perspective: 0.4
        )
        .padding(.bottom, 10)
        .animation(DS.Easing.standard(0.55), value: model.stage)
    }

    private var finished: some View {
        VStack(alignment: .leading, spacing: 0) {
            DSHeadline(String(localized: "export.ready", bundle: .module), size: 28)
                .padding(.bottom, 6)

            Text("export.summary", bundle: .module)
                .dsFont(.sans, .regular, 13)
                .foregroundStyle(DS.Palette.ink(0.45))
                .padding(.bottom, 18)

            HStack(spacing: 9) {
                ForEach(["Reels", "TikTok", "Shorts", "Files"], id: \.self) { target in
                    Text(target)
                        .dsFont(.sans, .semibold, 12)
                        .foregroundStyle(DS.Palette.ink(0.75))
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .dsCard(radius: 15, border: DS.Palette.hairline(0.08))
                }
            }

            DSPrimaryButton(
                String(localized: "export.done", bundle: .module),
                verticalPadding: 17,
                fontSize: 16,
                glow: false,
                action: onDone
            )
            .padding(.top, 12)
        }
        .dsEnter(.rise(duration: 0.45))
    }
}

/// The active stage's badge pulses; the others hold still.
private struct PulseIfActive: ViewModifier {
    let isActive: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isActive {
            content.dsPulse(duration: 1.2)
        } else {
            content
        }
    }
}
