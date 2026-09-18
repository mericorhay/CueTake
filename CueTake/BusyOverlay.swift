import Combine
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

    /// Written out, one literal per line, rather than built from the index.
    ///
    /// `String.LocalizationValue("busy.line.\(index)")` looks like it asks for "busy.line.3" and
    /// does not: interpolating into a localization value makes the number an *argument*, so the
    /// key becomes "busy.line.%lld", which is in no table, and the fallback is the key itself with
    /// the number filled in. That is exactly what was on screen. A key has to be a literal to be
    /// a key.
    private static let lines: [LocalizedStringResource] = [
        "busy.line.0", "busy.line.1", "busy.line.2", "busy.line.3", "busy.line.4",
        "busy.line.5", "busy.line.6", "busy.line.7", "busy.line.8", "busy.line.9",
        "busy.line.10", "busy.line.11", "busy.line.12", "busy.line.13", "busy.line.14",
        "busy.line.15", "busy.line.16", "busy.line.17", "busy.line.18", "busy.line.19",
    ]

    private static var lineCount: Int { lines.count }
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
                    Text(Self.lines[min(line, Self.lineCount - 1)])
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
                        .foregroundStyle(DS.Palette.ink(0.56))
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
}
