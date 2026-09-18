import SwiftUI

/// Where two phones are in meeting each other.
public enum BumpPhase: Hashable, Sendable {
    /// Nothing nearby. No light at all.
    case idle
    /// Looking for the other phone: a thin breathing line of light along the top edge, the
    /// place the other phone should touch.
    case sensing
    /// The phones met. The light bursts out of the top edge and rolls down the screen.
    case contact
    /// They are joined. The light has gathered into a soft band the card sits in.
    case connected
}

/// The light two phones make when they touch, drawn from the top edge of the screen.
///
/// Its own module with no dependencies on purpose: it is the showiest piece of the app, the one
/// most likely to be rewritten, and the one that must never be the reason anything else stops
/// working. Everything it needs is SwiftUI; everything it knows is the phase it is given.
public struct BumpGlow: View {
    public var phase: BumpPhase
    /// The colours of the light's edge. The core is always white: that is what reads as light.
    public var colours: [Color]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var burst = 0

    public init(phase: BumpPhase, colours: [Color] = BumpGlow.iridescent) {
        self.phase = phase
        self.colours = colours.isEmpty ? BumpGlow.iridescent : colours
    }

    public static let iridescent: [Color] = [
        Color(red: 0.36, green: 0.62, blue: 1.0),
        Color(red: 0.62, green: 0.42, blue: 1.0),
        Color(red: 1.0, green: 0.46, blue: 0.78),
        Color(red: 0.4, green: 0.92, blue: 1.0),
    ]

    public var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack(alignment: .top) {
                if phase != .idle {
                    if reduceMotion {
                        still(in: size)
                            .transition(.opacity)
                    } else {
                        TimelineView(.animation) { timeline in
                            let time = timeline.date.timeIntervalSinceReferenceDate
                            light(in: size, time: time)
                        }
                        .transition(.opacity)
                    }
                }
            }
            .frame(width: size.width, height: size.height, alignment: .top)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .animation(.easeInOut(duration: 0.45), value: phase)
        .onChange(of: phase) { _, next in
            if next == .contact { burst += 1 }
        }
        .sensoryFeedback(.impact(weight: .heavy, intensity: 1), trigger: burst)
        .accessibilityHidden(true)
    }

    // MARK: - The light

    /// How far down the screen the light reaches, as a fraction of its height.
    private var reach: CGFloat {
        switch phase {
        case .idle: 0
        case .sensing: 0.05
        case .contact: 0.62
        case .connected: 0.34
        }
    }

    private func light(in size: CGSize, time: Double) -> some View {
        let breathe = 0.5 + 0.5 * sin(time * 2.4)
        let depth = max(size.height * reach, 24)
        let width = size.width

        return ZStack(alignment: .top) {
            // The halo: the colours, turning slowly so the light looks alive rather than printed.
            halo(width: width, depth: depth, time: time)
                .opacity(phase == .sensing ? 0.55 + 0.35 * breathe : 1)

            // The core: white-hot where the phones touch, spread along the edge.
            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [.white, .white.opacity(0.85), .white.opacity(0)],
                        center: .center,
                        startRadius: 0,
                        endRadius: width * 0.36
                    )
                )
                .frame(width: width * (phase == .sensing ? 0.5 : 1.1), height: depth * 0.5)
                .offset(y: -depth * 0.2)
                .blur(radius: phase == .sensing ? 6 : 14)
                .blendMode(.plusLighter)
                .opacity(phase == .sensing ? 0.5 + 0.4 * breathe : 1)

            if phase == .contact {
                ripple(width: width, depth: depth)
            }
        }
        .frame(width: width, height: depth * 1.4, alignment: .top)
        .compositingGroup()
    }

    private func halo(width: CGFloat, depth: CGFloat, time: Double) -> some View {
        let turn = Angle.degrees(time.truncatingRemainder(dividingBy: 12) / 12 * 360)
        return Ellipse()
            .fill(
                AngularGradient(
                    colors: colours + [colours[0]],
                    center: .center,
                    angle: turn
                )
            )
            .frame(width: width * 1.5, height: depth * 1.6)
            .offset(y: -depth * 0.55)
            .blur(radius: max(depth * 0.18, 10))
            .blendMode(.plusLighter)
    }

    /// The single ring that rolls down the screen when the phones meet. Keyed on the burst count
    /// so it plays once per touch and not on every redraw.
    private func ripple(width: CGFloat, depth: CGFloat) -> some View {
        KeyframeAnimator(initialValue: Ripple(), trigger: burst) { value in
            Ellipse()
                .stroke(
                    LinearGradient(colors: colours, startPoint: .leading, endPoint: .trailing),
                    lineWidth: 6
                )
                .frame(width: width * (0.3 + value.spread * 1.2), height: depth * (0.2 + value.spread))
                .offset(y: -depth * 0.25 + value.spread * depth * 0.4)
                .blur(radius: 4 + value.spread * 10)
                .opacity(value.opacity)
                .blendMode(.plusLighter)
        } keyframes: { _ in
            KeyframeTrack(\.spread) {
                CubicKeyframe(0, duration: 0.01)
                SpringKeyframe(1, duration: 0.9, spring: .smooth(duration: 0.9, extraBounce: 0.1))
            }
            KeyframeTrack(\.opacity) {
                LinearKeyframe(1, duration: 0.15)
                LinearKeyframe(0, duration: 0.75)
            }
        }
    }

    /// The same light without motion, for Reduce Motion: a band that fades in and out.
    private func still(in size: CGSize) -> some View {
        LinearGradient(
            colors: [.white.opacity(0.9)] + colours.map { $0.opacity(0.6) } + [.clear],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(width: size.width, height: max(size.height * reach, 20))
        .blur(radius: 12)
        .blendMode(.plusLighter)
    }

    private struct Ripple {
        var spread: CGFloat = 0
        var opacity: Double = 0
    }
}
