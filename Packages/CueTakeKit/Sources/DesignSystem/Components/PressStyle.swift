import SwiftUI

/// The press feedback every control in the app shares.
///
/// The design gives its buttons `transition: transform .3s cubic-bezier(.22,1,.36,1)` and relies on
/// the pointer cursor for the rest. On a phone there is no cursor, so the press state has to carry
/// the whole signal — and `.buttonStyle(.plain)`, which the screens used to reach for, gives none at
/// all: no dim, no scale, no shape. A control that never acknowledges a touch reads as broken long
/// before the user works out that the tap did in fact register.
///
/// Two things happen here that `.plain` did not do:
///
/// 1. The label is given a hit shape. `.plain` hit-tests the label's own geometry, so a button whose
///    background sits outside the label is tappable only on its glyphs.
/// 2. The press is animated, and the release is springy rather than linear, so a tap feels like it
///    pushed something.
public struct DSPressStyle: ButtonStyle {
    private let scale: CGFloat
    private let dim: Double
    private let shape: AnyShape?

    /// - Parameters:
    ///   - scale: size at full press. Large surfaces travel less than small ones.
    ///   - dim: opacity at full press, on top of the scale.
    ///   - shape: hit shape for the label. Pass the control's own outline so the touch target
    ///     matches what is drawn; `nil` uses a rectangle, which is right for most labels.
    /// The smallest square a touch can land in, in points. Apple's guidelines ask for 44.
    private let minimumTarget: CGFloat

    public init(scale: CGFloat = 0.97, dim: Double = 1, shape: AnyShape? = nil, minimumTarget: CGFloat = 0) {
        self.scale = scale
        self.dim = dim
        self.shape = shape
        self.minimumTarget = minimumTarget
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(shape ?? AnyShape(Rectangle()))
            // A small drawn control still takes a finger-sized touch: the frame grows around it,
            // the drawing does not.
            .frame(minWidth: minimumTarget, minHeight: minimumTarget)
            .contentShape(minimumTarget > 0 ? AnyShape(Rectangle()) : (shape ?? AnyShape(Rectangle())))
            .scaleEffect(configuration.isPressed ? scale : 1)
            .opacity(configuration.isPressed ? dim : 1)
            // On the way down only, so a press taps once rather than twice.
            .sensoryFeedback(.impact(weight: .light, intensity: 0.7), trigger: configuration.isPressed) { _, pressed in
                pressed
            }
            // Down is quick so the control feels responsive; up overshoots slightly so it feels
            // physical rather than animated.
            .animation(
                configuration.isPressed
                    ? DS.Easing.ease(0.12)
                    : .spring(response: 0.34, dampingFraction: 0.62),
                value: configuration.isPressed
            )
    }
}

extension ButtonStyle where Self == DSPressStyle {
    /// Default press for text, icons and rows.
    public static var dsPress: DSPressStyle { DSPressStyle() }

    /// Press for large surfaces — full-width buttons and cards. They travel less, because the same
    /// ratio on a big rectangle reads as the whole screen flinching.
    public static var dsPressCard: DSPressStyle { DSPressStyle(scale: 0.985, dim: 0.92) }

    /// Press for small round controls, which can afford to move further.
    public static var dsPressIcon: DSPressStyle {
        DSPressStyle(scale: 0.9, dim: 0.8, shape: AnyShape(Circle()), minimumTarget: 44)
    }

    /// Press for a control with a known corner radius, so the touch target follows the drawn edge.
    public static func dsPress(radius: CGFloat, scale: CGFloat = 0.97) -> DSPressStyle {
        DSPressStyle(
            scale: scale,
            shape: AnyShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        )
    }
}
