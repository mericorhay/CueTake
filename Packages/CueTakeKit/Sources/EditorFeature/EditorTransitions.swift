import DesignSystem
import Domain
import SwiftUI

// MARK: - Model

extension EditorModel {
    /// Opens the cut after a clip for its transition.
    public func select(transition after: Segment.ID?) {
        if after != nil {
            selectedCameraMotion = nil
            selectedSubjectTrack = nil
            clearOtherSelections()
        }
        selectedTransition = after
    }

    /// The cuts, as the clip each one leaves and where it is on the video. The last clip has none.
    public var cuts: [(after: Segment.ID, index: Int, time: Double)] {
        var result: [(after: Segment.ID, index: Int, time: Double)] = []
        var time = 0.0
        for (index, segment) in project.segments.enumerated() {
            time += segment.barWeight
            if index < project.segments.count - 1 {
                result.append((segment.id, index, time))
            }
        }
        return result
    }

    /// The cut nearest the playhead, for the dock's transition tool.
    public var cutNearPlayhead: Segment.ID? {
        cuts.min { abs($0.time - playhead) < abs($1.time - playhead) }?.after
    }

    /// The longest transition the clips either side of a cut allow.
    public func longestTransition(after id: Segment.ID) -> Double {
        guard let index = project.segments.firstIndex(where: { $0.id == id }),
              project.segments.indices.contains(index + 1)
        else { return ClipTransition.durationRange.upperBound }
        let usable = ClipTransition.usableDuration(
            ClipTransition.durationRange.upperBound,
            outgoing: project.segments[index].barWeight,
            incoming: project.segments[index + 1].barWeight
        )
        return max(ClipTransition.durationRange.lowerBound, usable)
    }

    public func setTransition(after id: Segment.ID, kind: ClipTransition.Kind, duration: Double? = nil, coalescing: String? = nil) {
        guard project.segments.dropLast().contains(where: { $0.id == id }) else { return }
        record("editor.change.transition", symbol: "square.on.square.intersection.dashed", coalescing: coalescing)
        let wanted = duration.map { min($0, longestTransition(after: id)) }
        project.setTransition(after: id, kind: kind, duration: wanted)
        project.updatedAt = .now
    }

    public func removeTransition(after id: Segment.ID) {
        guard project.transition(after: id) != nil else { return }
        record("editor.change.transitionRemove", symbol: "scissors")
        project.setTransition(after: id, kind: nil)
        project.updatedAt = .now
    }

    /// The same transition on every cut. Each is fitted to its own clips.
    public func applyTransitionEverywhere(_ kind: ClipTransition.Kind, duration: Double) {
        guard project.segments.count > 1 else { return }
        record("editor.change.transitionAll", symbol: "square.on.square.intersection.dashed")
        for cut in cuts {
            project.setTransition(after: cut.after, kind: kind, duration: min(duration, longestTransition(after: cut.after)))
        }
        project.updatedAt = .now
    }

    public func removeAllTransitions() {
        guard !project.transitions.isEmpty else { return }
        record("editor.change.transitionRemove", symbol: "scissors")
        project.transitions.removeAll()
        project.updatedAt = .now
    }

    /// Plays the cut with a second either side, so the transition can be judged.
    public func previewTransition(after id: Segment.ID) {
        guard let cut = cuts.first(where: { $0.after == id }) else { return }
        let half = (project.transition(after: id)?.duration ?? 0.5) / 2
        seek(to: max(0, cut.time - half - 0.8))
        if !isPlaying { togglePlayback() }
    }
}

// MARK: - Timeline

