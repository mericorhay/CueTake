import DesignSystem
import SwiftUI

/// Rule-of-thirds guides over the preview.
///
/// Two hairlines each way, not a 3x3 box: the lines are the tool — you put your eyes on the upper
/// third and the frame stops looking like a passport photo — and a border would only add clutter
/// around an edge the viewfinder already has.
struct FramingGrid: View {
    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height

            ZStack {
                ForEach(1..<3) { column in
                    Rectangle()
                        .fill(DS.Palette.ink(0.18))
                        .frame(width: 0.5)
                        .offset(x: width * CGFloat(column) / 3 - width / 2)
                }

                ForEach(1..<3) { row in
                    Rectangle()
                        .fill(DS.Palette.ink(0.18))
                        .frame(height: 0.5)
                        .offset(y: height * CGFloat(row) / 3 - height / 2)
                }
            }
            .frame(width: width, height: height)
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }
}
