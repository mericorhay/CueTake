import DesignSystem
import SwiftUI

/// Background work and short answers, at the top of the screen and out of the way.
///
/// The busy overlay stops everything, which is right while a project is being assembled and wrong
/// for listening to clips that are already on the timeline. This is the other register: a small
/// glass capsule that says what is happening, and a line that says how it went and then leaves.
struct StatusToasts: View {
    let activity: String?
    let notice: String?

    var body: some View {
        VStack(spacing: 8) {
            if let activity {
                HStack(spacing: 8) {
                    Image(systemName: "waveform")
                        .font(.system(size: 11, weight: .semibold))
                        .symbolEffect(.variableColor.iterative, options: .repeating)
                    Text(activity)
                        .dsFont(.sans, .medium, 12)
                }
                .foregroundStyle(DS.Palette.ink)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .dsGlass(tint: DS.Palette.glass(0.7), in: Capsule())
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            if let notice {
                Text(notice)
                    .dsFont(.sans, .semibold, 13, lineHeight: 1.35)
                    .foregroundStyle(DS.Palette.ink)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 11)
                    .frame(maxWidth: 340)
                    .dsGlass(
                        tint: DS.Palette.glassSheet(0.88),
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous),
                        border: DS.Palette.hairline(0.14)
                    )
                    .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
                    .transition(.scale(scale: 0.9, anchor: .top).combined(with: .opacity))
                    .id(notice)
            }
        }
        .padding(.top, 52)
        .padding(.horizontal, 20)
        .animation(DS.Motion.bloom, value: notice)
        .animation(DS.Motion.settle, value: activity)
        .allowsHitTesting(false)
    }
}
