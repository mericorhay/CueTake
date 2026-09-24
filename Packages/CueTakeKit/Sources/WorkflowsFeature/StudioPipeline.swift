import DesignSystem
import Domain
import SwiftUI

/// The automatic tools, in the order they run.
///
/// Drawn as a rail with cards hanging off it rather than as a list, because order *is* the
/// meaning here — trimming pauses before the transcript exists does nothing — and a rail makes
/// order the first thing you see. During a run the rail fills as each tool finishes.
struct StudioPipeline: View {
    @Bindable var model: WorkflowStudioModel
    let onShowPalette: () -> Void

    @State private var dropTarget: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                DSKicker(AppLocalization.string("studio.pipeline", bundle: .module), size: 10, color: DS.Palette.ink(0.56))
                Spacer(minLength: 0)
                Button(action: onShowPalette) {
                    Label(AppLocalization.string("studio.pipeline.add", bundle: .module), systemImage: "plus")
                        .dsFont(.sans, .semibold, 12)
                        .foregroundStyle(DS.Palette.lime)
                }
                .buttonStyle(.dsPress)
            }

            toolStrip

            VStack(spacing: 0) {
                ForEach(Array(model.definition.steps.enumerated()), id: \.element.id) { index, step in
                    if !model.isLocked(step.id) {
                        card(step, index: index)
                            .transition(
                                reduceMotion
                                    ? .opacity
                                    : .asymmetric(
                                        insertion: .move(edge: .leading).combined(with: .opacity),
                                        removal: .scale(scale: 0.9).combined(with: .opacity)
                                    )
                            )
                    }
                }

                endZone

                // Always last, always there: the run ends by writing the video.
                if let closing = model.definition.finalExport {
                    card(closing, index: model.definition.steps.count - 1)
                        .padding(.top, 10)
                }
            }
            .animation(reduceMotion ? nil : DS.Motion.settle, value: model.definition.steps.map(\.id))
        }
    }

    /// The tools, in a strip, to drag onto the rail. The palette sheet holds the same tools with
    /// descriptions; this is the fast path for someone who already knows them.
    private var toolStrip: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(StudioCatalog.addable) { tool in
                    let tint = StudioCatalog.tint(tool.category)
                    Button {
                        withAnimation(DS.Motion.settle) { model.addStep(type: tool.type) }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: tool.symbol)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(tint)
                            Text(AppLocalization.string(tool.title, bundle: .module))
                                .dsFont(.sans, .medium, 11)
                                .foregroundStyle(DS.Palette.ink(0.75))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(DS.Palette.hairline(0.06)))
                    }
                    .buttonStyle(.dsPress(radius: 20))
                    .draggable(StudioDrag.tool + tool.type) {
                        Label(AppLocalization.string(tool.title, bundle: .module), systemImage: tool.symbol)
                            .dsFont(.sans, .semibold, 12)
                            .foregroundStyle(DS.Palette.inkInverse)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Capsule().fill(tint))
                    }
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    // MARK: - A step

    private func card(_ step: WorkflowStep, index: Int) -> some View {
        let tool = StudioCatalog.tool(for: step.kind.typeName)
        let tint = StudioCatalog.tint(tool.category)
        let state = model.state(of: step.id)
        let isExpanded = model.expandedStep == step.id
        let isTarget = dropTarget == step.id.uuidString && !model.isLocked(step.id)
        let warning = model.warning(for: step)
        let locked = model.isLocked(step.id)

        return HStack(alignment: .top, spacing: 12) {
            rail(for: state, tint: tint, index: index, isLast: locked)

            VStack(alignment: .leading, spacing: 0) {
                // Where a dragged step or tool will land: a line that opens above the card.
                Capsule()
                    .fill(DS.Palette.lime)
                    .frame(height: isTarget ? 3 : 0)
                    .padding(.bottom, isTarget ? 8 : 0)
                    .opacity(isTarget ? 1 : 0)

                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        Image(systemName: tool.symbol)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(step.isEnabled ? tint : DS.Palette.ink(0.25))
                            .frame(width: 32, height: 32)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(tint.opacity(step.isEnabled ? 0.14 : 0.04))
                            )
                            .symbolEffect(.bounce, value: state == .done)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(AppLocalization.string(tool.title, bundle: .module))
                                .dsFont(.sans, .semibold, 14)
                                .foregroundStyle(step.isEnabled ? DS.Palette.ink : DS.Palette.ink(0.35))
                                .strikethrough(!step.isEnabled, color: DS.Palette.ink(0.52))

                            Text(model.stepNotes[step.id] ?? Self.subtitle(step, state: state, note: tool.note))
                                .dsFont(.sans, .regular, 11)
                                .foregroundStyle(Self.subtitleColor(state))
                                .lineLimit(isExpanded ? 3 : 1)
                                .contentTransition(.opacity)
                        }

                        Spacer(minLength: 0)

                        if locked {
                            // Not a switch: the closing export cannot be turned off or moved.
                            Image(systemName: "lock.fill")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(DS.Palette.ink(0.52))
                                .frame(width: 30, height: 30)
                                .accessibilityLabel(Text("studio.export.locked", bundle: .module))
                        } else {
                            Toggle("", isOn: Binding(
                                get: { step.isEnabled },
                                set: { _ in withAnimation(DS.Motion.snap) { model.toggleStep(step.id) } }
                            ))
                            .labelsHidden()
                            .tint(tint)
                        }
                    }

                    if step.when != nil || step.forEach != nil {
                        FlowLayout(horizontalSpacing: 5, verticalSpacing: 5) {
                            if let condition = step.when {
                                automationBadge(
                                    "arrow.triangle.branch",
                                    text: "\(condition.variable) · \(condition.operation.rawValue)"
                                )
                            }
                            if let loop = step.forEach {
                                automationBadge("repeat", text: "\(loop.source) → \(loop.itemVariable)")
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }

                    if let warning, step.isEnabled {
                        Label(AppLocalization.string(warning, bundle: .module), systemImage: "exclamationmark.triangle.fill")
                            .dsFont(.sans, .regular, 11)
                            .foregroundStyle(DS.Palette.accentWarm)
                            .transition(.opacity)
                    }

                    if let board = model.generation, board.stepID == step.id {
                        GenerationBoardView(board: board)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    if isExpanded {
                        StudioStepEditor(model: model, step: step)
                            .transition(.opacity.combined(with: .move(edge: .top)))

                        if locked {
                            Label(AppLocalization.string("studio.export.lockedNote", bundle: .module), systemImage: "lock")
                                .dsFont(.sans, .regular, 10)
                                .foregroundStyle(DS.Palette.ink(0.56))
                        } else {
                            HStack(spacing: 6) {
                                moveButton("arrow.up", step: step, by: -1)
                                moveButton("arrow.down", step: step, by: 1)
                                Spacer(minLength: 0)
                                Button(role: .destructive) {
                                    withAnimation(DS.Motion.settle) { model.removeStep(step.id) }
                                } label: {
                                    Label(AppLocalization.string("studio.delete", bundle: .module), systemImage: "trash")
                                        .dsFont(.sans, .medium, 12)
                                        .foregroundStyle(DS.Palette.accent)
                                        .padding(.horizontal, 12)
                                        .frame(height: 36)
                                        .background(Capsule().fill(DS.Palette.accent(0.1)))
                                }
                                .buttonStyle(.dsPress(radius: 18))
                            }
                        }
                    }
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(state == .running ? tint.opacity(0.1) : DS.Palette.hairline(isExpanded ? 0.07 : 0.045))
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(
                            state == .running ? tint : DS.Palette.hairline(isExpanded ? 0.14 : 0.07),
                            lineWidth: state == .running ? 1.5 : 1
                        )
                }
                .modifier(PulseWhileRunning(isRunning: state == .running))
                .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .onTapGesture {
                    withAnimation(DS.Motion.settle) {
                        model.expandedStep = isExpanded ? nil : step.id
                    }
                }
                .modifier(StepDrag(enabled: !locked, payload: StudioDrag.step + step.id.uuidString, title: AppLocalization.string(tool.title, bundle: .module), symbol: tool.symbol, tint: tint))
                .padding(.bottom, 10)
            }
            .animation(DS.Motion.snap, value: isTarget)
        }
        .dropDestination(for: String.self) { items, _ in
            drop(items, before: step.id)
        } isTargeted: { targeted in
            dropTarget = targeted ? step.id.uuidString : (dropTarget == step.id.uuidString ? nil : dropTarget)
        }
    }

    private func automationBadge(_ symbol: String, text: String) -> some View {
        Label(text, systemImage: symbol)
            .dsFont(.mono, .medium, 9, letterSpacing: 0.04)
            .foregroundStyle(DS.Palette.ink(0.58))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Capsule().fill(DS.Palette.hairline(0.08)))
    }

    private func moveButton(_ symbol: String, step: WorkflowStep, by offset: Int) -> some View {
        let enabled = model.canMoveStep(step.id, by: offset)
        return Button {
            withAnimation(DS.Motion.settle) { model.moveStep(step.id, by: offset) }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(DS.Palette.ink(enabled ? 0.75 : 0.2))
                .frame(width: 36, height: 36)
                .background(Circle().fill(DS.Palette.hairline(0.08)))
        }
        .buttonStyle(.dsPressIcon)
        .disabled(!enabled)
        .accessibilityLabel(Text(offset < 0 ? "studio.step.up" : "studio.step.down", bundle: .module))
    }

    /// The rail: a node per step, and the line to the next one, filled once the step is done.
    private func rail(for state: StudioStepState?, tint: Color, index: Int, isLast: Bool) -> some View {
        VStack(spacing: 0) {
            ZStack {
                Circle()
                    .fill(Self.nodeFill(state, tint: tint))
                    .frame(width: 22, height: 22)

                switch state {
                case .done:
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .black))
                        .foregroundStyle(DS.Palette.inkInverse)
                        .transition(.symbolEffect(.drawOn))
                case .skipped:
                    Image(systemName: "arrow.turn.down.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(DS.Palette.ink(0.6))
                        .transition(.scale.combined(with: .opacity))
                case .running:
                    RunningArc(reduceMotion: reduceMotion)
                        .transition(.opacity)
                default:
                    Text(verbatim: "\(index + 1)")
                        .dsFont(.mono, .medium, 10)
                        .foregroundStyle(DS.Palette.ink(0.5))
                }
            }
            .animation(DS.Motion.bloom, value: state)
            .padding(.top, 17)

            ZStack(alignment: .top) {
                Rectangle().fill(DS.Palette.hairline(0.12))
                Rectangle()
                    .fill(tint)
                    .scaleEffect(x: 1, y: state == .done ? 1 : 0, anchor: .top)
            }
            .frame(width: 2)
            .frame(maxHeight: .infinity)
            .opacity(isLast ? 0 : 1)
            .animation(reduceMotion ? .easeOut(duration: 0.2) : .easeInOut(duration: 0.55), value: state)
        }
        .frame(width: 22)
    }

    private var endZone: some View {
        let isTarget = dropTarget == "end"

        return HStack(spacing: 12) {
            Circle()
                .stroke(DS.Palette.hairline(0.25), style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                .frame(width: 22, height: 22)

            Button(action: onShowPalette) {
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .semibold))
                    Text(
                        model.definition.steps.isEmpty
                            ? AppLocalization.string("studio.pipeline.empty", bundle: .module)
                            : AppLocalization.string("studio.pipeline.drop", bundle: .module)
                    )
                    .dsFont(.sans, .medium, 12)
                }
                .foregroundStyle(DS.Palette.ink(isTarget ? 0.9 : 0.45))
                .frame(maxWidth: .infinity, minHeight: 50)
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(
                            isTarget ? DS.Palette.lime : DS.Palette.hairline(0.18),
                            style: StrokeStyle(lineWidth: 1.2, dash: [5, 4])
                        )
                }
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(DS.Palette.lime.opacity(isTarget ? 0.08 : 0))
                )
            }
            .buttonStyle(.dsPress(radius: 16))
        }
        .animation(DS.Motion.snap, value: isTarget)
        .dropDestination(for: String.self) { items, _ in
            drop(items, before: nil)
        } isTargeted: { targeted in
            dropTarget = targeted ? "end" : (dropTarget == "end" ? nil : dropTarget)
        }
    }

    private func drop(_ items: [String], before target: WorkflowStep.ID?) -> Bool {
        guard let item = items.first else { return false }
        withAnimation(reduceMotion ? .easeOut(duration: 0.15) : DS.Motion.settle) {
            if item.hasPrefix(StudioDrag.step), let id = UUID(uuidString: String(item.dropFirst(StudioDrag.step.count))) {
                model.moveStep(id, before: target)
            } else if item.hasPrefix(StudioDrag.tool) {
                model.addStep(type: String(item.dropFirst(StudioDrag.tool.count)), before: target)
            }
        }
        dropTarget = nil
        return true
    }

    // MARK: - Looks

    static func subtitle(_ step: WorkflowStep, state: StudioStepState?, note: String.LocalizationValue) -> String {
        switch state {
        case .running: return AppLocalization.string("studio.step.running", bundle: .module)
        case .skipped(let reason): return reason
        default:
            var summary = StudioCatalog.summary(of: step.kind)
            if summary.isEmpty { summary = AppLocalization.string(note, bundle: .module) }
            // Its span, when it was given one on the preview's timeline.
            if let range = step.range, step.kind.acceptsTimeRange {
                let end = range.end.map(StudioRangeLanes.clock) ?? AppLocalization.string("studio.range.end", bundle: .module)
                return StudioRangeLanes.clock(range.start) + "–" + end + " · " + summary
            }
            return summary
        }
    }

    static func subtitleColor(_ state: StudioStepState?) -> Color {
        switch state {
        case .running: DS.Palette.lime
        case .skipped: DS.Palette.accentWarm
        default: DS.Palette.ink(0.4)
        }
    }

    static func nodeFill(_ state: StudioStepState?, tint: Color) -> Color {
        switch state {
        case .done, .running: tint
        case .skipped: DS.Palette.hairline(0.15)
        default: DS.Palette.hairline(0.08)
        }
    }
}

