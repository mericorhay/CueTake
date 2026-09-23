import DesignSystem
import Domain
import SwiftUI

/// "Clean up": everything the take could lose, shown in the words themselves before anything is
/// cut.
///
/// Each thing offered is struck through in the text where it was said, and a tap on it keeps or
/// cuts it. The kinds can be switched as a whole, the pause length is a slider, and the button says
/// how much shorter the clip will be. Nothing changes until the button is pressed.
struct CleanupPanel: View {
    @Bindable var model: EditorModel
    let index: Int
    let onDone: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pause = 0.6
    @State private var chosen: Set<CleanupItem.ID>?
    @State private var result: String?
    @State private var plan: CleanupPlan?
    /// Changes whenever the clip's own words or cuts do, so the plan is worked out again.
    private var planInput: String {
        let take = model.project.segments.indices.contains(index) ? model.project.segments[index].selectedTake : nil
        return [
            take?.id.uuidString ?? "",
            String(take?.sourceRange.duration.seconds ?? 0),
            String(pause),
        ].joined(separator: "|")
    }

    private var words: [TimedWord] { model.spokenWords(at: index) }

    var body: some View {
        Group {
            if let plan {
                content(plan, chosen: chosen ?? plan.defaultSelection)
            } else {
                Text("editor.cleanup.nothing", bundle: .module)
                    .dsFont(.sans, .regular, 13, lineHeight: 1.45)
                    .foregroundStyle(DS.Palette.ink(0.5))
                    .padding(.horizontal, 20)
            }
        }
        .task(id: planInput) {
            plan = model.cleanupPlan(at: index, options: CleanupOptions(pause: pause))
        }
    }

    private func content(_ plan: CleanupPlan, chosen: Set<CleanupItem.ID>) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            summary(plan, chosen: chosen)
            kinds(plan, chosen: chosen)
            pauseSlider
            ScrollView {
                marked(plan, chosen: chosen)
                    .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            buttons(plan, chosen: chosen)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
        .onChange(of: pause) { _, _ in self.chosen = nil }
        .onChange(of: plan) { _, _ in self.chosen = nil }
    }

    // MARK: - Summary

