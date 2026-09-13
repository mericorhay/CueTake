import DesignSystem
import SwiftUI

/// Entry points into a new video. Four 3D cards; the first one is the accent card.
public struct CreateScreen: View {
    public enum Destination: Hashable, Sendable {
        /// Footage the user already has. First, and the accent card: it is the only entry point
        /// that asks nothing of them — no idea, no script, no change to how they shoot.
        case importFootage
        case prompt
        case script
        case workflow
        case studio
    }

    private let onBack: () -> Void
    private let onSelect: (Destination) -> Void

    public init(onBack: @escaping () -> Void, onSelect: @escaping (Destination) -> Void) {
        self.onBack = onBack
        self.onSelect = onSelect
    }

    private struct Card {
        var titleKey: String.LocalizationValue
        var subtitleKey: String.LocalizationValue
        var mark: String
        var destination: Destination
        var isAccent: Bool
        var chipFill: Color
        var chipInk: Color
    }

    private var cards: [Card] {
        [
            Card(
                titleKey: "create.import.title",
                subtitleKey: "create.import.subtitle",
                mark: "↑",
                destination: .importFootage,
                isAccent: true,
                chipFill: DS.Palette.inkInverse,
                chipInk: DS.Palette.accent
            ),
            Card(
                titleKey: "create.idea.title",
                subtitleKey: "create.idea.subtitle",
                mark: "AI",
                destination: .prompt,
                isAccent: false,
                chipFill: DS.Palette.hairline(0.1),
                chipInk: DS.Palette.accent
            ),
            Card(
                titleKey: "create.script.title",
                subtitleKey: "create.script.subtitle",
                mark: "TX",
                destination: .script,
                isAccent: false,
                chipFill: DS.Palette.hairline(0.1),
                chipInk: DS.Palette.ink
            ),
            Card(
                titleKey: "create.workflow.title",
                subtitleKey: "create.workflow.subtitle",
                mark: "WF",
                destination: .workflow,
                isAccent: false,
                chipFill: DS.Palette.lime,
                chipInk: DS.Palette.inkInverse
            ),
            Card(
                titleKey: "create.record.title",
                subtitleKey: "create.record.subtitle",
                mark: "●",
                destination: .studio,
                isAccent: false,
                chipFill: DS.Palette.accent(0.18),
                chipInk: DS.Palette.accent
            ),
        ]
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DSBackButton(action: onBack)

            DSHeadline(String(localized: "create.title", bundle: .module), size: 36, lineHeight: 0.98)
                .padding(.top, 22)
                .padding(.bottom, 6)

            Text("create.subtitle", bundle: .module)
                .dsFont(.sans, .regular, 14)
                .foregroundStyle(DS.Palette.ink(0.45))

            VStack(spacing: 13) {
                ForEach(Array(cards.enumerated()), id: \.offset) { index, card in
                    button(for: card, index: index)
                }
            }
            .frame(maxHeight: .infinity)
            .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 22)
        .padding(.top, 64)
        .padding(.bottom, 40)
        .dsScreenLayout()
        .background(DS.Palette.screen)
        .dsEnter(.screen())
    }

    private func button(for card: Card, index: Int) -> some View {
        let ink = card.isAccent ? DS.Palette.inkInverse : DS.Palette.ink
        let subInk = card.isAccent ? DS.Palette.inkInverse(0.6) : DS.Palette.ink(0.45)

        return Button {
            onSelect(card.destination)
        } label: {
            HStack(spacing: 14) {
                Text(card.mark)
                    .dsFont(.archivo, .bold, 15)
                    .foregroundStyle(card.chipInk)
                    .frame(width: 42, height: 42)
                    .background(
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .fill(card.chipFill)
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: card.titleKey, bundle: .module))
                        .dsFont(.archivo, .bold, 17)
                        .foregroundStyle(ink)
                    Text(String(localized: card.subtitleKey, bundle: .module))
                        .dsFont(.sans, .regular, 12)
                        .foregroundStyle(subInk)
                }

                Spacer(minLength: 0)

                Text("›")
                    .font(.system(size: 17))
                    .foregroundStyle(subInk)
            }
            .multilineTextAlignment(.leading)
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.cardLarge, style: .continuous)
                    .fill(card.isAccent ? DS.Palette.accent : DS.Palette.surfaceRaised)
            )
            .overlay {
                RoundedRectangle(cornerRadius: DS.Radius.cardLarge, style: .continuous)
                    .stroke(card.isAccent ? .clear : DS.Palette.hairline(0.08), lineWidth: 1)
            }
            .shadow(color: card.isAccent ? DS.Palette.accent(0.3) : .clear, radius: 25, y: 20)
        }
        .buttonStyle(.dsPressCard)
        .dsEnter(.slab(duration: 0.55, delay: Double(index) * 0.07))
    }
}