/// The cuts on the clip row: a diamond on each, filled when the cut has a transition, with the
/// transition's length drawn across the cut.
struct TransitionMarks: View {
    @Bindable var model: EditorModel
    let scale: Double
    var onSelect: (Segment.ID) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(model.cuts, id: \.after) { cut in
                let transition = model.project.transition(after: cut.after)
                let selected = model.selectedTransition == cut.after
                let x = CGFloat(cut.time * scale)
                if let transition {
                    let width = CGFloat(min(transition.duration, model.longestTransition(after: cut.after)) * scale)
                    Capsule()
                        .fill(DS.Palette.lime.opacity(selected ? 0.55 : 0.32))
                        .frame(width: max(width, 8), height: 8)
                        .offset(x: x - max(width, 8) / 2, y: 60)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
                Button {
                    onSelect(cut.after)
                } label: {
                    Image(systemName: transition.map { Self.symbol($0.kind) } ?? "plus")
                        .font(.system(size: transition == nil ? 8 : 9, weight: .bold))
                        .foregroundStyle(transition == nil ? DS.Palette.ink(0.7) : DS.Palette.inkInverse)
                        .frame(width: 20, height: 20)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(transition == nil ? DS.Palette.screen : DS.Palette.lime)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(selected ? DS.Palette.ink : DS.Palette.hairline(0.3), lineWidth: selected ? 2 : 1)
                        }
                        .rotationEffect(.degrees(transition == nil ? 45 : 0))
                        .scaleEffect(selected && !reduceMotion ? 1.18 : 1)
                        .contentTransition(.symbolEffect(.replace))
                        // A bigger target than the mark: it sits on the edge of two clips.
                        .frame(width: 34, height: 40)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.dsPressIcon)
                .offset(x: x - 17, y: 12)
                .accessibilityLabel(Text("editor.transition.at \(cut.index + 1)", bundle: .module))
                .animation(DS.Motion.snap, value: selected)
                .animation(DS.Motion.snap, value: transition?.kind)
            }
        }
        .frame(height: 64, alignment: .topLeading)
    }

    static func symbol(_ kind: ClipTransition.Kind) -> String {
        switch kind {
        case .crossfade: "circle.lefthalf.filled"
        case .fadeBlack: "moon.fill"
        case .fadeWhite: "sun.max.fill"
        case .slideLeft: "arrow.left.square.fill"
        case .slideRight: "arrow.right.square.fill"
        case .slideUp: "arrow.up.square.fill"
        case .slideDown: "arrow.down.square.fill"
        case .pushLeft: "arrow.left.to.line"
        case .pushRight: "arrow.right.to.line"
        case .wipeLeft: "rectangle.lefthalf.inset.filled.arrow.left"
        case .wipeRight: "rectangle.righthalf.inset.filled.arrow.right"
        case .wipeUp: "rectangle.tophalf.inset.filled"
        case .wipeDown: "rectangle.bottomhalf.inset.filled"
        case .zoomIn: "plus.magnifyingglass"
        case .zoomOut: "minus.magnifyingglass"
        }
    }

    static func title(_ kind: ClipTransition.Kind) -> LocalizedStringKey {
        switch kind {
        case .crossfade: "editor.transition.crossfade"
        case .fadeBlack: "editor.transition.fadeBlack"
        case .fadeWhite: "editor.transition.fadeWhite"
        case .slideLeft: "editor.transition.slideLeft"
        case .slideRight: "editor.transition.slideRight"
        case .slideUp: "editor.transition.slideUp"
        case .slideDown: "editor.transition.slideDown"
        case .pushLeft: "editor.transition.pushLeft"
        case .pushRight: "editor.transition.pushRight"
        case .wipeLeft: "editor.transition.wipeLeft"
        case .wipeRight: "editor.transition.wipeRight"
        case .wipeUp: "editor.transition.wipeUp"
        case .wipeDown: "editor.transition.wipeDown"
        case .zoomIn: "editor.transition.zoomIn"
        case .zoomOut: "editor.transition.zoomOut"
        }
    }

    static func titleKey(_ kind: ClipTransition.Kind) -> String.LocalizationValue {
        String.LocalizationValue(stringLiteral: "editor.transition." + kind.rawValue)
    }

    static func familyTitle(_ family: ClipTransition.Kind.Family) -> LocalizedStringKey {
        switch family {
        case .blend: "editor.transition.family.blend"
        case .slide: "editor.transition.family.slide"
        case .wipe: "editor.transition.family.wipe"
        case .zoom: "editor.transition.family.zoom"
        }
    }
}

// MARK: - Panel

/// The open cut's transition: every effect as a small moving picture, the length, and ways to
/// use it everywhere or take it away.
struct TransitionPanel: View {
    @Bindable var model: EditorModel
    let cut: Segment.ID
    let onClose: () -> Void

