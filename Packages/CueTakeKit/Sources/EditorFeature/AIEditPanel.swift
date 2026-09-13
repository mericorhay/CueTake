import DesignSystem
import Domain
import SwiftUI

/// Asks a model to edit the video, shows what it wants to do, and does it only when told.
///
/// Three beats, never skipped: say what you want, read the plan, apply. A model that edits the
/// timeline without showing its work first is a model nobody trusts with a second request — and a
/// plan laid out as "clip 2: cut 1.2–1.8 s" is also how people learn what the tools can do.
struct AIEditPanel: View {
    @Bindable var model: EditorModel
    let request: (EditDocument, String) async throws -> EditPlan

    enum Phase: Equatable {
        case asking
        case thinking
        case review(EditPlan)
        case done(EditPlanOutcome)
        case failed(String)
    }

    @State private var instruction = ""
    @State private var phase: Phase = .asking
    @FocusState private var focused: Bool

    private var suggestions: [String] {
        [
            String(localized: "editor.ai.suggest.tighten", bundle: .module),
            String(localized: "editor.ai.suggest.energy", bundle: .module),
            String(localized: "editor.ai.suggest.captions", bundle: .module),
            String(localized: "editor.ai.suggest.hook", bundle: .module),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch phase {
            case .asking: asking
            case .thinking: thinking
            case .review(let plan): review(plan)
            case .done(let outcome): done(outcome)
            case .failed(let message): failed(message)
            }
        }
        .animation(DS.Motion.settle, value: phase)
    }

    // MARK: - Asking

