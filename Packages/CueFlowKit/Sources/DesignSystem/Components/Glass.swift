import SwiftUI

// The design's panels are rgba(20,20,24,.55) plus backdrop-filter: blur(20px).
// SwiftUI's only real backdrop blur is Material, which carries its own tint, so the exact rgba is
// layered on top of it. This is the closest match available without snapshotting the backdrop.
private struct GlassBackground: ViewModifier {
    let tint: Color
    let shape: AnyShape
    let border: Color?
    let borderWidth: CGFloat

    func body(content: Content) -> some View {
        content
            .background {
                shape
                    .fill(.ultraThinMaterial)
                    .overlay(shape.fill(tint))
            }
            .overlay {
                if let border {
                    shape.stroke(border, lineWidth: borderWidth)
                }
            }
            .clipShape(shape)
    }
}

extension View {
    /// Translucent panel with a hairline border, as used by every floating control in the design.
    public func dsGlass(
        tint: Color = DS.Palette.glass(0.55),
        in shape: some Shape = RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous),
        border: Color? = DS.Palette.hairline(0.12),
        borderWidth: CGFloat = 1
    ) -> some View {
        modifier(GlassBackground(tint: tint, shape: AnyShape(shape), border: border, borderWidth: borderWidth))
    }

    /// Solid card: background #131317 with a 1px rgba(255,255,255,.07) border.
    public func dsCard(
        fill: Color = DS.Palette.surface,
        radius: CGFloat = DS.Radius.card,
        border: Color? = DS.Palette.hairline(0.07)
    ) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return self
            .background(shape.fill(fill))
            .overlay {
                if let border {
                    shape.stroke(border, lineWidth: 1)
                }
            }
            .clipShape(shape)
    }
}
