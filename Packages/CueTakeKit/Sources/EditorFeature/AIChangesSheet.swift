import DesignSystem
import Domain
import SwiftUI

/// Every change the AI made in this session, grouped by what it was asked, each one reversible.
///
/// Taking one back puts only the things it touched back as they were — a caption the AI fixed, a
/// clip it cut — and leaves the rest of the edit, including what you did afterwards, alone. A change
/// taken back can be put back the same way. Tapping one closes the sheet, goes to where it happened
/// and lights it up in the studio.
struct AIChangesSheet: View {
    @Bindable var model: EditorModel
    let onClose: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if model.aiChanges.isEmpty {
                empty
            } else {
                ScrollView {
                    LazyVStack(spacing: 14) {
                        ForEach(Array(model.aiChanges.enumerated()), id: \.element.id) { position, set in
                            card(set)
                                .dsEnter(.rise(duration: 0.4, delay: Double(min(position, 6)) * 0.05))
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 30)
                }
                .scrollIndicators(.hidden)
            }
        }
        .background(DS.Palette.screen)
    }

    private var header: some View {
        HStack(spacing: 9) {
            AIOrb(fast: false, size: 26)
            VStack(alignment: .leading, spacing: 2) {
                DSKicker(String(localized: "editor.aiChanges.title", bundle: .module))
                Text("editor.aiChanges.hint", bundle: .module)
                    .dsFont(.sans, .regular, 11)
                    .foregroundStyle(DS.Palette.ink(0.45))
            }
            Spacer(minLength: 0)
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(DS.Palette.ink(0.6))
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(DS.Palette.hairline(0.08)))
            }
            .buttonStyle(.dsPressIcon)
        }
        .padding(.horizontal, 20)
        .padding(.top, 22)
        .padding(.bottom, 16)
    }

    private var empty: some View {
        VStack(spacing: 12) {
            AISparkle(size: 26)
            Text("editor.aiChanges.empty", bundle: .module)
                .dsFont(.sans, .regular, 13, lineHeight: 1.4)
                .foregroundStyle(DS.Palette.ink(0.55))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 40)
    }

    private func card(_ set: AIChangeSet) -> some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                AISparkle(size: 11)
                Text(verbatim: set.instruction.isEmpty ? set.summary : "“\(set.instruction)”")
                    .dsFont(.sans, .semibold, 14, lineHeight: 1.3)
                    .foregroundStyle(DS.Palette.ink(set.isFullyReverted ? 0.45 : 1))
                    .lineLimit(2)
                Spacer(minLength: 0)
                Text(set.date, format: .dateTime.hour().minute())
                    .dsFont(.mono, .medium, 10)
                    .foregroundStyle(DS.Palette.ink(0.4))
            }

            if !set.instruction.isEmpty, !set.summary.isEmpty {
                Text(set.summary)
                    .dsFont(.sans, .regular, 12, lineHeight: 1.35)
                    .foregroundStyle(DS.Palette.ink(0.55))
                    .lineLimit(3)
            }

            VStack(spacing: 4) {
                ForEach(set.items) { item in
                    row(item, in: set)
                }
            }

            HStack {
                Text("editor.aiChanges.count \(set.activeCount)", bundle: .module)
                    .dsFont(.mono, .medium, 10)
                    .foregroundStyle(DS.Palette.ink(0.45))
                    .contentTransition(.numericText())
                Spacer(minLength: 0)
                Button {
                    withAnimation(reduceMotion ? .easeOut(duration: 0.2) : DS.Motion.settle) {
                        if set.isFullyReverted {
                            model.reapplyAIChangeSet(set.id)
                        } else {
                            model.revertAIChangeSet(set.id)
                        }
                    }
                } label: {
                    Label {
                        Text(LocalizedStringKey(set.isFullyReverted ? "editor.aiChanges.reapplyAll" : "editor.aiChanges.revertAll"), bundle: .module)
                    } icon: {
                        Image(systemName: set.isFullyReverted ? "arrow.uturn.forward" : "arrow.uturn.backward")
                    }
                    .dsFont(.sans, .semibold, 12)
                    .foregroundStyle(set.isFullyReverted ? DS.Palette.inkInverse : DS.Palette.ink)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background {
                        if set.isFullyReverted {
                            Capsule().fill(AIPalette.blue)
                        } else {
                            Capsule().fill(DS.Palette.hairline(0.1))
                        }
                    }
                    .contentTransition(.interpolate)
                }
                .buttonStyle(.dsPress(radius: 20))
                .disabled(model.isAIDriving)
            }
        }
        .padding(14)
        .background(shape.fill(DS.Palette.surfaceRaised))
        .overlay {
            shape.strokeBorder(DS.Palette.hairline(set.isFullyReverted ? 0.05 : 0.1), lineWidth: 1)
        }
        .animation(DS.Motion.settle, value: set.items.map(\.reverted))
    }

    private func row(_ item: AIChangeItem, in set: AIChangeSet) -> some View {
        HStack(spacing: 10) {
            Image(systemName: item.symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(item.reverted ? DS.Palette.ink(0.3) : AIPalette.blue)
                .frame(width: 26, height: 26)
                .background(Circle().fill(DS.Palette.hairline(item.reverted ? 0.03 : 0.07)))

            VStack(alignment: .leading, spacing: 1) {
                Text(item.text)
                    .dsFont(.sans, .regular, 12)
                    .foregroundStyle(DS.Palette.ink(item.reverted ? 0.35 : 0.85))
                    .strikethrough(item.reverted, color: DS.Palette.ink(0.35))
                    .lineLimit(2)
                if item.reverted {
                    Text("editor.aiChanges.reverted", bundle: .module)
                        .dsFont(.sans, .medium, 10)
                        .foregroundStyle(DS.Palette.ink(0.35))
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }

            Spacer(minLength: 0)

            if let time = item.time {
                Text(MediaTime(seconds: time).preciseTimecode)
                    .dsFont(.mono, .medium, 10)
                    .foregroundStyle(DS.Palette.ink(0.5))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(DS.Palette.hairline(0.07)))
            }

            Button {
                withAnimation(reduceMotion ? .easeOut(duration: 0.2) : DS.Motion.settle) {
                    if item.reverted {
                        model.reapplyAIChange(item.id, in: set.id)
                    } else {
                        model.revertAIChange(item.id, in: set.id)
                    }
                }
            } label: {
                Image(systemName: item.reverted ? "arrow.uturn.forward" : "arrow.uturn.backward")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(DS.Palette.ink(0.85))
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(DS.Palette.hairline(0.09)))
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.dsPressIcon)
            .disabled(model.isAIDriving)
            .accessibilityLabel(Text(LocalizedStringKey(item.reverted ? "editor.aiChanges.reapply" : "editor.aiChanges.revert"), bundle: .module))
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .onTapGesture {
            guard !item.reverted else { return }
            onClose()
            Task {
                try? await Task.sleep(for: .milliseconds(380))
                model.showAIChange(item)
            }
        }
    }
}