/// A quarter-open ring turning around the running step's node.
private struct RunningArc: View {
    let reduceMotion: Bool
    @State private var turning = false

    var body: some View {
        Circle()
            .trim(from: 0, to: 0.72)
            .stroke(DS.Palette.inkInverse, style: StrokeStyle(lineWidth: 2, lineCap: .round))
            .frame(width: 12, height: 12)
            .rotationEffect(.degrees(turning ? 360 : 0))
            .animation(reduceMotion ? nil : .linear(duration: 0.9).repeatForever(autoreverses: false), value: turning)
            .onAppear { turning = true }
    }
}

/// Steps are dragged to reorder them; the closing export is not.
private struct StepDrag: ViewModifier {
    let enabled: Bool
    let payload: String
    let title: String
    let symbol: String
    let tint: Color

    @ViewBuilder
    func body(content: Content) -> some View {
        if enabled {
            content.draggable(payload) {
                Label(title, systemImage: symbol)
                    .dsFont(.sans, .semibold, 13)
                    .foregroundStyle(DS.Palette.inkInverse)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(tint))
            }
        } else {
            content
        }
    }
}

private struct PulseWhileRunning: ViewModifier {
    let isRunning: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isRunning {
            content.dsPulse(duration: 1)
        } else {
            content
        }
    }
}

