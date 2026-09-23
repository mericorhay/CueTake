import DesignSystem
import Domain
import SwiftUI

/// "Clip deleted · Undo", for four seconds after a clip goes.
///
/// Deleting is one tap, so taking it back is one tap too, right where the eye already is. The
/// note also says when texts or sounds that lay only over the clip went with it.
struct DeletionNote: View {
    let deletion: ClipDeletion
    let onUndo: () -> Void
    let onDismiss: () -> Void

    @State private var remaining = 1.0

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "trash.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(DS.Palette.accent)
                .symbolEffect(.bounce, value: deletion.id)
            VStack(alignment: .leading, spacing: 1) {
                Text("editor.delete.done \(deletion.title)", bundle: .module)
                    .dsFont(.sans, .semibold, 13)
                    .foregroundStyle(DS.Palette.ink)
                    .lineLimit(1)
                if deletion.alsoRemoved > 0 {
                    Text("editor.delete.alsoRemoved \(deletion.alsoRemoved)", bundle: .module)
                        .dsFont(.sans, .regular, 10)
                        .foregroundStyle(DS.Palette.ink(0.55))
                }
            }
            Spacer(minLength: 0)
            Button(action: onUndo) {
                Label(AppLocalization.string("editor.delete.undo", bundle: .module), systemImage: "arrow.uturn.backward")
                    .dsFont(.sans, .semibold, 13)
                    .foregroundStyle(DS.Palette.inkInverse)
                    .padding(.horizontal, 14)
                    .frame(height: 38)
                    .background(Capsule().fill(DS.Palette.ink))
            }
            .buttonStyle(.dsPress(radius: 19))
        }
        .padding(.leading, 16)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .background {
            Capsule().fill(DS.Palette.glassSheet(0.96))
                .overlay(alignment: .bottomLeading) {
                    // How long the note stays.
                    GeometryReader { box in
                        Capsule()
                            .fill(DS.Palette.accent.opacity(0.5))
                            .frame(width: box.size.width * remaining, height: 2)
                            .frame(maxHeight: .infinity, alignment: .bottom)
                    }
                    .padding(.horizontal, 18)
                }
        }
        .overlay(Capsule().stroke(DS.Palette.hairline(0.12), lineWidth: 1))
        .shadow(color: .black.opacity(0.3), radius: 18, y: 8)
        .padding(.horizontal, 16)
        .task(id: deletion.id) {
            withAnimation(.linear(duration: 4)) { remaining = 0 }
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            onDismiss()
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: deletion.id)
    }
}
