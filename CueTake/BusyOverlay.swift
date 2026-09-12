import DesignSystem
import SwiftUI

/// Shown while the app is doing something long enough to look broken otherwise.
///
/// Importing thirty clips and transcribing them takes real time. The failure mode is not that it
/// is slow — it is that nothing on screen changes, so the user taps again, or leaves. The message
/// says which of the two long things is happening, because "loading" answers nothing.
///
/// Deliberately blocking. What is underneath is a project mid-assembly, and letting someone edit a
/// timeline that is still growing is worse than making them wait for it.
struct BusyOverlay: View {
    let message: String

    var body: some View {
        ZStack {
            DS.Palette.inkInverse(0.72)

            VStack(spacing: 16) {
                ProgressView()
                    .controlSize(.large)
                    .tint(DS.Palette.accent)

                Text(message)
                    .dsFont(.sans, .medium, 14)
                    .foregroundStyle(DS.Palette.ink(0.85))
                    .multilineTextAlignment(.center)
                    .contentTransition(.opacity)
            }
            .padding(28)
            .dsGlass(
                tint: DS.Palette.glassSheet(0.9),
                in: RoundedRectangle(cornerRadius: DS.Radius.sheet, style: .continuous),
                border: DS.Palette.hairline(0.12)
            )
            .padding(.horizontal, 48)
        }
        .ignoresSafeArea()
        .transition(.opacity)
    }
}
