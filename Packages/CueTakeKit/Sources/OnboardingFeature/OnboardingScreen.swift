import DesignSystem
import SwiftUI

/// Three pages, each with the stacked idea → blueprint → video cards.
public struct OnboardingScreen: View {
    @State private var page = 0
    private let onFinish: () -> Void

    public init(onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
    }

    private struct Page {
        var headline: String.LocalizationValue
        var subtitle: String.LocalizationValue
        var cta: String.LocalizationValue
    }

    private static let pages: [Page] = [
        Page(headline: "onboarding.1.title", subtitle: "onboarding.1.subtitle", cta: "onboarding.next"),
        Page(headline: "onboarding.2.title", subtitle: "onboarding.2.subtitle", cta: "onboarding.next"),
        Page(headline: "onboarding.3.title", subtitle: "onboarding.3.subtitle", cta: "onboarding.start"),
    ]

    private var current: Page { Self.pages[min(page, Self.pages.count - 1)] }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            brand

            VStack(alignment: .leading, spacing: 0) {
                cardStack
                    .frame(height: 250)
                    .padding(.bottom, 34)

                DSHeadline(
                    String(localized: current.headline, bundle: .module),
                    size: 44,
                    lineHeight: 0.95,
                    letterSpacing: -0.035
                )

                Text(String(localized: current.subtitle, bundle: .module))
                    .dsFont(.sans, .regular, 15, lineHeight: 1.5)
                    .foregroundStyle(DS.Palette.ink(0.52))
                    .frame(maxWidth: 290, alignment: .leading)
                    .padding(.top, 16)
            }
            .frame(maxHeight: .infinity)

            dots
                .padding(.bottom, 22)

            HStack(spacing: 12) {
                Button(action: onFinish) {
                    Text("onboarding.skip", bundle: .module)
                        .dsFont(.sans, .medium, 14)
                        .foregroundStyle(DS.Palette.ink(0.42))
                        .padding(.vertical, 14)
                        .padding(.horizontal, 4)
                        // Text alone hit-tests on its glyphs; this hands the padding over too.
                        .contentShape(Rectangle())
                }
                .buttonStyle(.dsPress)

                DSPrimaryButton(
                    String(localized: current.cta, bundle: .module),
                    radius: DS.Radius.cardLarge,
                    verticalPadding: 18,
                    fontSize: 16
                ) {
                    if page >= Self.pages.count - 1 {
                        onFinish()
                    } else {
                        withAnimation(DS.Easing.standard(0.4)) { page += 1 }
                    }
                }
            }
        }
        .padding(.horizontal, 26)
        .padding(.top, 78)
        .padding(.bottom, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .dsScreenLayout()
        .background {
            DS.Palette.screen
                .overlay(alignment: .topTrailing) {
                    // The accent bloom bleeding off the top-right corner.
                    Circle()
                        .fill(
                            // radial-gradient(circle, rgba(255,90,79,.4), transparent 65%) —
                            // the stop matters: spreading the fade over the whole radius
                            // leaves a visible haze where the design has none.
                            RadialGradient(
                                stops: [
                                    .init(color: DS.Palette.accent(0.4), location: 0),
                                    .init(color: .clear, location: 0.65),
                                ],
                                center: .center,
                                startRadius: 0,
                                endRadius: 140
                            )
                        )
                        .frame(width: 280, height: 280)
                        .blur(radius: 10)
                        .offset(x: 70, y: -90)
                }
                .clipped()
                .ignoresSafeArea()
        }
        .dsEnter(.screen(duration: 0.5))
    }

    private var brand: some View {
        DSBrandLockup(size: 17)
    }

    private struct StackCard {
        var kicker: String.LocalizationValue
        var title: String.LocalizationValue
        var fill: Color
        var x: CGFloat
        var y: CGFloat
        var rotation: Double
        var scale: CGFloat
    }

    /// The deck is fixed, so it is built once rather than on every `body` evaluation.
    private static let stackCards: [StackCard] = [
        StackCard(kicker: "onboarding.card.idea", title: "onboarding.card.idea.value", fill: DS.Palette.ink, x: -14, y: 0, rotation: -7, scale: 0.9),
        StackCard(kicker: "onboarding.card.blueprint", title: "onboarding.card.blueprint.value", fill: DS.Palette.lime, x: 14, y: 58, rotation: 4, scale: 0.95),
        StackCard(kicker: "onboarding.card.video", title: "onboarding.card.video.value", fill: DS.Palette.accent, x: -6, y: 120, rotation: -2, scale: 1),
    ]

    private var cardStack: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(Self.stackCards.enumerated()), id: \.offset) { index, card in
                VStack(alignment: .leading, spacing: 8) {
                    Text(String(localized: card.kicker, bundle: .module))
                        .dsFont(.mono, .medium, 10, letterSpacing: 0.16)
                        .foregroundStyle(DS.Palette.inkInverse)
                        .opacity(0.65)
                        .lineLimit(1)
                    // The deck overlaps by design and only reads while every card is one line
                    // tall. A title that wraps swallows the card beneath it, so it shrinks
                    // instead — the geometry stays identical in both languages.
                    TightText(
                        String(localized: card.title, bundle: .module),
                        .archivo,
                        .bold,
                        19,
                        lineHeight: 1.2,
                        color: DS.Palette.inkInverse,
                        lineLimit: 1,
                        minimumScaleFactor: 0.7
                    )
                }
                .frame(width: 250, alignment: .leading)
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                        .fill(card.fill)
                )
                .shadow(color: .black.opacity(0.6), radius: 30, y: 24)
                .scaleEffect(card.scale)
                .rotationEffect(.degrees(card.rotation))
                .offset(x: 28 + card.x, y: card.y)
                .dsEnter(.slab(duration: 0.7, delay: Double(index) * 0.12))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var dots: some View {
        HStack(spacing: 8) {
            ForEach(0..<Self.pages.count, id: \.self) { index in
                Capsule()
                    .fill(index == page ? DS.Palette.accent : DS.Palette.ink(0.2))
                    .frame(width: index == page ? 24 : 6, height: 6)
            }
        }
        .animation(DS.Easing.standard(0.4), value: page)
    }
}
