import DesignSystem
import SwiftUI

/// The studio's control cluster. The design moves it on rotation:
/// portrait lays it across the bottom (`space-between`, 34pt inset, 30pt from the bottom);
/// landscape stacks it in a 96pt column on the right, bottom-up, 18pt apart.
struct StudioControlCluster<Leading: View, Center: View, Trailing: View>: View {
    let isLandscape: Bool
    @ViewBuilder let leading: Leading
    @ViewBuilder let center: Center
    @ViewBuilder let trailing: Trailing

    var body: some View {
        if isLandscape {
            VStack(spacing: 18) {
                trailing
                center
                leading
            }
            .frame(width: 96)
            .frame(maxHeight: .infinity, alignment: .center)
            .padding(.trailing, 18)
            .frame(maxWidth: .infinity, alignment: .trailing)
        } else {
            HStack {
                leading
                Spacer(minLength: 0)
                center
                Spacer(minLength: 0)
                trailing
            }
            .padding(.horizontal, 34)
            .padding(.bottom, 30)
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
    }
}

extension View {
    /// Top bar insets, which the design also swaps on rotation.
    func studioTopBarInsets(isLandscape: Bool) -> some View {
        padding(.horizontal, isLandscape ? 22 : 18)
            .padding(.top, isLandscape ? 16 : 56)
            .frame(maxHeight: .infinity, alignment: .top)
    }
}
