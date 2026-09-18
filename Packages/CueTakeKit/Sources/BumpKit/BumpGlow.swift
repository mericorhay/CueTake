import SwiftUI

/// Where two phones are in meeting each other.
public enum BumpPhase: Hashable, Sendable {
    /// Nothing nearby. No light at all.
    case idle
    /// Looking for the other phone. Still no light: the light is the other phone, and it is not
    /// here yet. It gathers only as the phones come close (see `closeness`).
    case sensing
    /// The phones met: one flash out of the top edge, which then goes out by itself.
    case contact
    /// They are joined. Whatever light is left fades; the card is what remains.
    case connected
}

/// The light two phones make when they touch, drawn from the top edge of the screen.
///
/// Modelled on the system's own: white, brief, and only ever a response to the other phone — it
/// gathers as the phones approach, flashes once when they touch, and is gone a second later.
/// A light that stays on, or that is every colour, stops reading as light and starts reading as
/// decoration.
///
/// Its own module with no dependencies on purpose: it is the showiest piece of the app, the one
/// most likely to be rewritten, and the one that must never be the reason anything else stops
/// working. Everything it needs is SwiftUI; everything it knows is what it is given.
public struct BumpGlow: View {
    public var phase: BumpPhase
    /// 0 far apart … 1 touching. Drives the faint glow before contact; nil where distance
    /// cannot be measured, which means no glow before the tap.
    public var closeness: Double?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var flashes = 0

    public init(phase: BumpPhase, closeness: Double? = nil) {
        self.phase = phase
        self.closeness = closeness
    }

    /// The only colours: white, and at the very edge the faintest cool cast, the way bright light
    /// through glass picks one up.
    static let core = Color.white
    static let rim = Color(red: 0.86, green: 0.92, blue: 1.0)

    public var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack(alignment: .top) {
                approach(in: size)
                flash(in: size)
            }
            .frame(width: size.width, height: size.height, alignment: .top)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .onChange(of: phase) { _, next in
            if next == .contact { flashes += 1 }
        }
        .sensoryFeedback(.impact(weight: .heavy, intensity: 1), trigger: flashes)
        .accessibilityHidden(true)
    }

    // MARK: - Before the touch

    /// A soft white gathering at the top edge as the other phone comes near. Nothing at arm's
    /// length; most of the way there just before they touch.
    private func approach(in size: CGSize) -> some View {
        let near = phase == .sensing ? min(max(closeness ?? 0, 0), 1) : 0
        let eased = near * near
        return Ellipse()
            .fill(
                RadialGradient(
                    colors: [Self.core.opacity(0.9), Self.rim.opacity(0.35), .clear],
                    center: .center,
                    startRadius: 0,
                    endRadius: size.width * 0.5
                )
            )
            .frame(width: size.width * 1.2, height: 60 + 140 * eased)
            .offset(y: -40)
            .blur(radius: 24)
            .blendMode(.plusLighter)
            .opacity(eased * 0.8)
            .animation(.easeOut(duration: 0.25), value: eased)
    }

    // MARK: - The touch

    /// One flash per touch: bright white out of the top edge, rolling a short way down the
    /// screen and gone again within about a second. Keyed on the count of touches, so it plays
    /// once and never idles on screen.
    private func flash(in size: CGSize) -> some View {
        KeyframeAnimator(initialValue: Flash(), trigger: flashes) { value in
            ZStack(alignment: .top) {
                // The body of the light.
                Ellipse()
                    .fill(
                        RadialGradient(
                            colors: [Self.core, Self.core.opacity(0.75), Self.rim.opacity(0.25), .clear],
                            center: .center,
                            startRadius: 0,
                            endRadius: size.width * 0.62
                        )
                    )
                    .frame(width: size.width * 1.35, height: size.height * (0.12 + 0.38 * value.reach))
                    .offset(y: -size.height * 0.06)
                    .blur(radius: reduceMotion ? 18 : 22)

                // The leading edge, a thin brighter line that runs down with the light.
                if !reduceMotion {
                    Capsule()
                        .fill(Self.core.opacity(0.9))
                        .frame(width: size.width * (0.35 + 0.6 * value.reach), height: 3)
                        .offset(y: size.height * 0.32 * value.reach)
                        .blur(radius: 3)
                        .opacity(1 - value.reach)
                }
            }
            .blendMode(.plusLighter)
            .opacity(value.light)
        } keyframes: { _ in
            KeyframeTrack(\.light) {
                LinearKeyframe(0, duration: 0.01)
                CubicKeyframe(1, duration: 0.12)
                CubicKeyframe(0.55, duration: 0.35)
                CubicKeyframe(0, duration: 0.7)
            }
            KeyframeTrack(\.reach) {
                LinearKeyframe(0, duration: 0.01)
                SpringKeyframe(1, duration: reduceMotion ? 0.3 : 0.8, spring: .smooth(duration: 0.8))
                LinearKeyframe(1, duration: 0.37)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .top)
    }

    private struct Flash {
        var light: Double = 0
        var reach: CGFloat = 0
    }
}
