import DesignSystem
import Domain
import SwiftUI

/// A workflow the assistant wrote, as something to use rather than something to read.
///
/// This is the first place the assistant does more than talk: ask it to "cut the pauses and add
/// karaoke captions" and the answer includes the pipeline that does it. The card shows its shape
/// — the sections as a coloured bar, the tools in order — and two ways forward: open it in the
/// workflow studio to adjust, or run it on the open project now.
struct WorkflowProposalCard: View {
    let workflow: WorkflowDefinition
    let onOpen: () -> Void
    let onRun: () -> Void

    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "flowchart.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DS.Palette.lime)
                Text(workflow.name)
                    .dsFont(.sans, .semibold, 14)
                    .foregroundStyle(DS.Palette.ink)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text(AppLocalization.string("assistant.workflow.steps \(workflow.steps.count)", bundle: .module))
                    .dsFont(.mono, .medium, 10)
                    .foregroundStyle(DS.Palette.ink(0.56))
            }

            if !workflow.sections.isEmpty {
                GeometryReader { proxy in
                    let total = max(1, workflow.sections.reduce(0) { $0 + $1.seconds })
                    let gaps = CGFloat(workflow.sections.count - 1) * 3
                    HStack(spacing: 3) {
                        ForEach(workflow.sections) { section in
                            Capsule()
                                .fill(DS.Palette.segment(at: section.segmentRole.paletteIndex))
                                .frame(width: max(4, (proxy.size.width - gaps) * section.seconds / total))
                        }
                    }
                }
                .frame(height: 5)
            }

            VStack(alignment: .leading, spacing: 5) {
                ForEach(Array(workflow.steps.filter(\.isEnabled).enumerated()), id: \.offset) { index, step in
                    HStack(spacing: 7) {
                        Text(verbatim: "\(index + 1)")
                            .dsFont(.mono, .medium, 10)
                            .foregroundStyle(DS.Palette.inkInverse)
                            .frame(width: 16, height: 16)
                            .background(Circle().fill(DS.Palette.lime))
                        Text(Self.stepName(step.kind))
                            .dsFont(.sans, .regular, 12)
                            .foregroundStyle(DS.Palette.ink(0.8))
                    }
                    .opacity(shown ? 1 : 0)
                    .offset(x: shown ? 0 : -8)
                    .animation(reduceMotion ? nil : DS.Motion.settle.delay(0.05 * Double(index)), value: shown)
                }
            }

            HStack(spacing: 8) {
                Button(action: onOpen) {
                    Text("assistant.workflow.open", bundle: .module)
                        .dsFont(.sans, .semibold, 12)
                        .foregroundStyle(DS.Palette.ink)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.dsPress(radius: 16))
                .glassEffect(.regular.interactive(), in: .capsule)

                Button(action: onRun) {
                    Label(AppLocalization.string("assistant.workflow.run", bundle: .module), systemImage: "play.fill")
                        .dsFont(.sans, .semibold, 12)
                        .foregroundStyle(DS.Palette.inkInverse)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.dsPress(radius: 16))
                .glassEffect(.regular.tint(DS.Palette.lime).interactive(), in: .capsule)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(DS.Palette.hairline(0.06))
        )
        .onAppear { shown = true }
    }

    /// Plain names for the tools, in the conversation's language.
    static func stepName(_ kind: WorkflowStepKind) -> String {
        switch kind {
        case .assembleSections: AppLocalization.string("assistant.step.assemble", bundle: .module)
        case .analyzeSpeech: AppLocalization.string("assistant.step.transcribe", bundle: .module)
        case .trimSilences: AppLocalization.string("assistant.step.pauses", bundle: .module)
        case .cutWords: AppLocalization.string("assistant.step.fillers", bundle: .module)
        case .setSpeed(let o): AppLocalization.string("assistant.step.speed \(String(format: "%g", o.speed))", bundle: .module)
        case .cleanAudio: AppLocalization.string("assistant.step.clean", bundle: .module)
        case .musicBed: AppLocalization.string("assistant.step.music", bundle: .module)
        case .generateCaptions: AppLocalization.string("assistant.step.captions", bundle: .module)
        case .applyCaptionStyle(let preset): AppLocalization.string("assistant.step.look \(preset.capitalized)", bundle: .module)
        case .export: AppLocalization.string("assistant.step.export", bundle: .module)
        case .generateVideo(let o): o.modelPreset.title
        case .cleanup, .bestTakes, .brandKit, .addTitle, .brandTemplate, .filter, .background, .autoZoom,
             .trackFace, .transitions, .voiceEffect, .videoLayout, .aiEdit, .soundDesign:
            AppLocalization.string(String.LocalizationValue(stringLiteral: "assistant.step." + kind.typeName), bundle: .module)
        case .generateScript, .segmentScript, .record, .unsupported: kind.typeName
        }
    }
}
