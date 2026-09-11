import SwiftUI

/// Dark-first palette, like Apple Camera: the camera image and the user's face are the content,
/// chrome stays out of the way. Defined in code so every module shares one source of truth.
public enum Palette {
    public static let background = Color(red: 0.04, green: 0.04, blue: 0.05)
    public static let surface = Color(red: 0.11, green: 0.11, blue: 0.13)
    public static let textPrimary = Color.white
    public static let textSecondary = Color.white.opacity(0.62)
    public static let accent = Color(red: 1.0, green: 0.78, blue: 0.18)
    public static let recording = Color(red: 1.0, green: 0.23, blue: 0.19)
    public static let success = Color(red: 0.2, green: 0.84, blue: 0.47)
}

public enum Spacing {
    public static let xxs: CGFloat = 2
    public static let xs: CGFloat = 4
    public static let s: CGFloat = 8
    public static let m: CGFloat = 12
    public static let l: CGFloat = 16
    public static let xl: CGFloat = 24
    public static let xxl: CGFloat = 32
    public static let xxxl: CGFloat = 48
}

public enum Radius {
    public static let s: CGFloat = 10
    public static let m: CGFloat = 16
    public static let l: CGFloat = 24
}

public enum Motion {
    /// Buttons, toggles, record state.
    public static let snappy: Animation = .snappy(duration: 0.25)
    /// Teleprompter scrolling, panel transitions.
    public static let smooth: Animation = .smooth(duration: 0.4)
    public static let bouncy: Animation = .spring(duration: 0.45, bounce: 0.25)
}

extension Font {
    public static let cfDisplay = Font.system(.largeTitle, design: .rounded, weight: .bold)
    public static let cfTitle = Font.system(.title2, design: .rounded, weight: .semibold)
    public static let cfHeadline = Font.system(.headline, design: .rounded)
    public static let cfBody = Font.system(.body)
    public static let cfCaption = Font.system(.footnote, weight: .medium)

    /// Teleprompter text. Sized by the teleprompter's own scale setting rather than Dynamic Type,
    /// because it is read from a distance.
    public static func cfPrompter(size: CGFloat) -> Font {
        .system(size: size, weight: .semibold, design: .rounded)
    }
}
