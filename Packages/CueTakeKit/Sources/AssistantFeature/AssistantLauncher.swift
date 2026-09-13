import DesignSystem
import SwiftUI

/// The assistant's orb, for use outside the assistant — beside the tab bar, in the journey map.
/// The same face everywhere, so it is recognised as the same someone.
public struct AssistantLauncherOrb: View {
    public init() {}

    public var body: some View {
        AssistantOrb(isThinking: false)
    }
}

/// The way into the assistant from the main tabs: a glass disc with the orb inside, sitting next
/// to the tab bar at the same height, so it reads as part of the app's navigation rather than as
/// a floating chat bubble bolted onto it.
public struct AssistantLauncherButton: View {
    private let action: () -> Void
    @State private var pressed = 0

    public init(action: @escaping () -> Void) {
        self.action = action
    }

    public var body: some View {
        Button {
            pressed += 1
            action()
        } label: {
            AssistantOrb(isThinking: false)
                .frame(width: 30, height: 30)
                .frame(width: 62, height: 62)
                .contentShape(Circle())
        }
        .buttonStyle(.dsPressIcon)
        .glassEffect(.regular.interactive(), in: .circle)
        .sensoryFeedback(.impact(weight: .light), trigger: pressed)
        .accessibilityLabel(Text("assistant.title", bundle: .module))
    }
}
