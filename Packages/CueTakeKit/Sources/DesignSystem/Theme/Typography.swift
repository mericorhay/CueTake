import CoreText
import SwiftUI
import UIKit

// The design uses three Google fonts. They ship inside this module and are registered at runtime,
// so no Info.plist entry is needed and the module stays self-contained.
//
// CSS in the design is written as `font: <weight> <size>px/<line-height> '<family>'`.
// `DS.archivo(...)`, `DS.sans(...)` and `DS.mono(...)` mirror that shorthand one to one.

extension DS {
    public enum FontFamily: String {
        case archivo = "Archivo"
        case sans = "InstrumentSans"
        case mono = "JetBrainsMono"
    }

    /// Weights the design actually uses. Anything else is not in the type system by design.
    public enum FontWeight: Int {
        case regular = 400
        case medium = 500
        case semibold = 600
        case bold = 700
        case extrabold = 800
    }

    public static func fontName(_ family: FontFamily, _ weight: FontWeight) -> String {
        let suffix: String
        switch weight {
        case .regular: suffix = "Regular"
        case .medium: suffix = "Medium"
        case .semibold: suffix = "SemiBold"
        case .bold: suffix = "Bold"
        case .extrabold: suffix = "ExtraBold"
        }
        return "\(family.rawValue)-\(suffix)"
    }

    /// Matches `font: 800 34px 'Archivo'`.
    public static func archivo(_ weight: FontWeight, _ size: CGFloat) -> Font {
        custom(.archivo, weight, size)
    }

    /// Matches `font: 400 14px 'Instrument Sans'`.
    public static func sans(_ weight: FontWeight, _ size: CGFloat) -> Font {
        custom(.sans, weight, size)
    }

    /// Matches `font: 500 10px 'JetBrains Mono'`. The design only ever uses weight 500 here.
    public static func mono(_ size: CGFloat) -> Font {
        custom(.mono, .medium, size)
    }

    /// Follows the reader's text size (Dynamic Type) from the size the design set. The root view
    /// caps how far, so a layout drawn for the default size still holds together.
    public static func custom(_ family: FontFamily, _ weight: FontWeight, _ size: CGFloat) -> Font {
        FontRegistry.ensureRegistered()
        return .custom(fontName(family, weight), size: size, relativeTo: textStyle(for: size))
    }

    /// A face at exactly this size, whatever the reader's text size: for type whose size is itself
    /// a setting, like the prompter's.
    public static func fixed(_ family: FontFamily, _ weight: FontWeight, _ size: CGFloat) -> Font {
        FontRegistry.ensureRegistered()
        return .custom(fontName(family, weight), fixedSize: size)
    }

    /// The system style a size grows with, so small labels and large titles scale as the system's own do.
    static func textStyle(for size: CGFloat) -> Font.TextStyle {
        switch size {
        case ..<11.5: .caption2
        case ..<12.5: .caption
        case ..<13.5: .footnote
        case ..<15.5: .subheadline
        case ..<17.5: .body
        case ..<20.5: .title3
        case ..<24.5: .title2
        case ..<30: .title
        default: .largeTitle
        }
    }

    /// How far the app's type follows the reader's text size.
    public static let largestTextSize = DynamicTypeSize.xxLarge

    static func uiFont(_ family: FontFamily, _ weight: FontWeight, _ size: CGFloat) -> UIFont {
        FontRegistry.ensureRegistered()
        return UIFont(name: fontName(family, weight), size: size)
            ?? .systemFont(ofSize: size, weight: weight == .regular ? .regular : .semibold)
    }
}

enum FontRegistry {
    private static var didRegister = false

    /// Registers the bundled faces once per process.
    static func ensureRegistered() {
        guard !didRegister else { return }
        didRegister = true
        let faces = [
            "Archivo-SemiBold", "Archivo-Bold", "Archivo-ExtraBold",
            "InstrumentSans-Regular", "InstrumentSans-Medium", "InstrumentSans-SemiBold",
            "JetBrainsMono-Medium",
        ]
        for face in faces {
            // SwiftPM may or may not keep the "Fonts" subdirectory, so try both spellings.
            let url = Bundle.module.url(forResource: face, withExtension: "ttf")
                ?? Bundle.module.url(forResource: face, withExtension: "ttf", subdirectory: "Fonts")
            guard let url else {
                assertionFailure("Missing bundled font \(face).ttf")
                continue
            }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}

extension View {
    /// Applies a design font together with CSS-equivalent letter spacing and line height.
    ///
    /// `letterSpacing` is in em, like the design's `letter-spacing:-.03em`.
    /// `lineHeight` is the CSS multiplier; it only stretches lines, never tightens them —
    /// for tight display type (`line-height:.95`) use ``DSHeadline``.
    public func dsFont(
        _ family: DS.FontFamily,
        _ weight: DS.FontWeight,
        _ size: CGFloat,
        lineHeight: CGFloat? = nil,
        letterSpacing: CGFloat = 0,
        fixed: Bool = false
    ) -> some View {
        let natural = DS.uiFont(family, weight, size).lineHeight
        let extra = lineHeight.map { max(0, $0 * size - natural) } ?? 0
        return self
            .font(fixed ? DS.fixed(family, weight, size) : DS.custom(family, weight, size))
            .tracking(letterSpacing * size)
            .lineSpacing(extra)
    }
}

/// Display type with exact line height, including values below the font's natural leading.
///
/// SwiftUI cannot tighten line spacing inside a single `Text`, and the design's headlines are set
/// at `line-height:.95`–`1`. Every headline in the design already declares its own line breaks,
/// so each line is laid out individually at the exact box height.
public struct DSHeadline: View {
    private let lines: [String]
    private let size: CGFloat
    private let weight: DS.FontWeight
    private let family: DS.FontFamily
    private let lineHeight: CGFloat
    private let letterSpacing: CGFloat
    private let color: Color
    private let alignment: HorizontalAlignment

    public init(
        _ text: String,
        family: DS.FontFamily = .archivo,
        weight: DS.FontWeight = .extrabold,
        size: CGFloat,
        lineHeight: CGFloat = 1,
        letterSpacing: CGFloat = -0.03,
        color: Color = DS.Palette.ink,
        alignment: HorizontalAlignment = .leading
    ) {
        self.lines = text.components(separatedBy: "\n")
        self.family = family
        self.weight = weight
        self.size = size
        self.lineHeight = lineHeight
        self.letterSpacing = letterSpacing
        self.color = color
        self.alignment = alignment
    }

    public var body: some View {
        // Each line carries its own exact line box, so a line that wraps by itself — Turkish runs
        // longer than the English source — keeps the same tight leading as the authored breaks.
        VStack(alignment: alignment, spacing: 0) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                TightText(
                    line,
                    family,
                    weight,
                    size,
                    lineHeight: lineHeight,
                    letterSpacing: letterSpacing,
                    color: color,
                    alignment: textAlignment
                )
                .frame(maxWidth: .infinity, alignment: frameAlignment)
            }
        }
    }

    // HorizontalAlignment is a struct, so these compare rather than switch.
    private var textAlignment: TextAlignment {
        if alignment == .center { return .center }
        if alignment == .trailing { return .trailing }
        return .leading
    }

    private var frameAlignment: Alignment {
        if alignment == .center { return .center }
        if alignment == .trailing { return .trailing }
        return .leading
    }
}
