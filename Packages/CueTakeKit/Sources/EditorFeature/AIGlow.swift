import DesignSystem
import Domain
import SwiftUI

/// The AI's own colour, so a change it made never reads as one you made.
///
/// Every other colour in the studio already means something — coral is the brand and destructive,
/// lime is selection and snapping. The AI gets a moving spectrum instead of one more flat colour:
/// cyan through violet to rose, turning, which nothing else in the app does.
nonisolated enum AIPalette {
    static let cyan = Color(red: 0.31, green: 0.84, blue: 1.0)
    static let violet = Color(red: 0.55, green: 0.42, blue: 1.0)
    static let rose = Color(red: 1.0, green: 0.36, blue: 0.78)
    static let amber = Color(red: 1.0, green: 0.62, blue: 0.33)

    static let spectrum: [Color] = [cyan, violet, rose, amber, cyan]

    static func angular(_ degrees: Double) -> AngularGradient {
        AngularGradient(colors: spectrum, center: .center, angle: .degrees(degrees))
    }

    static var linear: LinearGradient {
        LinearGradient(colors: [cyan, violet, rose], startPoint: .leading, endPoint: .trailing)
    }

    /// A soft white band at `position` along the diagonal, stops kept inside 0…1 and in order.
    static func sheen(at position: Double) -> [Gradient.Stop] {
        let centre = min(max(position, 0), 1)
        let low = min(max(position - 0.18, 0), centre)
        let high = max(min(position + 0.18, 1), centre)
        let strength = position < -0.1 || position > 1.1 ? 0 : 0.55
        return [
            .init(color: .clear, location: 0),
            .init(color: .clear, location: low),
            .init(color: .white.opacity(strength), location: centre),
            .init(color: .clear, location: high),
            .init(color: .clear, location: 1),
        ]
    }
}

// MARK: - Lighting up what changed

nonisolated private struct GlowFrame {
    var intensity: Double = 0
    var bump: Double = 0
    var angle: Double = 0
    var sweep: Double = -0.3
}

/// Lights a view when its token moves: a spectrum ring that turns, a bloom behind it, a sheen that
/// crosses it and a small spring, then everything settles back to nothing. At rest it draws nothing
/// but, when the thing still carries an AI change, a faint ring.
private struct AIGlowModifier<S: InsettableShape>: ViewModifier {
    let token: Int
    let shape: S
    let touched: Bool
    let inset: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        // Copied out: the animator draws off the main actor and may only hold plain values.
        let shape = shape
        let inset = inset
        let reduceMotion = reduceMotion
        return content
            .overlay {
                if touched {
                    shape
                        .strokeBorder(AIPalette.angular(0), lineWidth: 1.2)
                        .opacity(0.55)
                        .padding(-inset)
                        .allowsHitTesting(false)
                }
            }
            .keyframeAnimator(initialValue: GlowFrame(), trigger: token) { view, frame in
                view
                    .overlay {
                        ZStack {
                            shape
                                .strokeBorder(AIPalette.angular(frame.angle), lineWidth: 2.5)
                            shape
                                .fill(
                                    LinearGradient(
                                        stops: AIPalette.sheen(at: frame.sweep),
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .blendMode(.plusLighter)
                        }
                        .padding(-inset)
                        .opacity(frame.intensity)
                        .allowsHitTesting(false)
                    }
                    .background {
                        shape
                            .fill(AIPalette.angular(frame.angle))
                            .padding(-inset - 2)
                            .blur(radius: 14)
                            .opacity(frame.intensity * 0.85)
                            .allowsHitTesting(false)
                    }
                    .scaleEffect(reduceMotion ? 1 : 1 + frame.bump)
            } keyframes: { _ in
                KeyframeTrack(\.intensity) {
                    CubicKeyframe(1, duration: 0.16)
                    LinearKeyframe(1, duration: 0.9)
                    CubicKeyframe(0, duration: 0.9)
                }
                KeyframeTrack(\.bump) {
                    SpringKeyframe(0.07, duration: 0.18, spring: .bouncy)
                    SpringKeyframe(0, duration: 0.6, spring: .bouncy(duration: 0.5, extraBounce: 0.2))
                }
                KeyframeTrack(\.angle) {
                    LinearKeyframe(0, duration: 0.01)
                    LinearKeyframe(620, duration: 1.95)
                }
                KeyframeTrack(\.sweep) {
                    LinearKeyframe(-0.3, duration: 0.08)
                    CubicKeyframe(1.3, duration: 0.8)
                }
            }
    }

}

extension View {
    /// Lights this view each time `token` changes. See `AIGlowModifier`.
    func aiGlow<S: InsettableShape>(_ token: Int, in shape: S, touched: Bool = false, inset: CGFloat = 0) -> some View {
        modifier(AIGlowModifier(token: token, shape: shape, touched: touched, inset: inset))
    }
}

// MARK: - The whole studio, while the AI has it

/// A spectrum light around the edge of the screen while the AI reads and edits.
///
/// Slow and breathing while it reads, quicker while it changes things. Three strokes of the same
/// turning gradient — a sharp line, a glow and a wide haze — which is what makes it read as light
/// rather than as a border.
struct AIAuroraBorder: View {
    let active: Bool
    let fast: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: !active || reduceMotion)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let angle = (t * (fast ? 150 : 70)).truncatingRemainder(dividingBy: 360)
            let breath = 0.5 + 0.5 * sin(t * (fast ? 5 : 2.2))
            let shape = RoundedRectangle(cornerRadius: 56, style: .continuous)
            ZStack {
                shape.strokeBorder(AIPalette.angular(angle), lineWidth: 2.5 + breath)
                shape.strokeBorder(AIPalette.angular(angle), lineWidth: 10 + breath * 6)
                    .blur(radius: 12)
                    .opacity(0.8)
                shape.strokeBorder(AIPalette.angular(angle + 40), lineWidth: 34)
                    .blur(radius: 38)
                    .opacity(0.35 + breath * 0.25)
            }
        }
        .ignoresSafeArea()
        .opacity(active ? 1 : 0)
        .animation(.easeInOut(duration: 0.6), value: active)
        .allowsHitTesting(false)
    }
}

