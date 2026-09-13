import DesignSystem
import SwiftUI

/// What you have done to this video, and how to take it back.
///
/// An editor that changes things silently is an editor people stop trusting, and the usual answer
/// — a single undo button — only tells you that *something* can be taken back, never what. This is
/// the list: newest first, each with the name of the edit and when it happened, so undo is a
/// decision rather than a gamble.
///
/// Snapshots make the whole thing possible (see `EditorHistory`), which is also why "revert
/// everything" is one step rather than sixty: the state the editor opened in is still sitting at
/// the bottom of the stack.
struct ChangesSheet: View {
    @Bindable var model: EditorModel

    /// What the app layer says about the file on disk: saved, saving, or never yet.
    let saveLabel: String
    let isSaving: Bool
    let onSave: () -> Void
    let onClose: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var confirmingRevert = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            controls
            saveRow
            list
        }
        .background(DS.Palette.screen)
        .animation(DS.Motion.snap, value: confirmingRevert)
        .animation(reduceMotion ? nil : DS.Motion.settle, value: model.changes.count)
    }

    private var header: some View {
        HStack {
            DSKicker(String(localized: "editor.changes.title", bundle: .module))
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
        .padding(.bottom, 14)
    }

    private var controls: some View {
        HStack(spacing: 8) {
            action("editor.changes.undo", symbol: "arrow.uturn.backward", enabled: model.canUndo) {
                model.undo()
            }

            action("editor.changes.redo", symbol: "arrow.uturn.forward", enabled: model.canRedo) {
                model.redo()
            }

            // Two taps, because this is the one control in the editor that can throw away an
            // afternoon. The second tap says what it will do rather than asking "are you sure",
            // which is a question nobody reads.
            action(
                confirmingRevert ? "editor.changes.revertConfirm" : "editor.changes.revert",
                symbol: "arrow.counterclockwise",
                enabled: model.canUndo,
                isDestructive: true
            ) {
                if confirmingRevert {
                    model.revertAll()
                    confirmingRevert = false
                } else {
                    confirmingRevert = true
                }
            }
        }
        .padding(.horizontal, 20)
    }

    /// The state of the file on disk, said plainly and always visible here.
    ///
    /// The app saves by itself, which is right — nobody should lose work to a missed button — but
    /// an app that never mentions saving leaves people wondering, and wondering is worse than a
    /// button. So: what it did, when, and a way to make it happen now.
    private var saveRow: some View {
        HStack(spacing: 10) {
            Image(systemName: isSaving ? "arrow.triangle.2.circlepath" : "checkmark.circle.fill")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isSaving ? DS.Palette.ink(0.5) : DS.Palette.lime)
                .symbolEffect(.rotate, options: .repeating, isActive: isSaving)

            Text(saveLabel)
                .dsFont(.sans, .regular, 12)
                .foregroundStyle(DS.Palette.ink(0.6))
                .contentTransition(.opacity)

            Spacer(minLength: 0)

            Button(action: onSave) {
                Text("editor.changes.saveNow", bundle: .module)
                    .dsFont(.sans, .semibold, 12)
                    .foregroundStyle(DS.Palette.ink(0.85))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(
                        Capsule().fill(DS.Palette.hairline(0.08))
                    )
            }
            .buttonStyle(.dsPress(radius: 20))
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 4)
    }

    private var list: some View {
        ScrollView {
            VStack(spacing: 6) {
                if model.changes.isEmpty {
                    Text("editor.changes.empty", bundle: .module)
                        .dsFont(.sans, .regular, 12)
                        .foregroundStyle(DS.Palette.ink(0.35))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 26)
                } else {
                    ForEach(Array(model.changes.enumerated()), id: \.element.id) { position, change in
                        HStack(spacing: 10) {
                            Image(systemName: change.symbol)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(position == 0 ? DS.Palette.lime : DS.Palette.ink(0.4))
                                .frame(width: 26, height: 26)
                                .background(
                                    Circle().fill(DS.Palette.hairline(position == 0 ? 0.1 : 0.05))
                                )

                            Text(change.label)
                                .dsFont(.sans, .medium, 13)
                                .foregroundStyle(position == 0 ? DS.Palette.ink : DS.Palette.ink(0.6))

                            Spacer(minLength: 0)

                            Text(change.at.formatted(date: .omitted, time: .standard))
                                .dsFont(.mono, .medium, 9)
                                .foregroundStyle(DS.Palette.ink(0.3))
                        }
                        .padding(.horizontal, 11)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .fill(DS.Palette.hairline(position == 0 ? 0.06 : 0.03))
                        )
                        // The newest edit arrives from above, the way it arrives in the timeline.
                        .transition(
                            reduceMotion
                                ? .opacity
                                : .asymmetric(
                                    insertion: .opacity.combined(with: .offset(y: -10)),
                                    removal: .opacity.combined(with: .scale(scale: 0.96))
                                )
                        )
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
    }

    private func action(
        _ key: String.LocalizationValue,
        symbol: String,
        enabled: Bool,
        isDestructive: Bool = false,
        run: @escaping () -> Void
    ) -> some View {
        Button(action: run) {
            VStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .medium))
                    .symbolEffect(.bounce, value: model.changes.count)
                Text(String(localized: key, bundle: .module))
                    .dsFont(.sans, .medium, 11)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(
                enabled
                    ? (isDestructive ? DS.Palette.accent : DS.Palette.ink(0.85))
                    : DS.Palette.ink(0.22)
            )
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(DS.Palette.hairline(enabled ? 0.07 : 0.03))
            )
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.dsPress(radius: 14))
        .disabled(!enabled)
    }
}
