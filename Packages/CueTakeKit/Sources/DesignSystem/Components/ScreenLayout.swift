import SwiftUI

extension DS {
    /// The frame the design is drawn on: an iPhone 16 Pro screen, 402x874.
    ///
    /// Every measurement in the design file is authored against these numbers, which is why they
    /// belong here rather than in a screen. Nothing should read them to *scale* a layout — the
    /// design's points are points. They exist so a rotated phone can keep the same composition
    /// instead of compressing it.
    public enum Layout {
        public static let column: CGFloat = 402
        public static let page: CGFloat = 874
    }
}

/// Keeps a portrait-authored screen usable when the phone is rotated.
///
/// The design specifies one composition, laid out down an 874pt page. Landscape gives that
/// composition 402pt of height, so something has to give. The two obvious options are both bad:
/// squeezing the layout breaks every spacing decision in the design, and re-flowing it into columns
/// invents a second design that nobody drew.
///
/// So this does neither. In landscape the screen keeps its exact portrait geometry — same widths,
/// same paddings, same vertical rhythm — and becomes a centred column that scrolls. The design is
/// never contradicted; it is just taller than the window, which is a thing pages are allowed to be.
///
/// In portrait the modifier is a no-op, so fidelity where the design *does* apply is untouched.
public struct DSScreenLayout: ViewModifier {
    /// True for screens that already scroll themselves. Nesting a second scroll view inside one of
    /// those would fight the first for the gesture, so those only get the width treatment.
    private let scrolls: Bool

    public init(scrolls: Bool) {
        self.scrolls = scrolls
    }

    public func body(content: Content) -> some View {
        GeometryReader { proxy in
            let isLandscape = proxy.size.width > proxy.size.height
            // Wider than the portrait design in landscape, so a rotated phone is used rather than
            // shown a phone-shaped strip in the middle of it. The notch side keeps its margin.
            let column = isLandscape ? min(proxy.size.width - 88, 760) : min(proxy.size.width, DS.Layout.column)

            if !isLandscape {
                content.frame(width: proxy.size.width, height: proxy.size.height)
            } else if scrolls {
                content
                    .frame(width: column, height: proxy.size.height)
                    .frame(width: proxy.size.width)
            } else {
                ScrollView(.vertical) {
                    content
                        .frame(width: column)
                        .frame(minHeight: DS.Layout.page, alignment: .top)
                }
                .scrollIndicators(.hidden)
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
        }
    }
}

extension View {
    /// Applies the landscape treatment. Put it immediately inside the screen's background so the
    /// colour still fills the window rather than just the column.
    ///
    /// - Parameter scrolls: pass `true` when the screen already wraps its content in a `ScrollView`.
    public func dsScreenLayout(scrolls: Bool = false) -> some View {
        modifier(DSScreenLayout(scrolls: scrolls))
    }
}