/// A beam that sweeps back and forth across the timeline while the AI reads it.
struct AIReadingBeam: View {
    var body: some View {
        TimelineView(.animation) { context in
            GeometryReader { proxy in
                let t = context.date.timeIntervalSinceReferenceDate
                let phase = 0.5 - 0.5 * cos(t * 2.1)
                let width = max(proxy.size.width * 0.28, 60)
                LinearGradient(
                    colors: [.clear, AIPalette.cyan.opacity(0.35), AIPalette.violet.opacity(0.55), AIPalette.rose.opacity(0.3), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: width)
                .overlay {
                    Rectangle()
                        .fill(.white.opacity(0.85))
                        .frame(width: 1.5)
                        .shadow(color: AIPalette.violet, radius: 6)
                }
                .blendMode(.plusLighter)
                .offset(x: CGFloat(phase) * (proxy.size.width - width))
            }
        }
        .allowsHitTesting(false)
    }
}

/// A diagonal sheen crossing the picture over and over while the AI reads the frames.
struct AIShimmer: View {
    var body: some View {
        TimelineView(.animation) { context in
            GeometryReader { proxy in
                let t = context.date.timeIntervalSinceReferenceDate
                let travel = (t / 1.6).truncatingRemainder(dividingBy: 1)
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: AIPalette.violet.opacity(0.0), location: max(0, travel - 0.2)),
                        .init(color: AIPalette.cyan.opacity(0.28), location: travel),
                        .init(color: AIPalette.rose.opacity(0.0), location: min(1, travel + 0.2)),
                        .init(color: .clear, location: 1),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .frame(width: proxy.size.width, height: proxy.size.height)
                .blendMode(.plusLighter)
            }
        }
        .allowsHitTesting(false)
    }
}

nonisolated private struct ScanFrame {
    var open: Double = 0
    var glow: Double = 0
}

/// The stretch of the timeline an AI step works on: it opens out from its centre, glows while the
/// change lands and fades away.
struct AIScanBand: View {
    let mark: AIScanMark
    let scale: Double
    let height: CGFloat

    var body: some View {
        let width = max(CGFloat((mark.range.upperBound - mark.range.lowerBound) * scale), 6)
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(AIPalette.linear.opacity(0.28))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(AIPalette.linear, lineWidth: 1.5)
            }
            .frame(width: width, height: height)
            .keyframeAnimator(initialValue: ScanFrame(), repeating: false) { view, frame in
                view
                    .scaleEffect(x: frame.open, y: 1)
                    .shadow(color: AIPalette.violet.opacity(frame.glow), radius: 12)
                    .opacity(frame.glow)
            } keyframes: { _ in
                KeyframeTrack(\.open) {
                    SpringKeyframe(1, duration: 0.35, spring: .snappy)
                }
                KeyframeTrack(\.glow) {
                    CubicKeyframe(1, duration: 0.2)
                    LinearKeyframe(1, duration: 0.9)
                    CubicKeyframe(0, duration: 0.5)
                }
            }
            .offset(x: CGFloat(mark.range.lowerBound * scale))
            .allowsHitTesting(false)
    }
}

/// A small spectrum sparkle, for "the AI did this".
struct AISparkle: View {
    var size: CGFloat = 9

    var body: some View {
        Image(systemName: "sparkle")
            .font(.system(size: size, weight: .bold))
            .foregroundStyle(AIPalette.linear)
            .shadow(color: AIPalette.violet.opacity(0.7), radius: 3)
    }
}
