import SwiftUI

/// The design's styled range input: a 3px track at rgba(255,255,255,.18) with a 15px round thumb.
/// SwiftUI's stock `Slider` cannot be shaped like this, so it is rebuilt here.
public struct DSSlider: View {
    @Binding private var value: Double
    private let range: ClosedRange<Double>
    private let step: Double?

    private static let trackHeight: CGFloat = 3
    private static let thumbSize: CGFloat = 15

    public init(value: Binding<Double>, in range: ClosedRange<Double>, step: Double? = nil) {
        self._value = value
        self.range = range
        self.step = step
    }

    public var body: some View {
        GeometryReader { proxy in
            let usable = max(1, proxy.size.width - Self.thumbSize)
            let span = range.upperBound - range.lowerBound
            let fraction = span == 0 ? 0 : (value - range.lowerBound) / span

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(DS.Palette.hairline(0.18))
                    .frame(height: Self.trackHeight)

                Circle()
                    .fill(DS.Palette.ink)
                    .frame(width: Self.thumbSize, height: Self.thumbSize)
                    .shadow(color: .black.opacity(0.6), radius: 4, y: 2)
                    .offset(x: usable * fraction)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        let x = min(max(0, gesture.location.x - Self.thumbSize / 2), usable)
                        update(to: range.lowerBound + (x / usable) * span)
                    }
            )
        }
        .frame(height: Self.thumbSize)
    }

    private func update(to raw: Double) {
        guard let step else {
            value = min(max(range.lowerBound, raw), range.upperBound)
            return
        }
        let stepped = (raw / step).rounded() * step
        value = min(max(range.lowerBound, stepped), range.upperBound)
    }
}
