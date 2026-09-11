import SwiftUI

/// Stand-in for screens that are not built yet.
public struct PlaceholderScreen<Actions: View>: View {
    private let title: Text
    private let message: Text
    private let systemImage: String
    private let actions: Actions

    public init(title: Text, message: Text, systemImage: String, @ViewBuilder actions: () -> Actions) {
        self.title = title
        self.message = message
        self.systemImage = systemImage
        self.actions = actions()
    }

    public var body: some View {
        VStack(spacing: Spacing.xl) {
            Spacer()
            Image(systemName: systemImage)
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(Palette.accent)
            VStack(spacing: Spacing.s) {
                title
                    .font(.cfTitle)
                    .foregroundStyle(Palette.textPrimary)
                message
                    .font(.cfBody)
                    .foregroundStyle(Palette.textSecondary)
                    .multilineTextAlignment(.center)
            }
            Text("common.comingSoon", bundle: .module)
                .font(.cfCaption)
                .foregroundStyle(Palette.textPrimary)
                .padding(.horizontal, Spacing.m)
                .padding(.vertical, Spacing.xs)
                .glassEffect()
            Spacer()
            actions
        }
        .padding(Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.background)
    }
}

extension PlaceholderScreen where Actions == EmptyView {
    public init(title: Text, message: Text, systemImage: String) {
        self.init(title: title, message: message, systemImage: systemImage) { EmptyView() }
    }
}
