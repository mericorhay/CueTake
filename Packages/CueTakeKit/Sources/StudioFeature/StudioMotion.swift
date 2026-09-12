import DesignSystem
import SwiftUI

/// The studio's motion vocabulary.
///
/// Three curves, used deliberately. The point is not that every control moves — it is that two
/// controls which do different things do not move the same way. A shutter that commits to a take
/// should not feel like a toggle that draws guide lines, and a panel being dragged should not
/// settle like a button being tapped.
///
/// All three are springs. Duration-based easing is what makes an interface feel authored rather
/// than physical: a spring carries the velocity of the gesture that started it, so releasing a
/// control mid-motion looks like letting go of an object instead of cancelling a video.
enum StudioMotion {
    /// Taps. Quick, barely overshoots — it should be finished before the eye follows it.
    static let snap = Animation.spring(response: 0.26, dampingFraction: 0.7)
    /// Things coming to rest after a gesture: the prompter after a drag, a sheet after a dismiss.
    static let settle = Animation.spring(response: 0.48, dampingFraction: 0.86)
    /// Moments worth noticing. Loose enough to overshoot visibly, for the shutter and the count.
    static let bloom = Animation.spring(response: 0.42, dampingFraction: 0.55)
}

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
                configuration.isPressed ? StudioMotion.snap : StudioMotion.bloom,
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
                configuration.isPressed ? StudioMotion.snap : StudioMotion.settle,
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

extension View {
    /// Honours Reduce Motion for the decorative half of an animation while keeping the state change.
    ///
    /// An interface that ignores this setting is not polished, it is loud — and the people who turn
    /// it on are the ones who feel motion the most.
    func studioMotion(_ animation: Animation, reduced: Bool, value: some Equatable) -> some View {
        self.animation(reduced ? .easeOut(duration: 0.15) : animation, value: value)
    }
}
