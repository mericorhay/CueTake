import SwiftUI

/// Round icon button in the corner of most screens.
/// Two flavours in the design: flat rgba(255,255,255,.07), and glass when it sits over the camera.
public struct DSCircleButton: View {
    public enum Style { case flat, glass }

    private let glyph: String
    private let size: CGFloat
    private let fontSize: CGFloat
    /// Set when the glyph is type rather than a symbol — the studio's "Aa" is Archivo in the
    /// design, while the arrows and crosses are drawn in the system face at a given size.
    private let font: Font?
    private let style: Style
    private let action: () -> Void

    public init(
        _ glyph: String,
        size: CGFloat = 36,
        fontSize: CGFloat = 16,
        font: Font? = nil,
        style: Style = .flat,
        action: @escaping () -> Void
    ) {
        self.glyph = glyph
        self.size = size
        self.fontSize = fontSize
        self.font = font
        self.style = style
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            // The skin belongs to the label: a background applied outside the Button is not part
            // of what gets hit-tested, which used to leave only the glyph tappable.
            Text(glyph)
                .font(font ?? .system(size: fontSize))
                .foregroundStyle(DS.Palette.ink)
                .frame(width: size, height: size)
                .modifier(CircleSkin(style: style))
        }
        .buttonStyle(.dsPressIcon)
    }
}

private struct CircleSkin: ViewModifier {
    let style: DSCircleButton.Style

    @ViewBuilder
    func body(content: Content) -> some View {
        switch style {
        case .flat:
            content.background(Circle().fill(DS.Palette.hairline(0.07)))
        case .glass:
            content.dsGlass(tint: DS.Palette.glass(0.55), in: Circle())
        }
    }
}

/// Full-width accent button: #FF5A4F, radius 20–22, vertical padding 17–19.
public struct DSPrimaryButton: View {
    private let title: String
    private let fill: Color
    private let radius: CGFloat
    private let verticalPadding: CGFloat
    private let fontSize: CGFloat
    private let glow: Bool
    private let action: () -> Void

    public init(
        _ title: String,
        fill: Color = DS.Palette.accent,
        radius: CGFloat = DS.Radius.card,
        verticalPadding: CGFloat = 17,
        fontSize: CGFloat = 15,
        glow: Bool = true,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.fill = fill
        self.radius = radius
        self.verticalPadding = verticalPadding
        self.fontSize = fontSize
        self.glow = glow
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Text(title)
                .dsFont(.sans, .semibold, fontSize)
                .foregroundStyle(DS.Palette.inkInverse)
                .frame(maxWidth: .infinity)
                .padding(.vertical, verticalPadding)
                .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(fill))
        }
        .buttonStyle(.dsPress(radius: radius))
        .shadow(color: glow ? DS.Palette.accent(0.34) : .clear, radius: 20, y: 14)
    }
}

/// Glass companion to `DSPrimaryButton` — "Retake", "Edit", "Shoot again".
public struct DSSecondaryButton: View {
    private let title: String
    private let radius: CGFloat
    private let verticalPadding: CGFloat
    private let fontSize: CGFloat
    private let action: () -> Void

    public init(
        _ title: String,
        radius: CGFloat = DS.Radius.card,
        verticalPadding: CGFloat = 17,
        fontSize: CGFloat = 15,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.radius = radius
        self.verticalPadding = verticalPadding
        self.fontSize = fontSize
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Text(title)
                .dsFont(.sans, .semibold, fontSize)
                .foregroundStyle(DS.Palette.ink)
                .frame(maxWidth: .infinity)
                .padding(.vertical, verticalPadding)
                .dsGlass(
                    tint: DS.Palette.glass(0.6),
                    in: RoundedRectangle(cornerRadius: radius, style: .continuous),
                    border: DS.Palette.hairline(0.14)
                )
        }
        .buttonStyle(.dsPress(radius: radius))
    }
}

/// Small selectable pill used by captions, teleprompter and segmented rows.
public struct DSPill: View {
    private let title: String
    private let isOn: Bool
    private let onFill: Color
    private let fontSize: CGFloat
    private let radius: CGFloat
    private let verticalPadding: CGFloat
    private let action: () -> Void

    public init(
        _ title: String,
        isOn: Bool,
        onFill: Color = DS.Palette.accent,
        fontSize: CGFloat = 12,
        radius: CGFloat = 13,
        verticalPadding: CGFloat = 11,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.isOn = isOn
        self.onFill = onFill
        self.fontSize = fontSize
        self.radius = radius
        self.verticalPadding = verticalPadding
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Text(title)
                .dsFont(.sans, .medium, fontSize)
                .foregroundStyle(isOn ? DS.Palette.inkInverse : DS.Palette.ink(0.65))
                .frame(maxWidth: .infinity)
                .padding(.vertical, verticalPadding)
                .background(
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(isOn ? onFill : DS.Palette.hairline(0.07))
                )
        }
        .buttonStyle(.dsPress(radius: radius))
        .animation(DS.Easing.ease(0.25), value: isOn)
    }
}

/// Uppercase monospaced kicker, e.g. "BLUEPRINT · 0:30".
public struct DSKicker: View {
    private let text: String
    private let size: CGFloat
    private let tracking: CGFloat
    private let color: Color

    public init(
        _ text: String,
        size: CGFloat = 10,
        tracking: CGFloat = 0.16,
        color: Color = DS.Palette.ink(0.4)
    ) {
        self.text = text
        self.size = size
        self.tracking = tracking
        self.color = color
    }

    public var body: some View {
        Text(text)
            .dsFont(.mono, .medium, size, letterSpacing: tracking)
            .foregroundStyle(color)
    }
}
