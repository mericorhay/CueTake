import SwiftUI

// Every keyframe and easing curve in the design, translated one to one.
// The design leans on a single curve, cubic-bezier(.22,1,.36,1), for almost everything.

extension DS {
    public enum Easing {
        /// cubic-bezier(.22,1,.36,1)
        public static func standard(_ duration: Double) -> Animation {
            .timingCurve(0.22, 1, 0.36, 1, duration: duration)
        }

        /// Plain `transition: all .25s` style easing.
        public static func ease(_ duration: Double) -> Animation {
            .easeInOut(duration: duration)
        }
    }

    /// Entrance animations. Names match the CSS keyframes.
    public enum Entrance {
        /// `scin`: screens fading up 16px with a hair of scale.
        case screen(duration: Double = 0.45)
        /// `rise`: panels and rows coming up 20px.
        case rise(duration: Double = 0.4, delay: Double = 0)
        /// `slab`: 3D cards dropping in with rotateX.
        case slab(duration: Double = 0.6, delay: Double = 0)

        var duration: Double {
            switch self {
            case .screen(let d), .rise(let d, _), .slab(let d, _): d
            }
        }

        var delay: Double {
            switch self {
            case .screen: 0
            case .rise(_, let d), .slab(_, let d): d
            }
        }

        var offsetY: CGFloat {
            switch self {
            case .screen: 16
            case .rise: 20
            case .slab: 30
            }
        }

        var scale: CGFloat {
            switch self {
            case .screen: 0.985
            case .rise: 1
            case .slab: 0.94
            }
        }

        var rotationX: Double {
            switch self {
            case .slab: 22
            default: 0
            }
        }
    }
}

private struct EntranceModifier: ViewModifier {
    let entrance: DS.Entrance
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .scaleEffect(shown || reduceMotion ? 1 : entrance.scale)
            .offset(y: shown || reduceMotion ? 0 : entrance.offsetY)
            .rotation3DEffect(
                .degrees(shown || reduceMotion ? 0 : entrance.rotationX),
                axis: (x: 1, y: 0, z: 0),
                perspective: 0.4
            )
            .onAppear {
                withAnimation(DS.Easing.standard(entrance.duration).delay(entrance.delay)) {
                    shown = true
                }
            }
    }
}

private struct PulseModifier: ViewModifier {
    let duration: Double
    @State private var on = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .scaleEffect(on ? 1.06 : 1)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: duration / 2).repeatForever(autoreverses: true)) {
                    on = true
                }
            }
    }
}

private struct BlinkModifier: ViewModifier {
    let duration: Double
    @State private var dim = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(dim ? 0.25 : 1)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: duration / 2).repeatForever(autoreverses: true)) {
                    dim = true
                }
            }
    }
}

private struct FloatModifier: ViewModifier {
    @State private var up = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .offset(y: up ? -12 : 0)
            .rotationEffect(.degrees(up ? -1 : -3))
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                    up = true
                }
            }
    }
}

/// `ring`: the halo that expands out of the record button.
public struct RecordRing: View {
    @State private var expanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init() {}

    public var body: some View {
        Circle()
            .strokeBorder(DS.Palette.accent(0.5), lineWidth: 2)
            .scaleEffect(expanded ? 1.7 : 0.85)
            .opacity(expanded ? 0 : 0.55)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) {
                    expanded = true
                }
            }
    }
}

/// `sweep`: the light that crosses the Create card.
///
/// The band is 40% of the card wide and travels from -120% to 320% of its own width, which works
/// out to -48%…128% of the card. In the design it sits behind the card's text, so put it in the
/// background stack rather than in an overlay.
public struct SweepShine: View {
    @State private var travelling = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init() {}

    public var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            DS.gradient(100, [.clear, Color(.sRGB, white: 1, opacity: 0.28), .clear])
                .frame(width: width * 0.4)
                .offset(x: travelling ? width * 1.28 : -width * 0.48)
                .onAppear {
                    guard !reduceMotion else { return }
                    withAnimation(.linear(duration: 3.4).repeatForever(autoreverses: false)) {
                        travelling = true
                    }
                }
        }
        .allowsHitTesting(false)
    }
}

extension View {
    public func dsEnter(_ entrance: DS.Entrance) -> some View {
        modifier(EntranceModifier(entrance: entrance))
    }

    public func dsPulse(duration: Double = 1.1) -> some View {
        modifier(PulseModifier(duration: duration))
    }

    public func dsBlink(duration: Double = 1.1) -> some View {
        modifier(BlinkModifier(duration: duration))
    }

    public func dsFloat() -> some View {
        modifier(FloatModifier())
    }
}