// MARK: - Palette

/// Every tool, grouped and explained. Tapping one adds it to the end of the pipeline.
struct StudioToolPalette: View {
    @Bindable var model: WorkflowStudioModel
    let onClose: () -> Void

    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                DSKicker(AppLocalization.string("studio.palette", bundle: .module))
                Spacer(minLength: 0)
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .dsActionName("xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(DS.Palette.ink(0.6))
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(DS.Palette.hairline(0.08)))
                }
                .buttonStyle(.dsPressIcon)
            }
            .padding(.horizontal, 20)
            .padding(.top, 22)
            .padding(.bottom, 12)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(Array(WorkflowToolCategory.allCases.enumerated()), id: \.element) { order, category in
                        let tools = StudioCatalog.addable.filter { $0.category == category }
                        if !tools.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(AppLocalization.string(StudioCatalog.categoryTitle(category), bundle: .module))
                                    .dsFont(.archivo, .bold, 15)
                                    .foregroundStyle(DS.Palette.ink)

                                ForEach(tools) { tool in
                                    toolRow(tool)
                                }
                            }
                            .opacity(shown ? 1 : 0)
                            .offset(y: shown ? 0 : 12)
                            .animation(reduceMotion ? nil : DS.Motion.settle.delay(Double(order) * 0.05), value: shown)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
        }
        .background(DS.Palette.screen)
        .onAppear { shown = true }
    }

    private func toolRow(_ tool: StudioCatalog.Tool) -> some View {
        let tint = StudioCatalog.tint(tool.category)
        let count = model.definition.steps.filter { $0.kind.typeName == tool.type }.count

        return Button {
            withAnimation(DS.Motion.settle) { model.addStep(type: tool.type) }
            onClose()
        } label: {
            HStack(spacing: 11) {
                Image(systemName: tool.symbol)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(tint)
                    .frame(width: 34, height: 34)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(tint.opacity(0.14)))

                VStack(alignment: .leading, spacing: 2) {
                    Text(AppLocalization.string(tool.title, bundle: .module))
                        .dsFont(.sans, .semibold, 14)
                        .foregroundStyle(DS.Palette.ink)
                    Text(AppLocalization.string(tool.note, bundle: .module))
                        .dsFont(.sans, .regular, 11)
                        .foregroundStyle(DS.Palette.ink(0.56))
                        .lineLimit(2)
                }

                Spacer(minLength: 0)

                if count > 0 {
                    Text(verbatim: "×\(count)")
                        .dsFont(.mono, .medium, 10)
                        .foregroundStyle(DS.Palette.ink(0.56))
                }
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(DS.Palette.hairline(0.045)))
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.dsPress(radius: 14))
    }
}
