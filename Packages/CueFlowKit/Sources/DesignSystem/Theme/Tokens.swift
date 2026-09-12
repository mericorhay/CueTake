import SwiftUI

// Values extracted verbatim from the CueFlow design file (CueFlow.dc.html).
// Do not "improve" these numbers: the design is the source of truth.

extension Color {
    /// #RRGGBB, with optional alpha. Matches the hex literals in the design.
    public init(hex: UInt32, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}

public enum DS {}

extension DS {
    public enum Palette {
        /// Page behind the device frame. #08080A
        public static let page = Color(hex: 0x08080A)
        /// Screen background. #0B0B0D
        public static let screen = Color(hex: 0x0B0B0D)
        /// Camera stand-in. #101014
        public static let camera = Color(hex: 0x101014)
        /// Cards. #131317
        public static let surface = Color(hex: 0x131317)
        /// Raised cards. #17171C
        public static let surfaceRaised = Color(hex: 0x17171C)
        /// Active / selected card. #1A1A20
        public static let surfaceActive = Color(hex: 0x1A1A20)
        /// Control strip. #121216
        public static let surfaceStrip = Color(hex: 0x121216)

        /// Primary text. #F5F5F7
        public static let ink = Color(hex: 0xF5F5F7)
        /// Text on accent / light surfaces. #0B0B0D
        public static let inkInverse = Color(hex: 0x0B0B0D)

        /// Brand accent. #FF5A4F
        public static let accent = Color(hex: 0xFF5A4F)
        /// Secondary warm. #FF7043
        public static let accentWarm = Color(hex: 0xFF7043)
        /// Signal lime. #E8FF4F
        public static let lime = Color(hex: 0xE8FF4F)

        /// Translucent ink, e.g. `ink(0.45)` for rgba(245,245,247,.45).
        public static func ink(_ opacity: Double) -> Color { Color(hex: 0xF5F5F7, alpha: opacity) }
        /// Translucent dark ink used on accent surfaces, e.g. rgba(11,11,13,.6).
        public static func inkInverse(_ opacity: Double) -> Color { Color(hex: 0x0B0B0D, alpha: opacity) }
        /// Hairline borders: rgba(255,255,255,x).
        public static func hairline(_ opacity: Double) -> Color { Color(.sRGB, white: 1, opacity: opacity) }
        /// Accent wash: rgba(255,90,79,x).
        public static func accent(_ opacity: Double) -> Color { Color(hex: 0xFF5A4F, alpha: opacity) }
        /// Lime wash: rgba(232,255,79,x).
        public static func lime(_ opacity: Double) -> Color { Color(hex: 0xE8FF4F, alpha: opacity) }

        /// Glass panels: rgba(20,20,24,x).
        public static func glass(_ opacity: Double) -> Color { Color(hex: 0x141418, alpha: opacity) }
        /// Sheet glass: rgba(19,19,23,x).
        public static func glassSheet(_ opacity: Double) -> Color { Color(hex: 0x131317, alpha: opacity) }

        /// Segment colors, in blueprint order.
        public static let segmentHook = accent
        public static let segmentIntro = accentWarm
        public static let segmentPoint = lime
        public static let segmentCTA = ink
    }

    /// Corner radii used across the design.
    public enum Radius {
        public static let xs: CGFloat = 6
        public static let s: CGFloat = 11
        public static let m: CGFloat = 14
        public static let card: CGFloat = 20
        public static let cardLarge: CGFloat = 22
        public static let sheet: CGFloat = 26
        public static let hero: CGFloat = 28
    }

    /// Blur radii behind glass surfaces (CSS backdrop-filter values).
    public enum Blur {
        public static let chip: CGFloat = 8
        public static let control: CGFloat = 20
        public static let panel: CGFloat = 26
        public static let sheet: CGFloat = 30
    }
}
