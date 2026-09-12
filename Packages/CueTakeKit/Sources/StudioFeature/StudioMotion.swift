import DesignSystem
import SwiftUI

/// The shutter's press response.
///
/// Two rings that shrink by different amounts on different springs, so the control reads as
/// mechanically linked rather than as one flat image being scaled. The ring gives less than the
/// disc, which is what a physical button does: the bezel barely moves, the key travels.
struct ShutterButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .animation(
                configuration.isPressed ? DS.Motion.snap : DS.Motion.bloom,
                value: configuration.isPressed
            )
            .sensoryFeedback(.impact(weight: .heavy, intensity: 0.9), trigger: configuration.isPressed) { _, pressed in
                pressed
            }
    }
}

/// The stop button's press response.
///
/// The square turns to a diamond as it goes down — the outer ring is a circle, so the rotation is
/// only visible on the square inside it. Ending a take is a different act from starting one and
/// gets a different gesture: the shutter travels, this one pivots. Nobody will name it, and it is
/// why the two buttons do not feel interchangeable.
struct StopButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .rotationEffect(.degrees(configuration.isPressed ? 45 : 0))
            .animation(
                configuration.isPressed ? DS.Motion.snap : DS.Motion.settle,
                value: configuration.isPressed
            )
            .sensoryFeedback(.impact(weight: .medium, intensity: 0.8), trigger: configuration.isPressed) { _, pressed in
                pressed
            }
    }
}

/// A ring that expands out of a control and fades, played once when something commits.
///
/// Deliberately not a loop: a repeating animation is decoration and stops being read after the
/// third cycle. This fires when the shutter is pressed and never otherwise, so it stays meaningful.
struct BloomRing: View {
    let trigger: Int
    var color: Color = DS.Palette.accent

    @State private var phase = false

    var body: some View {
        Circle()
            .stroke(color, lineWidth: 2)
            .scaleEffect(phase ? 1.7 : 0.92)
            .opacity(phase ? 0 : 0.8)
            .animation(.easeOut(duration: 0.55), value: phase)
            .allowsHitTesting(false)
            .onChange(of: trigger) { _, _ in
                phase = false
                // One frame at the start size, so a second press restarts the ring instead of
                // animating it backwards from wherever the last one had reached.
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(16))
                    phase = true
                }
            }
    }
}
