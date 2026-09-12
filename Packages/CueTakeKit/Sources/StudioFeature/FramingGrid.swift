import DesignSystem
import SwiftUI

/// Rule-of-thirds guides over the preview.
///
/// Two hairlines each way, not a 3x3 box: the lines are the tool — you put your eyes on the upper
/// third and the frame stops looking like a passport photo — and a border would only add clutter
/// around an edge the viewfinder already has.
struct FramingGrid: View {
    /// Drawn rather than faded: the lines extend from the centre outward, a fraction apart, so the
    /// grid arrives as an instrument being placed over the frame instead of a layer switching on.
    @State private var drawn = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height

            ZStack {
                ForEach(1..<3) { column in
                    Rectangle()
                        .fill(DS.Palette.ink(0.18))
                        .frame(width: 0.5, height: drawn ? height : 0)
                        .offset(x: width * CGFloat(column) / 3 - width / 2)
                        .animation(
                            reduceMotion ? .easeOut(duration: 0.15)
                                : DS.Motion.settle.delay(Double(column - 1) * 0.05),
                            value: drawn
                        )
                }

                ForEach(1..<3) { row in
                    Rectangle()
                        .fill(DS.Palette.ink(0.18))
                        .frame(width: drawn ? width : 0, height: 0.5)
                        .offset(y: height * CGFloat(row) / 3 - height / 2)
                        .animation(
                            reduceMotion ? .easeOut(duration: 0.15)
                                : DS.Motion.settle.delay(0.1 + Double(row - 1) * 0.05),
                            value: drawn
                        )
                }
            }
            .frame(width: width, height: height)
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
        .onAppear { drawn = true }
    }
}
