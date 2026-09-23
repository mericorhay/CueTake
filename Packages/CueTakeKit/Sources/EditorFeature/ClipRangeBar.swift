import DesignSystem
import Domain
import SwiftUI

/// Picks a stretch of one clip with two handles: where a tool starts and where it stops.
///
/// Opens on the whole clip, which is what a tool did before, so nothing changes for someone who
/// never touches the handles. The playhead is drawn on it, and a tap on either "here" button puts
/// that end where the playhead is — the same two moves the timeline's own trim uses.
struct ClipRangeBar: View {
    /// Seconds into the clip, on the finished video.
    @Binding var range: ClosedRange<Double>
    let length: Double
    /// Where the playhead is inside the clip, when it is inside it.
    let playhead: Double?
    let tint: Color

    @State private var dragging: Edge?
    @State private var origin: ClosedRange<Double>?

    private enum Edge { case start, end }

    static let minimum = 0.3

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { proxy in
                let width = max(proxy.size.width, 1)
                let x = { (seconds: Double) in CGFloat(seconds / max(length, 0.01)) * width }
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(DS.Palette.hairline(0.07))
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(tint.opacity(0.35))
                        .overlay {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(tint, lineWidth: 2)
                        }
                        .frame(width: max(x(range.upperBound) - x(range.lowerBound), 12))
                        .offset(x: x(range.lowerBound))

                    if let playhead {
                        Rectangle()
                            .fill(DS.Palette.ink)
                            .frame(width: 2)
                            .offset(x: x(playhead) - 1)
                            .allowsHitTesting(false)
                    }

                    handle(active: dragging == .start)
                        .offset(x: x(range.lowerBound) - 11)
                        .gesture(edgeDrag(.start, width: width))
                    handle(active: dragging == .end)
                        .offset(x: x(range.upperBound) - 11)
                        .gesture(edgeDrag(.end, width: width))
                }
            }
            .frame(height: 34)

            HStack(spacing: 6) {
                Text(verbatim: "\(MediaTime(seconds: range.lowerBound).preciseTimecode) – \(MediaTime(seconds: range.upperBound).preciseTimecode)")
                    .dsFont(.mono, .medium, 10)
                    .foregroundStyle(DS.Palette.ink(0.7))
                    .contentTransition(.numericText())
                Spacer(minLength: 0)
                if let playhead {
                    chip("editor.range.startHere", symbol: "arrow.right.to.line") {
                        range = min(playhead, range.upperBound - Self.minimum)...range.upperBound
                    }
                    chip("editor.range.endHere", symbol: "arrow.left.to.line") {
                        range = range.lowerBound...max(playhead, range.lowerBound + Self.minimum)
                    }
                }
                chip("editor.range.whole", symbol: "arrow.left.and.right") {
                    range = 0...length
                }
            }
        }
    }

    private func handle(active: Bool) -> some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(DS.Palette.ink)
            .frame(width: active ? 8 : 6, height: 34)
            .frame(width: 22, height: 44)
            .contentShape(Rectangle())
    }

    private func edgeDrag(_ edge: Edge, width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                if origin == nil { origin = range; dragging = edge }
                guard let origin else { return }
                let delta = Double(value.translation.width / width) * length
                switch edge {
                case .start:
                    let start = min(max(0, origin.lowerBound + delta), origin.upperBound - Self.minimum)
                    range = start...origin.upperBound
                case .end:
                    let end = max(min(length, origin.upperBound + delta), origin.lowerBound + Self.minimum)
                    range = origin.lowerBound...end
                }
            }
            .onEnded { _ in
                origin = nil
                dragging = nil
            }
    }

    private func chip(_ key: String.LocalizationValue, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(DS.Palette.ink(0.85))
                .frame(width: 30, height: 26)
                .background(Capsule().fill(DS.Palette.hairline(0.08)))
        }
        .buttonStyle(.dsPressIcon)
        .accessibilityLabel(Text(AppLocalization.string(key, bundle: .module)))
    }
}