    private var asking: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                TextField(String(localized: "editor.ai.placeholder", bundle: .module), text: $instruction, axis: .vertical)
                    .lineLimit(1...3)
                    .dsFont(.sans, .regular, 14)
                    .foregroundStyle(DS.Palette.ink)
                    .tint(DS.Palette.accent)
                    .focused($focused)
                    .submitLabel(.send)
                    .onSubmit(send)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(DS.Palette.hairline(0.07)))

                Button(action: send) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(DS.Palette.inkInverse)
                        .frame(width: 42, height: 42)
                        .background(Circle().fill(DS.Palette.accent))
                        .symbolEffect(.bounce, value: instruction.isEmpty)
                }
                .buttonStyle(.dsPressIcon)
                .disabled(instruction.trimmingCharacters(in: .whitespaces).isEmpty)
                .opacity(instruction.trimmingCharacters(in: .whitespaces).isEmpty ? 0.45 : 1)
            }

            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(suggestions, id: \.self) { suggestion in
                        Button {
                            instruction = suggestion
                            send()
                        } label: {
                            Text(suggestion)
                                .dsFont(.sans, .medium, 11)
                                .foregroundStyle(DS.Palette.lime)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(Capsule().fill(DS.Palette.lime(0.1)))
                                .overlay(Capsule().stroke(DS.Palette.lime(0.25), lineWidth: 1))
                        }
                        .buttonStyle(.dsPress(radius: 20))
                    }
                }
            }
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
        }
        .transition(.opacity)
    }

    // MARK: - Thinking

    private var thinking: some View {
        let document = model.document()
        let words = document.clips.reduce(0) { $0 + $1.words.count }
        return HStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(DS.Palette.accent)
                .symbolEffect(.variableColor.iterative, options: .repeating)
            VStack(alignment: .leading, spacing: 3) {
                Text("editor.ai.thinking", bundle: .module)
                    .dsFont(.sans, .semibold, 14)
                    .foregroundStyle(DS.Palette.ink)
                Text("editor.ai.reading \(document.clips.count) \(words) \(document.beats.count)", bundle: .module)
                    .dsFont(.mono, .medium, 10)
                    .foregroundStyle(DS.Palette.ink(0.45))
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .transition(.opacity.combined(with: .scale(scale: 0.97)))
    }

    // MARK: - Review

    private func review(_ plan: EditPlan) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if !plan.summary.isEmpty {
                Text(plan.summary)
                    .dsFont(.sans, .medium, 13, lineHeight: 1.4)
                    .foregroundStyle(DS.Palette.ink(0.85))
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(plan.operations.enumerated()), id: \.offset) { position, operation in
                        HStack(spacing: 9) {
                            Image(systemName: symbol(for: operation))
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(isKnown(operation) ? DS.Palette.accent : DS.Palette.ink(0.3))
                                .frame(width: 22, height: 22)
                                .background(Circle().fill(DS.Palette.hairline(0.07)))
                            Text(describe(operation))
                                .dsFont(.sans, .regular, 12)
                                .foregroundStyle(isKnown(operation) ? DS.Palette.ink(0.8) : DS.Palette.ink(0.35))
                                .lineLimit(2)
                            Spacer(minLength: 0)
                        }
                        .dsEnter(.rise(duration: 0.35, delay: Double(position) * 0.04))
                    }
                }
            }
            .frame(maxHeight: 150)

            HStack(spacing: 8) {
                DSSecondaryButton(String(localized: "editor.ai.discard", bundle: .module), verticalPadding: 12, fontSize: 13) {
                    phase = .asking
                }
                DSPrimaryButton(
                    String(localized: "editor.ai.apply \(plan.operations.filter(isKnown).count)", bundle: .module),
                    verticalPadding: 12,
                    fontSize: 13,
                    glow: false
                ) {
                    model.pulse(.split)
                    let outcome = withAnimation(DS.Motion.settle) { model.apply(plan) }
                    phase = .done(outcome)
                }
                .disabled(plan.operations.filter(isKnown).isEmpty)
            }
        }
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    private func done(_ outcome: EditPlanOutcome) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 20))
                .foregroundStyle(DS.Palette.lime)
                .symbolEffect(.bounce, value: outcome.applied)
            VStack(alignment: .leading, spacing: 2) {
                Text("editor.ai.applied \(outcome.applied)", bundle: .module)
                    .dsFont(.sans, .semibold, 14)
                    .foregroundStyle(DS.Palette.ink)
                if !outcome.skipped.isEmpty {
                    Text("editor.ai.skipped \(outcome.skipped.count)", bundle: .module)
                        .dsFont(.sans, .regular, 11)
                        .foregroundStyle(DS.Palette.ink(0.45))
                }
            }
            Spacer(minLength: 0)
            Button {
                withAnimation(DS.Motion.settle) { model.undo() }
                phase = .asking
            } label: {
                Text("editor.ai.undo", bundle: .module)
                    .dsFont(.sans, .semibold, 12)
                    .foregroundStyle(DS.Palette.ink)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(DS.Palette.hairline(0.1)))
            }
            .buttonStyle(.dsPress(radius: 20))
            Button {
                instruction = ""
                phase = .asking
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(DS.Palette.ink)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(DS.Palette.hairline(0.1)))
            }
            .buttonStyle(.dsPressIcon)
        }
        .transition(.scale(scale: 0.95).combined(with: .opacity))
    }

    private func failed(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(message)
                .dsFont(.sans, .regular, 13, lineHeight: 1.4)
                .foregroundStyle(DS.Palette.accent)
            DSSecondaryButton(String(localized: "editor.ai.retry", bundle: .module), verticalPadding: 11, fontSize: 13) {
                send()
            }
        }
        .transition(.opacity)
    }

    // MARK: - Work

    private func send() {
        let text = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        focused = false
        phase = .thinking
        let document = model.document()
        Task {
            do {
                let plan = try await request(document, text)
                phase = plan.operations.isEmpty
                    ? .failed(plan.summary.isEmpty ? String(localized: "editor.ai.nothing", bundle: .module) : plan.summary)
                    : .review(plan)
            } catch {
                phase = .failed(String(localized: "editor.ai.failed \(error.localizedDescription)", bundle: .module))
            }
        }
    }

    private func isKnown(_ operation: EditPlan.Operation) -> Bool {
        if case .unknown = operation { return false }
        return true
    }

    private func clipNumber(_ id: String) -> String {
        guard let index = model.project.segments.firstIndex(where: { $0.id.uuidString == id }) else { return "?" }
        return "\(index + 1)"
    }

    private func symbol(for operation: EditPlan.Operation) -> String {
        switch operation {
        case .cut, .removeWords: "scissors"
        case .trimPauses: "waveform.badge.minus"
        case .setSpeed: "gauge.with.dots.needle.67percent"
        case .reverse: "backward.fill"
        case .freeze: "snowflake"
        case .deleteClip: "trash"
        case .reorder: "arrow.left.arrow.right"
        case .setCaptionText, .captionStyle: "captions.bubble"
        case .voiceCleanup: "waveform.and.person.filled"
        case .setMusicLevel: "music.note"
        case .unknown: "questionmark"
        }
    }

    private func describe(_ operation: EditPlan.Operation) -> String {
        switch operation {
        case .cut(let clip, let from, let to):
            String(localized: "editor.ai.op.cut \(clipNumber(clip)) \(String(format: "%.1f", from)) \(String(format: "%.1f", to))", bundle: .module)
        case .removeWords(let clip, let words):
            String(localized: "editor.ai.op.words \(clipNumber(clip)) \(words.count)", bundle: .module)
        case .trimPauses(let clip, let minPause):
            String(localized: "editor.ai.op.pauses \(clip.map(clipNumber) ?? "*") \(String(format: "%.1f", minPause))", bundle: .module)
        case .setSpeed(let clip, let speed):
            String(localized: "editor.ai.op.speed \(clipNumber(clip)) \(String(format: "%.2g", speed))", bundle: .module)
        case .reverse(let clip, _):
            String(localized: "editor.ai.op.reverse \(clipNumber(clip))", bundle: .module)
        case .freeze(let clip, _):
            String(localized: "editor.ai.op.freeze \(clipNumber(clip))", bundle: .module)
        case .deleteClip(let clip):
            String(localized: "editor.ai.op.delete \(clipNumber(clip))", bundle: .module)
        case .reorder:
            String(localized: "editor.ai.op.reorder", bundle: .module)
        case .setCaptionText(_, let text):
            String(localized: "editor.ai.op.caption \(text)", bundle: .module)
        case .captionStyle(let preset, _):
            String(localized: "editor.ai.op.style \(preset)", bundle: .module)
        case .voiceCleanup(let on):
            on ? String(localized: "editor.ai.op.voiceOn", bundle: .module) : String(localized: "editor.ai.op.voiceOff", bundle: .module)
        case .setMusicLevel(_, let gain):
            String(localized: "editor.ai.op.music \(String(format: "%.0f", gain))", bundle: .module)
        case .unknown(let type):
            String(localized: "editor.ai.op.unknown \(type)", bundle: .module)
        }
    }
}

extension EditPlanOutcome: Hashable {}
