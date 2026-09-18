import DesignSystem
import Domain
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
    /// Saved versions of the project. Nil where there is nowhere to keep them.
    let versionTools: VersionTools?
    let onClose: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var confirmingRevert = false
    /// An edit waiting for "yes" because taking it back also takes back later ones.
    @State private var pendingUndo: (entry: ChangeEntry, caught: [ChangeEntry])?
    @State private var showsVersions = false
    @State private var versionName = ""
    @State private var pendingRestore: ProjectVersion?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if versionTools != nil { tabs }
            if showsVersions, let versionTools {
                VersionList(
                    tools: versionTools,
                    name: $versionName,
                    onRestore: { pendingRestore = $0 }
                )
                .transition(.opacity)
            } else {
                controls
                saveRow
                list
            }
        }
        .background(DS.Palette.screen)
        .animation(DS.Motion.snap, value: showsVersions)
        .onAppear { versionTools?.refresh() }
        .confirmationDialog(
            String(localized: "editor.versions.restore.title \(pendingRestore?.name ?? "")", bundle: .module),
            isPresented: Binding(get: { pendingRestore != nil }, set: { if !$0 { pendingRestore = nil } }),
            titleVisibility: .visible
        ) {
            if let pending = pendingRestore {
                Button(String(localized: "editor.versions.restore.confirm", bundle: .module)) {
                    versionTools?.restore(pending)
                    pendingRestore = nil
                    onClose()
                }
            }
        } message: {
            Text("editor.versions.restore.message", bundle: .module)
        }
        .confirmationDialog(
            String(localized: "editor.changes.undoThis.also \(pendingUndo?.caught.count ?? 0)", bundle: .module),
            isPresented: Binding(get: { pendingUndo != nil }, set: { if !$0 { pendingUndo = nil } }),
            titleVisibility: .visible
        ) {
            if let pending = pendingUndo {
                Button(String(localized: "editor.changes.undoThis.confirm", bundle: .module), role: .destructive) {
                    withAnimation(DS.Motion.settle) { model.undoOnly(pending.entry.id) }
                    pendingUndo = nil
                }
            }
        } message: {
            Text(verbatim: pendingUndo?.caught.map(\.label).joined(separator: ", ") ?? "")
        }
        .animation(DS.Motion.snap, value: confirmingRevert)
        .animation(reduceMotion ? nil : DS.Motion.settle, value: model.changes.count)
    }

    private var header: some View {
        HStack {
            DSKicker(String(localized: "editor.changes.title", bundle: .module))
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
        .padding(.bottom, 14)
    }

    /// History of this session, or saved states of the whole project: two different questions
    /// ("what did I just do" and "what did it look like on Tuesday"), so two lists, not one.
    private var tabs: some View {
        HStack(spacing: 6) {
            tab("editor.changes.tab.edits", symbol: "list.bullet", isOn: !showsVersions) { showsVersions = false }
            tab("editor.changes.tab.versions", symbol: "clock.arrow.circlepath", isOn: showsVersions) { showsVersions = true }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }

    private func tab(_ key: String.LocalizationValue, symbol: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(String(localized: key, bundle: .module), systemImage: symbol)
                .dsFont(.sans, .semibold, 12)
                .foregroundStyle(isOn ? DS.Palette.inkInverse : DS.Palette.ink(0.7))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(Capsule().fill(isOn ? DS.Palette.lime : DS.Palette.hairline(0.07)))
        }
        .buttonStyle(.dsPress(radius: 20))
        .accessibilityAddTraits(isOn ? .isSelected : [])
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
                        .foregroundStyle(DS.Palette.ink(0.52))
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
                                .dsFont(.mono, .medium, 10)
                                .foregroundStyle(DS.Palette.ink(0.52))

                            // Any edit, not just the newest: the ones after it stay.
                            if model.canUndoOnly(change.id) {
                                Button {
                                    let caught = model.editsCaughtUp(inUndoing: change.id)
                                    if caught.isEmpty {
                                        withAnimation(DS.Motion.settle) { model.undoOnly(change.id) }
                                    } else {
                                        pendingUndo = (change, caught)
                                    }
                                } label: {
                                    Image(systemName: "arrow.uturn.backward")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundStyle(DS.Palette.ink(0.85))
                                        .frame(width: 34, height: 30)
                                        .background(Capsule().fill(DS.Palette.hairline(0.1)))
                                }
                                .buttonStyle(.dsPressIcon)
                                .accessibilityLabel(Text("editor.changes.undoThis", bundle: .module))
                            }
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
