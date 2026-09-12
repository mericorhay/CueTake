import SwiftUI

extension DS {
    /// The app's motion vocabulary.
    ///
    /// Three curves, used deliberately. The point is not that everything moves — it is that two
    /// controls doing different things do not move the same way. A shutter that commits to a take
    /// should not feel like a toggle that draws guide lines.
    ///
    /// All three are springs. Duration-based easing is what makes an interface feel authored rather
    /// than physical: a spring carries the velocity of the gesture that started it, so releasing a
    /// control mid-motion looks like letting go of an object instead of cancelling a video.
    public enum Motion {
        /// Taps. Quick, barely overshoots — finished before the eye follows it.
        public static let snap = Animation.spring(response: 0.26, dampingFraction: 0.7)
        /// Things coming to rest after a gesture: a panel after a drag, a sheet after a dismiss.
        public static let settle = Animation.spring(response: 0.48, dampingFraction: 0.86)
        /// Moments worth noticing. Loose enough to overshoot visibly.
        public static let bloom = Animation.spring(response: 0.42, dampingFraction: 0.55)
    }
}

extension View {
    /// Honours Reduce Motion for the decorative half of an animation while keeping the state change.
    ///
    /// An interface that ignores this setting is not polished, it is loud — and the people who turn
    /// it on are the ones who feel motion the most.
    public func dsMotion(_ animation: Animation, reduced: Bool, value: some Equatable) -> some View {
        self.animation(reduced ? .easeOut(duration: 0.15) : animation, value: value)
    }
}
