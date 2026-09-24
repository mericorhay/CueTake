import DesignSystem
import Domain
import SwiftUI

/// When each look works, on the video's own timeline: one lane per tool that acts on a span of
/// time, its span drawn as a bar. The ends are dragged to set "from 19 s to 23 s", the middle to
/// move the span, and "Whole video" takes the span away again.
///
/// Kept when the finger lifts, like the rest of the preview: each change is a save.
struct StudioRangeLanes: View {
    @Bindable var model: WorkflowStudioModel
    /// The preview's playhead, in seconds of the video.
    let playhead: Double

    @State private var selected: WorkflowStep.ID?
    /// While a finger is on a lane: the span it is making.
    @State private var live: (id: WorkflowStep.ID, range: ClosedRange<Double>)?
    @State private var tick = 0
    /// The span as it was when the finger went down. The lanes redraw with the playhead several
    /// times a second, and a drag measured from the redrawn span would run away from the finger.
    @State private var origin: ClosedRange<Double>?

    private var total: Double { model.timelineSeconds }

    private var steps: [WorkflowStep] {
        model.definition.steps.filter { $0.isEnabled && $0.kind.acceptsTimeRange }
    }

    var body: some View {
        if !steps.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    DSKicker(AppLocalization.string("studio.range", bundle: .module), size: 10, color: DS.Palette.ink(0.56))
                    Spacer(minLength: 0)
                    Text(verbatim: Self.clock(total))
                        .dsFont(.mono, .medium, 10)
                        .foregroundStyle(DS.Palette.ink(0.4))
                }
                ForEach(steps) { step in
                    lane(step)
                }
                if let id = selected, let step = steps.first(where: { $0.id == id }) {
                    detail(step)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                } else {
                    Text("studio.range.hint", bundle: .module)
                        .dsFont(.sans, .regular, 12)
                        .foregroundStyle(DS.Palette.ink(0.45))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .sensoryFeedback(.selection, trigger: tick)
            .animation(DS.Motion.settle, value: selected)
        }
    }

    // MARK: - A lane

    private func lane(_ step: WorkflowStep) -> some View {
        let tool = StudioCatalog.tool(for: step.kind.typeName)
        let span = live?.id == step.id ? live!.range : displayed(step)
        let isSelected = selected == step.id
        return HStack(spacing: 8) {
            Image(systemName: tool.symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isSelected ? DS.Palette.lime : DS.Palette.ink(0.6))
                .frame(width: 22)
            GeometryReader { geometry in
                let width = geometry.size.width
                let x0 = width * CGFloat(span.lowerBound / total)
                let x1 = width * CGFloat(span.upperBound / total)
                ZStack(alignment: .leading) {
                    Capsule().fill(DS.Palette.hairline(0.07))
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isSelected ? DS.Palette.lime.opacity(0.85) : DS.Palette.ink(0.35))
                        .frame(width: max(8, x1 - x0))
                        .offset(x: x0)
                        .gesture(moveGesture(step, width: width, from: span))
                    if isSelected {
                        handle(at: x0)
                            .gesture(edgeGesture(step, width: width, from: span, leading: true))
                        handle(at: x1 - 14)
                            .gesture(edgeGesture(step, width: width, from: span, leading: false))
                    }
                    Rectangle()
                        .fill(Color.white.opacity(0.9))
                        .frame(width: 2)
                        .offset(x: width * CGFloat(min(1, max(0, playhead / total))) - 1)
                        .allowsHitTesting(false)
                }
            }
            .frame(height: 30)
            .contentShape(Rectangle())
            .onTapGesture { selected = isSelected ? nil : step.id }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(AppLocalization.string(tool.title, bundle: .module)))
        .accessibilityValue(Text(verbatim: Self.clock(span.lowerBound) + " – " + Self.clock(span.upperBound)))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { selected = step.id }
    }

    private func handle(at x: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(DS.Palette.ink)
            .frame(width: 14, height: 30)
            .overlay { Capsule().fill(DS.Palette.inkInverse).frame(width: 2, height: 12) }
            .offset(x: x)
    }

    // MARK: - The selected lane, in numbers

    private func detail(_ step: WorkflowStep) -> some View {
        let span = displayed(step)
        return HStack(spacing: 8) {
            stepper(step, span: span, leading: true)
            Text(verbatim: "–").foregroundStyle(DS.Palette.ink(0.4))
            stepper(step, span: span, leading: false)
            Spacer(minLength: 0)
            Button {
                model.setRange(nil, for: step.id)
            } label: {
                Text("studio.range.whole", bundle: .module)
                    .dsFont(.sans, .semibold, 12)
                    .foregroundStyle(step.range == nil ? DS.Palette.inkInverse : DS.Palette.ink(0.7))
                    .padding(.horizontal, 12)
                    .frame(minHeight: 34)
                    .background(Capsule().fill(step.range == nil ? DS.Palette.lime : DS.Palette.hairline(0.07)))
            }
            .buttonStyle(.dsPress(radius: 17))
        }
    }

    /// One end in seconds, with half-second steps either side.
    private func stepper(_ step: WorkflowStep, span: ClosedRange<Double>, leading: Bool) -> some View {
        let value = leading ? span.lowerBound : span.upperBound
        return HStack(spacing: 2) {
            Button { nudge(step, span: span, leading: leading, by: -0.5) } label: {
                Image(systemName: "minus").font(.system(size: 11, weight: .bold)).frame(width: 30, height: 34)
            }
            Text(verbatim: Self.clock(value))
                .dsFont(.mono, .semibold, 13)
                .monospacedDigit()
                .frame(minWidth: 50)
            Button { nudge(step, span: span, leading: leading, by: 0.5) } label: {
                Image(systemName: "plus").font(.system(size: 11, weight: .bold)).frame(width: 30, height: 34)
            }
        }
        .foregroundStyle(DS.Palette.ink)
        .background(Capsule().fill(DS.Palette.hairline(0.07)))
        .buttonStyle(.dsPress(radius: 17))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(LocalizedStringKey(leading ? "studio.range.from" : "studio.range.to"), bundle: .module))
        .accessibilityValue(Text(verbatim: Self.clock(value)))
        .accessibilityAdjustableAction { direction in
            nudge(step, span: span, leading: leading, by: direction == .increment ? 0.5 : -0.5)
        }
    }

    private func nudge(_ step: WorkflowStep, span: ClosedRange<Double>, leading: Bool, by delta: Double) {
        var lower = span.lowerBound
        var upper = span.upperBound
        if leading { lower = min(max(0, lower + delta), upper - 0.5) } else { upper = max(min(total, upper + delta), lower + 0.5) }
        commit(step, lower...upper)
    }

    // MARK: - Dragging

    private func edgeGesture(_ step: WorkflowStep, width: CGFloat, from span: ClosedRange<Double>, leading: Bool) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                let start = origin ?? span
                if origin == nil { origin = span }
                let delta = Double(value.translation.width / max(width, 1)) * total
                var lower = start.lowerBound
                var upper = start.upperBound
                if leading { lower = min(max(0, lower + delta), upper - 0.5) } else { upper = max(min(total, upper + delta), lower + 0.5) }
                update(step, Self.snapped(lower)...Self.snapped(upper))
            }
            .onEnded { _ in finish(step) }
    }

    private func moveGesture(_ step: WorkflowStep, width: CGFloat, from span: ClosedRange<Double>) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                selected = step.id
                let start = origin ?? span
                if origin == nil { origin = span }
                let length = start.upperBound - start.lowerBound
                let delta = Double(value.translation.width / max(width, 1)) * total
                let lower = min(max(0, start.lowerBound + delta), total - length)
                update(step, Self.snapped(lower)...Self.snapped(lower + length))
            }
            .onEnded { _ in finish(step) }
    }

    private func update(_ step: WorkflowStep, _ range: ClosedRange<Double>) {
        if let live, live.id == step.id, Int(live.range.lowerBound) != Int(range.lowerBound) || Int(live.range.upperBound) != Int(range.upperBound) {
            tick += 1
        }
        live = (step.id, range)
    }

    private func finish(_ step: WorkflowStep) {
        if let live, live.id == step.id { commit(step, live.range) }
        live = nil
        origin = nil
    }

    private func commit(_ step: WorkflowStep, _ range: ClosedRange<Double>) {
        // The whole video again is no span at all.
        if range.lowerBound <= 0.05, range.upperBound >= total - 0.05 {
            model.setRange(nil, for: step.id)
        } else {
            model.setRange(WorkflowTimeRange(start: range.lowerBound, end: range.upperBound), for: step.id)
        }
    }

    // MARK: - Where a step works

    /// The span a step works on: its own, or where the tool puts itself when it has none.
    private func displayed(_ step: WorkflowStep) -> ClosedRange<Double> {
        Self.span(of: step, total: total, sections: model.definition.sections)
    }

    static func span(of step: WorkflowStep, total: Double, sections: [WorkflowSection]) -> ClosedRange<Double> {
        if let range = step.range { return range.resolved(in: total) }
        let placed: (WorkflowMoment, Double, Double)? = switch step.kind {
        case .addTitle(let options): (options.moment, options.seconds, options.duration)
        case .brandTemplate(let options): (options.moment, options.seconds, options.duration)
        default: nil
        }
        guard let (moment, seconds, duration) = placed else { return 0...max(total, 0.5) }
        let length = min(max(duration, 0.5), total)
        let start: Double = switch moment {
        case .start: min(0.2, total - length)
        case .end: max(0, total - length - 0.2)
        case .at: min(max(0, seconds), total - length)
        case .cta: ctaStart(sections: sections, total: total).map { min($0 + 0.2, total - length) } ?? max(0, total - length - 0.2)
        }
        return max(0, start)...min(total, max(0, start) + length)
    }

    /// Where the CTA section begins, scaled from the outline to the video.
    private static func ctaStart(sections: [WorkflowSection], total: Double) -> Double? {
        let planned = sections.reduce(0) { $0 + max(0, $1.seconds) }
        guard planned > 0 else { return nil }
        var at = 0.0
        for section in sections {
            if section.role.lowercased() == "cta" { return at / planned * total }
            at += max(0, section.seconds)
        }
        return nil
    }

    static func snapped(_ seconds: Double) -> Double { (seconds * 10).rounded() / 10 }

    static func clock(_ seconds: Double) -> String {
        let tenths = Int((seconds * 10).rounded())
        let minutes = tenths / 600
        let rest = Double(tenths % 600) / 10
        return minutes > 0 ? String(format: "%d:%04.1f", minutes, rest) : String(format: "%.1fs", rest)
    }
}