    private func summary(_ plan: CleanupPlan, chosen: Set<CleanupItem.ID>) -> some View {
        let saved = plan.saved(chosen)
        let cuts = plan.cuts(chosen).count
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: plan.alignment == nil ? "waveform" : "text.badge.checkmark")
                    .font(.system(size: 11, weight: .semibold))
                if plan.alignment != nil {
                    Text(AppLocalization.string("editor.cleanup.scripted \(Int(((plan.alignment?.accuracy ?? 0) * 100).rounded()))", bundle: .module))
                } else {
                    Text("editor.cleanup.unscripted", bundle: .module)
                }
            }
            .dsFont(.sans, .medium, 11)
            .foregroundStyle(plan.alignment == nil ? DS.Palette.ink(0.45) : DS.Palette.lime)

            Text(AppLocalization.string("editor.cleanup.summary \(cuts) \(Self.seconds(saved))", bundle: .module))
                .dsFont(.sans, .semibold, 15)
                .foregroundStyle(DS.Palette.ink)
                .contentTransition(.numericText())

            if let result {
                Text(result)
                    .dsFont(.sans, .regular, 11)
                    .foregroundStyle(DS.Palette.ink(0.5))
            }
        }
    }

    // MARK: - Kinds

    private func kinds(_ plan: CleanupPlan, chosen: Set<CleanupItem.ID>) -> some View {
        FlowLayout(horizontalSpacing: 6, verticalSpacing: 6) {
            ForEach(CleanupItem.Kind.allCases, id: \.self) { kind in
                let items = plan.items.filter { $0.kind == kind }
                if !items.isEmpty {
                    let on = items.filter { chosen.contains($0.id) }.count
                    Button {
                        var next = chosen
                        if on == items.count {
                            items.forEach { next.remove($0.id) }
                        } else {
                            items.forEach { next.insert($0.id) }
                        }
                        self.chosen = next
                    } label: {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Self.tint(kind))
                                .frame(width: 7, height: 7)
                            Text(Self.label(kind))
                                .dsFont(.sans, .medium, 12)
                            Text(verbatim: "\(on)/\(items.count)")
                                .dsFont(.mono, .medium, 10)
                                .foregroundStyle(DS.Palette.ink(0.56))
                        }
                        .foregroundStyle(on > 0 ? DS.Palette.ink : DS.Palette.ink(0.45))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(
                            Capsule().fill(DS.Palette.hairline(on > 0 ? 0.1 : 0.04))
                        )
                        .overlay {
                            Capsule().stroke(on > 0 ? Self.tint(kind).opacity(0.5) : .clear, lineWidth: 1)
                        }
                    }
                    .buttonStyle(.dsPress(radius: 14))
                }
            }
        }
    }

    private var pauseSlider: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("editor.cleanup.pauseLength", bundle: .module)
                    .dsFont(.sans, .medium, 11)
                    .foregroundStyle(DS.Palette.ink(0.5))
                Spacer(minLength: 0)
                Text(verbatim: Self.seconds(pause))
                    .dsFont(.mono, .medium, 11)
                    .foregroundStyle(DS.Palette.ink(0.7))
            }
            Slider(value: $pause, in: 0.3...1.5, step: 0.1)
                .tint(Self.tint(.pause))
        }
    }

    // MARK: - Words

    /// The take as text, with what would go struck through and what stays plain.
    private func marked(_ plan: CleanupPlan, chosen: Set<CleanupItem.ID>) -> some View {
        let byWord = Self.itemsByWord(plan)
        let pausesAfter = Self.pausesAfterWord(plan, words: words)
        return FlowLayout(horizontalSpacing: 4, verticalSpacing: 6) {
            ForEach(Array(words.enumerated()), id: \.offset) { position, word in
                let item = byWord[position]
                let cut = item.map { chosen.contains($0.id) } ?? false
                Button {
                    if let item {
                        toggle(item.id, in: chosen)
                    } else {
                        model.seek(to: model.start(at: index) + word.range.start.seconds)
                    }
                } label: {
                    Text(word.text)
                        .dsFont(.sans, .regular, 15, lineHeight: 1.3)
                        .strikethrough(cut, color: item.map { Self.tint($0.kind) } ?? .clear)
                        .foregroundStyle(cut ? DS.Palette.ink(0.35) : DS.Palette.ink(0.88))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(item.map { Self.tint($0.kind).opacity(cut ? 0.18 : 0.07) } ?? .clear)
                        )
                }
                .buttonStyle(.dsPress(radius: 6))

                ForEach(pausesAfter[position] ?? []) { gap in
                    let cutGap = chosen.contains(gap.id)
                    Button {
                        toggle(gap.id, in: chosen)
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: gap.kind == .pause ? "pause.fill" : "waveform")
                                .font(.system(size: 7, weight: .bold))
                            Text(verbatim: Self.seconds(gap.duration))
                                .dsFont(.mono, .medium, 10)
                        }
                        .foregroundStyle(cutGap ? DS.Palette.inkInverse : DS.Palette.ink(0.5))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .background(
                            Capsule().fill(cutGap ? Self.tint(gap.kind) : DS.Palette.hairline(0.08))
                        )
                    }
                    .buttonStyle(.dsPress(radius: 10))
                }
            }
        }
    }

    private func toggle(_ id: CleanupItem.ID, in current: Set<CleanupItem.ID>) {
        var next = current
        if next.contains(id) {
            next.remove(id)
        } else {
            next.insert(id)
        }
        chosen = next
    }

    // MARK: - Buttons

    private func buttons(_ plan: CleanupPlan, chosen: Set<CleanupItem.ID>) -> some View {
        let canApply = plan.saved(chosen) > 0.05 && !plan.kept(chosen).isEmpty
        let kinds = Set(plan.items.filter { chosen.contains($0.id) }.map(\.kind))
        return VStack(spacing: 8) {
            Button {
                model.pulse(.split)
                withAnimation(reduceMotion ? .easeOut(duration: 0.15) : DS.Motion.settle) {
                    model.applyCleanup(plan, chosen: chosen)
                }
                onDone()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 13, weight: .semibold))
                    Text("editor.cleanup.apply", bundle: .module)
                        .dsFont(.sans, .semibold, 14)
                }
                .foregroundStyle(canApply ? DS.Palette.inkInverse : DS.Palette.ink(0.3))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(canApply ? DS.Palette.accent : DS.Palette.hairline(0.06))
                )
            }
            .buttonStyle(.dsPress(radius: 16))
            .disabled(!canApply)

            if model.project.segments.count > 1, !kinds.isEmpty {
                Button {
                    model.pulse(.split)
                    let done = withAnimation(reduceMotion ? .easeOut(duration: 0.15) : DS.Motion.settle) {
                        model.cleanUpAllClips(kinds: kinds, options: CleanupOptions(pause: pause))
                    }
                    result = AppLocalization.string("editor.cleanup.allDone \(done.clips) \(Self.seconds(done.seconds))", bundle: .module)
                    self.chosen = nil
                } label: {
                    Text("editor.cleanup.applyAll", bundle: .module)
                        .dsFont(.sans, .medium, 13)
                        .foregroundStyle(DS.Palette.ink(0.8))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(DS.Palette.hairline(0.07))
                        )
                }
                .buttonStyle(.dsPress(radius: 14))
            }
        }
    }

    // MARK: - Helpers

    static func itemsByWord(_ plan: CleanupPlan) -> [Int: CleanupItem] {
        var result: [Int: CleanupItem] = [:]
        for item in plan.items {
            guard let words = item.words else { continue }
            for word in words { result[word] = item }
        }
        return result
    }

    /// Each pause or wordless sound, placed after the word it follows. One before the first word
    /// shows after it.
    static func pausesAfterWord(_ plan: CleanupPlan, words: [TimedWord]) -> [Int: [CleanupItem]] {
        var result: [Int: [CleanupItem]] = [:]
        for item in plan.items where item.words == nil {
            let before = words.lastIndex { $0.range.end.seconds <= item.start + 0.2 } ?? 0
            result[before, default: []].append(item)
        }
        return result
    }

    static func seconds(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1))) + " s"
    }

    static func label(_ kind: CleanupItem.Kind) -> String {
        switch kind {
        case .pause: AppLocalization.string("editor.cleanup.kind.pause", bundle: .module)
        case .filler: AppLocalization.string("editor.cleanup.kind.filler", bundle: .module)
        case .repeated: AppLocalization.string("editor.cleanup.kind.repeated", bundle: .module)
        case .restart: AppLocalization.string("editor.cleanup.kind.restart", bundle: .module)
        case .offScript: AppLocalization.string("editor.cleanup.kind.offScript", bundle: .module)
        }
    }

    static func tint(_ kind: CleanupItem.Kind) -> Color {
        switch kind {
        case .pause: DS.Palette.lime
        case .filler: DS.Palette.accent
        case .repeated: DS.Palette.accentWarm
        case .restart: Color(hex: 0x6FB7FF)
        case .offScript: DS.Palette.ink(0.6)
        }
    }
}

/// Shown above the words of a clip a cleanup made: what was taken out, and the way back.
struct CleanupBanner: View {
    @Bindable var model: EditorModel
    let index: Int

    var body: some View {
        if let group = model.cleanupGroup(at: index) {
            HStack(spacing: 10) {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DS.Palette.lime)
                Text(AppLocalization.string("editor.cleanup.cleaned \(CleanupPanel.seconds(group.removed))", bundle: .module))
                    .dsFont(.sans, .medium, 12)
                    .foregroundStyle(DS.Palette.ink(0.8))
                Spacer(minLength: 0)
                Button {
                    model.pulse(.split)
                    model.restoreCleanup(at: index)
                } label: {
                    Text("editor.cleanup.restore", bundle: .module)
                        .dsFont(.sans, .semibold, 12)
                        .foregroundStyle(DS.Palette.ink)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(DS.Palette.hairline(0.1)))
                }
                .buttonStyle(.dsPress(radius: 12))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(DS.Palette.lime(0.06))
            )
            .padding(.horizontal, 20)
            .padding(.bottom, 10)
        }
    }
}