    @State private var family: ClipTransition.Kind.Family = .blend
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var current: ClipTransition? { model.project.transition(after: cut) }
    private var cutIndex: Int { model.cuts.first { $0.after == cut }?.index ?? 0 }
    private var longest: Double { model.longestTransition(after: cut) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            CameraPanelHeader(
                title: Text("editor.transition.title \(cutIndex + 1) \(cutIndex + 2)", bundle: .module),
                symbol: current.map { TransitionMarks.symbol($0.kind) } ?? "square.on.square.intersection.dashed",
                tint: DS.Palette.lime,
                range: model.cuts.first { $0.after == cut }.map { cut in
                    let half = (current?.duration ?? 0) / 2
                    return (cut.time - half)...(cut.time + half)
                },
                onClose: onClose
            )

            familyPicker

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 8)], spacing: 8) {
                noneTile
                ForEach(ClipTransition.Kind.allCases.filter { $0.family == family }, id: \.self) { kind in
                    tile(kind)
                        .transition(.scale(scale: 0.85).combined(with: .opacity))
                }
            }
            .animation(reduceMotion ? nil : DS.Motion.settle, value: family)

            if let current {
                durationRow(current)
                    .transition(.opacity.combined(with: .move(edge: .top)))

                HStack(spacing: 8) {
                    Button {
                        model.previewTransition(after: cut)
                    } label: {
                        Label(String(localized: "editor.transition.preview", bundle: .module), systemImage: "play.fill")
                            .dsFont(.sans, .semibold, 12)
                            .foregroundStyle(DS.Palette.inkInverse)
                            .frame(maxWidth: .infinity)
                            .frame(height: 40)
                            .background(Capsule().fill(DS.Palette.ink))
                    }
                    .buttonStyle(.dsPress(radius: 20))

                    Button {
                        withAnimation(DS.Motion.settle) {
                            model.applyTransitionEverywhere(current.kind, duration: current.duration)
                        }
                    } label: {
                        Label(String(localized: "editor.transition.all", bundle: .module), systemImage: "square.stack.3d.forward.dottedline")
                            .dsFont(.sans, .semibold, 12)
                            .foregroundStyle(DS.Palette.ink)
                            .frame(maxWidth: .infinity)
                            .frame(height: 40)
                            .background(Capsule().fill(DS.Palette.hairline(0.1)))
                    }
                    .buttonStyle(.dsPress(radius: 20))
                    .disabled(model.cuts.count < 2)
                }

                CameraPanelDelete(title: Text("editor.transition.remove", bundle: .module)) {
                    withAnimation(DS.Motion.settle) { model.removeTransition(after: cut) }
                }
            } else {
                Text("editor.transition.hint", bundle: .module)
                    .dsFont(.sans, .regular, 11, lineHeight: 1.35)
                    .foregroundStyle(DS.Palette.ink(0.55))
            }

            if model.project.transitions.count > 1 {
                Button {
                    withAnimation(DS.Motion.settle) { model.removeAllTransitions() }
                } label: {
                    Text("editor.transition.removeAll \(model.project.transitions.count)", bundle: .module)
                        .dsFont(.sans, .medium, 11)
                        .foregroundStyle(DS.Palette.ink(0.5))
                        .frame(maxWidth: .infinity)
                        .frame(height: 32)
                }
                .buttonStyle(.dsPress(radius: 16))
            }
        }
        .cameraPanelSurface()
        .onAppear {
            if let current { family = current.kind.family }
        }
        .onChange(of: cut) {
            if let current { family = current.kind.family }
        }
        .sensoryFeedback(.selection, trigger: current?.kind)
    }

    private var familyPicker: some View {
        HStack(spacing: 6) {
            ForEach(ClipTransition.Kind.Family.allCases, id: \.self) { item in
                let active = family == item
                Button {
                    withAnimation(DS.Motion.snap) { family = item }
                } label: {
                    Text(TransitionMarks.familyTitle(item), bundle: .module)
                        .dsFont(.sans, .semibold, 11)
                        .foregroundStyle(active ? DS.Palette.inkInverse : DS.Palette.ink(0.65))
                        .frame(maxWidth: .infinity)
                        .frame(height: 32)
                        .background {
                            if active {
                                Capsule().fill(DS.Palette.ink)
                            } else {
                                Capsule().fill(DS.Palette.hairline(0.06))
                            }
                        }
                }
                .buttonStyle(.dsPress(radius: 16))
                .accessibilityAddTraits(active ? .isSelected : [])
            }
        }
    }

    private var noneTile: some View {
        let active = current == nil
        return Button {
            withAnimation(DS.Motion.settle) { model.removeTransition(after: cut) }
        } label: {
            VStack(spacing: 5) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(DS.Palette.hairline(0.08))
                    Image(systemName: "scissors")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(DS.Palette.ink(0.6))
                }
                .frame(height: 50)
                Text("editor.transition.none", bundle: .module)
                    .dsFont(.sans, .semibold, 10)
                    .lineLimit(1)
                    .foregroundStyle(DS.Palette.ink(0.7))
            }
            .padding(5)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(active ? DS.Palette.lime(0.18) : .clear))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(active ? DS.Palette.lime : DS.Palette.hairline(0.1), lineWidth: active ? 2 : 1)
            }
        }
        .buttonStyle(.dsPress(radius: 12))
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    private func tile(_ kind: ClipTransition.Kind) -> some View {
        let active = current?.kind == kind
        return Button {
            withAnimation(DS.Motion.settle) {
                model.setTransition(after: cut, kind: kind)
            }
        } label: {
            VStack(spacing: 5) {
                TransitionThumbnail(kind: kind, animating: !reduceMotion)
                    .frame(height: 50)
                Text(TransitionMarks.title(kind), bundle: .module)
                    .dsFont(.sans, .semibold, 10)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .foregroundStyle(DS.Palette.ink(active ? 1 : 0.7))
            }
            .padding(5)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(active ? DS.Palette.lime(0.18) : .clear))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(active ? DS.Palette.lime : DS.Palette.hairline(0.1), lineWidth: active ? 2 : 1)
            }
        }
        .buttonStyle(.dsPress(radius: 12))
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    private func durationRow(_ transition: ClipTransition) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("editor.transition.duration", bundle: .module)
                    .dsFont(.sans, .medium, 11)
                    .foregroundStyle(DS.Palette.ink(0.55))
                Spacer(minLength: 0)
                Text(verbatim: String(format: "%.2f s", transition.duration))
                    .dsFont(.mono, .semibold, 11)
                    .foregroundStyle(DS.Palette.ink)
                    .contentTransition(.numericText(value: transition.duration))
            }
            HStack(spacing: 10) {
                Image(systemName: "hare")
                    .font(.system(size: 11))
                    .foregroundStyle(DS.Palette.ink(0.45))
                Slider(
                    value: Binding(
                        get: { min(transition.duration, longest) },
                        set: { value in
                            model.setTransition(after: cut, kind: transition.kind, duration: (value * 20).rounded() / 20, coalescing: "transition-\(cut)")
                        }
                    ),
                    in: ClipTransition.durationRange.lowerBound...max(longest, ClipTransition.durationRange.lowerBound + 0.05)
                )
                .tint(DS.Palette.lime)
                Image(systemName: "tortoise")
                    .font(.system(size: 11))
                    .foregroundStyle(DS.Palette.ink(0.45))
            }
            if longest < ClipTransition.durationRange.upperBound - 0.01 {
                Text("editor.transition.limited \(String(format: "%.1f", longest))", bundle: .module)
                    .dsFont(.sans, .regular, 10)
                    .foregroundStyle(DS.Palette.ink(0.4))
            }
        }
    }
}

