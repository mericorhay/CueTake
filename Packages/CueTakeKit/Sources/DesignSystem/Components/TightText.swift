import SwiftUI
import UIKit

/// Text with an exact CSS line height, including values tighter than the font's natural leading.
///
/// SwiftUI's `Text` can only add line spacing, never remove it, and `DSHeadline` solves that only
/// for headlines whose line breaks are written into the string. Text that wraps on its own — card
/// titles at `line-height:1.15`, captions at `1.15`/`1.2` — needs a paragraph style, so this drops
/// down to `UILabel`.
///
/// Prefer `dsFont(...)` for everything else; this exists for the tight-leading cases only.
public struct TightText: UIViewRepresentable {
    private let text: String
    private let font: UIFont
    /// Absolute line box height in points, i.e. CSS `font-size × line-height`.
    private let lineHeight: CGFloat
    private let letterSpacing: CGFloat
    private let color: UIColor
    private let alignment: NSTextAlignment
    private let shadow: Shadow?

    /// CSS `text-shadow`. Unlike SwiftUI's `.shadow(radius:)`, `blur` here maps 1:1 to the CSS blur.
    public struct Shadow {
        var color: UIColor
        var offset: CGSize
        var blur: CGFloat

        public init(color: Color, offset: CGSize, blur: CGFloat) {
            self.color = UIColor(color)
            self.offset = offset
            self.blur = blur
        }
    }

    /// Mirrors `dsFont`: family, weight, size, then the CSS line-height multiplier and em spacing.
    public init(
        _ text: String,
        _ family: DS.FontFamily,
        _ weight: DS.FontWeight,
        _ size: CGFloat,
        lineHeight: CGFloat,
        letterSpacing: CGFloat = 0,
        color: Color = DS.Palette.ink,
        alignment: TextAlignment = .leading,
        shadow: Shadow? = nil
    ) {
        self.text = text
        self.font = DS.uiFont(family, weight, size)
        self.lineHeight = size * lineHeight
        self.letterSpacing = letterSpacing * size
        self.color = UIColor(color)
        self.alignment = switch alignment {
        case .leading: .left
        case .center: .center
        case .trailing: .right
        }
        self.shadow = shadow
    }

    public func makeUIView(context: Context) -> UILabel {
        let label = UILabel()
        label.numberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        label.backgroundColor = .clear
        // Let SwiftUI decide the width; the label reports the height it needs for it.
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.setContentHuggingPriority(.defaultHigh, for: .vertical)
        return label
    }

    public func updateUIView(_ label: UILabel, context: Context) {
        label.attributedText = attributedText
        label.textAlignment = alignment
    }

    public func sizeThatFits(_ proposal: ProposedViewSize, uiView label: UILabel, context: Context) -> CGSize? {
        let proposed = proposal.width ?? .greatestFiniteMagnitude
        let width = proposed.isFinite ? proposed : .greatestFiniteMagnitude
        let fitted = label.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: min(width, fitted.width), height: fitted.height)
    }

    private var attributedText: NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = lineHeight
        paragraph.maximumLineHeight = lineHeight
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.alignment = alignment

        var attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph,
            // A forced line box shifts the glyphs inside it; this puts them back on the centre line.
            .baselineOffset: (lineHeight - font.lineHeight) / 4,
        ]

        if letterSpacing != 0 {
            attributes[.kern] = letterSpacing
        }

        if let shadow {
            let textShadow = NSShadow()
            textShadow.shadowColor = shadow.color
            textShadow.shadowOffset = shadow.offset
            textShadow.shadowBlurRadius = shadow.blur
            attributes[.shadow] = textShadow
        }

        return NSAttributedString(string: text, attributes: attributes)
    }
}
