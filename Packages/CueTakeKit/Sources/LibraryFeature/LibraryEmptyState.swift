import DesignSystem
import SwiftUI

/// What the library says when it has nothing to show.
///
/// Not an illustration and not an apology. An empty library is the most common first screen there
/// is, and the only useful thing it can do is name the one action worth taking — so it says what
/// goes here and offers the way in, rather than leaving a blank strip that reads as a bug.
struct LibraryEmptyState: View {
    let message: String
    /// Nil where there is nothing sensible to offer, as on a screen the user reached deliberately.
    let action: String?
    let onTap: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(message)
                .dsFont(.sans, .regular, 14, lineHeight: 1.45)
                .foregroundStyle(DS.Palette.ink(0.56))
                .frame(maxWidth: 280, alignment: .leading)

            if let action, let onTap {
                Button(action: onTap) {
                    Text(action)
                        .dsFont(.sans, .semibold, 13)
                        .foregroundStyle(DS.Palette.accent)
                        .padding(.horizontal, 15)
                        .padding(.vertical, 10)
                        .background(
                            Capsule().fill(DS.Palette.accent(0.12))
                        )
                        .overlay(Capsule().stroke(DS.Palette.accent(0.35), lineWidth: 1))
                }
                .buttonStyle(.dsPress)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 18)
    }
}
