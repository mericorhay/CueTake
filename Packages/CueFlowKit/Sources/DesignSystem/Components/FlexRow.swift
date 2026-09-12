import SwiftUI

/// A row that splits its width by weight, the way CSS `flex-grow` does.
///
/// The design pairs buttons at uneven ratios — `flex:1` next to `flex:1.4` on the blueprint
/// footer, `flex:1` next to `flex:1.3` on the retake compare. SwiftUI has no built-in equivalent
/// (`layoutPriority` changes who gets squeezed, not the ratio), so the split is done here.
public struct FlexRow: Layout {
    private let spacing: CGFloat
    private let weights: [CGFloat]

    public init(spacing: CGFloat, weights: [CGFloat]) {
        self.spacing = spacing
        self.weights = weights
    }

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? widths(in: .infinity, count: subviews.count).reduce(0, +)
        let heights = zip(subviews, widths(in: width, count: subviews.count)).map { subview, width in
            subview.sizeThatFits(ProposedViewSize(width: width, height: proposal.height)).height
        }
        return CGSize(width: width, height: heights.max() ?? 0)
    }

    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        for (index, width) in widths(in: bounds.width, count: subviews.count).enumerated() {
            subviews[index].place(
                at: CGPoint(x: x, y: bounds.minY),
                proposal: ProposedViewSize(width: width, height: bounds.height)
            )
            x += width + spacing
        }
    }

    private func widths(in total: CGFloat, count: Int) -> [CGFloat] {
        guard count > 0 else { return [] }
        let resolved = (0..<count).map { index in
            weights.indices.contains(index) ? max(0, weights[index]) : 1
        }
        let sum = max(0.0001, resolved.reduce(0, +))
        let usable = max(0, total - spacing * CGFloat(count - 1))
        return resolved.map { usable * $0 / sum }
    }
}
