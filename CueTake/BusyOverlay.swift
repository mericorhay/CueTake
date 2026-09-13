import DesignSystem
import SwiftUI

/// Shown while the app is doing something long enough to look broken otherwise.
///
/// Two lines, doing different jobs. The big one changes every second and is there to make the wait
/// feel like something is happening — a fixed string stops being read after three seconds, and the
/// eye starts treating it as furniture. The small one underneath is the actual status, and it is
/// the one that tells the truth: which clip, out of how many.
///
/// Deliberately blocking. What is underneath is a project mid-assembly, and letting someone edit a
/// timeline that is still growing is worse than making them wait for it.
struct BusyOverlay: View {
    let status: String

    @State private var line = Int.random(in: 0..<Self.lineCount)
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let lineCount = 20
    /// Slow enough to finish reading, quick enough to feel alive.
    private let beat = Timer.publish(every: 1.1, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            DS.Palette.inkInverse(0.72)

            VStack(spacing: 18) {
                ProgressView()
                    .controlSize(.large)
                    .tint(DS.Palette.accent)

                VStack(spacing: 7) {
                    Text(Self.text(at: line))
                        .dsFont(.sans, .semibold, 16)
                        .foregroundStyle(DS.Palette.ink)
                        .multilineTextAlignment(.center)
                        .id(line)
                        .transition(
                            reduceMotion
                                ? .opacity
                                : .asymmetric(
                                    insertion: .opacity.combined(with: .offset(y: 8)),
                                    removal: .opacity.combined(with: .offset(y: -8))
                                )
                        )

                    Text(status)
                        .dsFont(.mono, .medium, 11)
                        .foregroundStyle(DS.Palette.ink(0.45))
                        .contentTransition(.numericText())
                }
                .frame(minHeight: 52)
            }
            .padding(28)
            .frame(maxWidth: 320)
            .dsGlass(
                tint: DS.Palette.glassSheet(0.9),
                in: RoundedRectangle(cornerRadius: DS.Radius.sheet, style: .continuous),
                border: DS.Palette.hairline(0.12)
            )
            .padding(.horizontal, 40)
        }
        .ignoresSafeArea()
        .transition(.opacity)
        .onReceive(beat) { _ in
            withAnimation(DS.Motion.settle) {
                // Stepping rather than re-rolling: random picks repeat, and seeing the same line
                // twice in a row reads as the app having stalled.
                line = (line + 1) % Self.lineCount
            }
        }
    }

    private static func text(at index: Int) -> String {
        String(localized: String.LocalizationValue("busy.line.\(index)"))
    }
}
