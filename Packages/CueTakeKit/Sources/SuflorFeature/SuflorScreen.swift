import DesignSystem
import SwiftUI

/// An ad, whole: the brief and the cards, and after the take the report.
public struct SuflorScreen: View {
    @Bindable var model: SuflorModel
    let onClose: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(model: SuflorModel, onClose: @escaping () -> Void) {
        self.model = model
        self.onClose = onClose
    }

    public var body: some View {
        ZStack {
            DS.Palette.screen.ignoresSafeArea()
            switch model.stage {
            case .setup:
                SuflorSetupView(model: model, onClose: onClose)
                    .transition(.opacity)
            case .report:
                SuflorReportView(model: model) {
                    model.leaveReport()
                    onClose()
                }
                .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? .easeOut(duration: 0.2) : DS.Motion.settle, value: model.stage)
        .dynamicTypeSize(...DS.largestTextSize)
    }
}