/// Two coloured frames performing the transition, over and over, drawn from the same numbers the
/// video uses.
struct TransitionThumbnail: View {
    let kind: ClipTransition.Kind
    let animating: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !animating)) { context in
            let cycle = 2.0
            let t = animating ? context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: cycle) / cycle : 0.5
            // Hold each end a moment, so the eye sees where it started and ended.
            let progress = TransitionLook.eased(min(max((t - 0.2) / 0.6, 0), 1))
            let look = TransitionLook.at(progress, kind: kind)
            Canvas { context, size in
                let bounds = CGRect(origin: .zero, size: size)
                context.fill(Path(roundedRect: bounds, cornerRadius: 9), with: .color(look.whiteBackground ? .white : .black))
                context.clip(to: Path(roundedRect: bounds, cornerRadius: 9))
                let layers: [(TransitionLook.Layer, Color, String)] = [
                    (look.outgoing, DS.Palette.accent, "A"),
                    (look.incoming, DS.Palette.lime, "B"),
                ]
                let ordered = look.incomingOnTop ? layers : Array(layers.reversed())
                for (layer, color, letter) in ordered {
                    var drawing = context
                    drawing.opacity = layer.opacity
                    if let visible = layer.visible {
                        drawing.clip(to: Path(CGRect(
                            x: visible.x * size.width,
                            y: visible.y * size.height,
                            width: max(0, visible.width) * size.width,
                            height: max(0, visible.height) * size.height
                        )))
                    }
                    let width = size.width * layer.scale
                    let height = size.height * layer.scale
                    let rect = CGRect(
                        x: (size.width - width) / 2 + layer.dx * size.width,
                        y: (size.height - height) / 2 + layer.dy * size.height,
                        width: width,
                        height: height
                    )
                    drawing.fill(Path(rect), with: .color(color))
                    drawing.draw(
                        Text(verbatim: letter).font(.system(size: 16 * layer.scale, weight: .black)).foregroundStyle(.black.opacity(0.55)),
                        at: CGPoint(x: rect.midX, y: rect.midY)
                    )
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// Said over the preview when it plays without its transitions, with the system's reason.
struct TransitionProblemNote: View {
    let problem: String
    var onClose: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DS.Palette.accent)
            VStack(alignment: .leading, spacing: 3) {
                Text("editor.transition.previewFailed", bundle: .module)
                    .dsFont(.sans, .semibold, 12)
                    .foregroundStyle(DS.Palette.ink)
                Text(verbatim: problem)
                    .dsFont(.mono, .medium, 9)
                    .foregroundStyle(DS.Palette.ink(0.55))
                    .lineLimit(3)
                    .textSelection(.enabled)
            }
            Spacer(minLength: 0)
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(DS.Palette.ink(0.7))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.dsPressIcon)
            .accessibilityLabel(Text("editor.panel.close", bundle: .module))
        }
        .padding(.leading, 12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
        )
    }
}
