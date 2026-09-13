import DesignSystem
import Domain
import SwiftUI

/// The AI's own colour, so a change it made never reads as one you made.
///
/// One quiet violet with a lighter tint beside it. Coral is the brand and lime is selection; the AI
/// needs to be told apart from both, not to compete with the footage.
nonisolated enum AIPalette {
    static let violet = Color(red: 0.58, green: 0.50, blue: 1.0)
    static let lilac = Color(red: 0.74, green: 0.68, blue: 1.0)

    static var linear: LinearGradient {
        LinearGradient(colors: [violet, lilac], startPoint: .leading, endPoint: .trailing)
    }
}

// MARK: - Lighting up what changed

nonisolated private struct GlowFrame {
    var intensity: Double = 0
    var bump: Double = 0
}

/// Lights a view when its token moves: a violet outline and a faint wash that come up quickly and
/// fade, with a small lift. Nothing is drawn at rest, and nothing blurs — this runs over live
/// video on a timeline that may be scrolling.
private struct AIGlowModifier<S: InsettableShape>: ViewModifier {
    let token: Int
    let shape: S
    let inset: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        // Copied out: the animator's content closure may only hold plain values.
        let shape = shape
        let inset = inset
        let reduceMotion = reduceMotion
        return content
            .keyframeAnimator(initialValue: GlowFrame(), trigger: token) { view, frame in
                view
                    .overlay {
                        ZStack {
                            shape.fill(AIPalette.violet.opacity(0.16))
                            shape.strokeBorder(AIPalette.violet, lineWidth: 2)
                        }
                        .padding(-inset)
                        .opacity(frame.intensity)
                        .allowsHitTesting(false)
                    }
                    .scaleEffect(reduceMotion ? 1 : 1 + frame.bump)
            } keyframes: { _ in
                KeyframeTrack(\.intensity) {
                    CubicKeyframe(1, duration: 0.12)
                    LinearKeyframe(1, duration: 0.6)
                    CubicKeyframe(0, duration: 0.5)
                }
                KeyframeTrack(\.bump) {
                    SpringKeyframe(0.03, duration: 0.14, spring: .snappy)
                    SpringKeyframe(0, duration: 0.3, spring: .snappy)
                }
            }
    }
}

extension View {
    /// Lights this view each time `token` changes. See `AIGlowModifier`.
    func aiGlow<S: InsettableShape>(_ token: Int, in shape: S, inset: CGFloat = 0) -> some View {
        modifier(AIGlowModifier(token: token, shape: shape, inset: inset))
    }
}

// MARK: - The whole studio, while the AI has it

/// A thin violet edge around the screen while the AI works, breathing slowly.
///
/// One stroke whose opacity is animated by the render server rather than redrawn by SwiftUI every
/// frame; the earlier version redrew three blurred gradients sixty times a second over the video.
struct AIAuroraBorder: View {
    let active: Bool

    @State private var breathing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        RoundedRectangle(cornerRadius: 56, style: .continuous)
            .strokeBorder(AIPalette.violet, lineWidth: 2.5)
            .opacity(active ? (breathing ? 0.9 : 0.35) : 0)
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .animation(.easeInOut(duration: 0.35), value: active)
            .onChange(of: active, initial: true) { _, on in
                guard on, !reduceMotion else {
                    breathing = false
                    return
                }
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                    breathing = true
                }
            }
    }
}

/// A soft band that slides back and forth across the timeline while the AI reads it.
struct AIReadingBeam: View {
    @State private var across = false

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width * 0.25, 60)
            LinearGradient(
                colors: [.clear, AIPalette.violet.opacity(0.28), .clear],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: width)
            .offset(x: across ? proxy.size.width - width : 0)
        }
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                across = true
            }
        }
    }
}

/// The stretch of the timeline an AI step works on: it opens from its left edge and fades.
struct AIScanBand: View {
    let mark: AIScanMark
    let scale: Double
    let height: CGFloat

    var body: some View {
        let width = max(CGFloat((mark.range.upperBound - mark.range.lowerBound) * scale), 6)
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(AIPalette.violet.opacity(0.18))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(AIPalette.violet.opacity(0.8), lineWidth: 1.5)
            }
            .frame(width: width, height: height)
            .keyframeAnimator(initialValue: ScanFrame(), repeating: false) { view, frame in
                view
                    .scaleEffect(x: frame.open, y: 1, anchor: .leading)
                    .opacity(frame.glow)
            } keyframes: { _ in
                KeyframeTrack(\.open) {
                    SpringKeyframe(1, duration: 0.25, spring: .snappy)
                }
                KeyframeTrack(\.glow) {
                    CubicKeyframe(1, duration: 0.12)
                    LinearKeyframe(1, duration: 0.7)
                    CubicKeyframe(0, duration: 0.4)
                }
            }
            .offset(x: CGFloat(mark.range.lowerBound * scale))
            .allowsHitTesting(false)
    }
}

nonisolated private struct ScanFrame {
    var open: Double = 0
    var glow: Double = 0
}

/// A small violet sparkle, for "the AI did this".
struct AISparkle: View {
    var size: CGFloat = 9

    var body: some View {
        Image(systemName: "sparkle")
            .font(.system(size: size, weight: .bold))
            .foregroundStyle(AIPalette.violet)
    }
}

/// The AI's mark: a violet disc with sparkles, which shimmer while it works.
struct AIOrb: View {
    let fast: Bool
    var size: CGFloat = 36

    var body: some View {
        Circle()
            .fill(AIPalette.linear)
            .overlay {
                Image(systemName: "sparkles")
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(.white)
                    .symbolEffect(.variableColor.iterative, options: .repeating, isActive: fast)
            }
            .frame(width: size, height: size)
            .allowsHitTesting(false)
    }
}

/// A still violet outline, stronger while the AI works.
struct AIRing<S: InsettableShape>: View {
    let shape: S
    let active: Bool

    var body: some View {
        shape
            .strokeBorder(AIPalette.violet, lineWidth: 1)
            .opacity(active ? 0.9 : 0.4)
            .allowsHitTesting(false)
    }
}
