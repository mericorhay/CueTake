import SwiftUI

/// A screen that two phones meet on: the content, the light over it, and the card that comes out
/// of the light once they are joined.
///
/// The content steps back when the phones touch — a little smaller, a little darker — the way the
/// system does it, so the light reads as coming from in front of the screen rather than painted
/// on it.
public struct BumpStage<Content: View, Card: View>: View {
    public var phase: BumpPhase
    /// 0…1 as the other phone approaches; nil where it cannot be measured.
    public var closeness: Double?
    private let content: Content
    private let card: Card

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        phase: BumpPhase,
        closeness: Double? = nil,
        @ViewBuilder content: () -> Content,
        @ViewBuilder card: () -> Card
    ) {
        self.phase = phase
        self.closeness = closeness
        self.content = content()
        self.card = card()
    }

    public var body: some View {
        ZStack(alignment: .top) {
            content
                .scaleEffect(stepBack ? 0.96 : 1, anchor: .bottom)
                .brightness(stepBack ? -0.12 : 0)
                .blur(radius: stepBack && !reduceMotion ? 1.5 : 0)
                .animation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(duration: 0.55, bounce: 0.18), value: stepBack)

            BumpGlow(phase: phase, closeness: closeness)

            if phase == .connected {
                card
                    .padding(.top, 70)
                    .padding(.horizontal, 20)
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .asymmetric(
                                insertion: .scale(scale: 0.6, anchor: .top)
                                    .combined(with: .offset(y: -40))
                                    .combined(with: .opacity),
                                removal: .opacity
                            )
                    )
            }
        }
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(duration: 0.6, bounce: 0.25), value: phase)
    }

    private var stepBack: Bool {
        phase == .contact || phase == .connected
    }
}

/// A person arriving out of the light: their initials in a ring of the same colours.
public struct BumpPersonCard: View {
    public var name: String
    public var detail: String

    public init(name: String, detail: String) {
        self.name = name
        self.detail = detail
    }

    public var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(colors: [BumpGlow.core, BumpGlow.rim], startPoint: .top, endPoint: .bottom)
                    )
                Circle()
                    .fill(.black.opacity(0.55))
                    .padding(3)
                Text(verbatim: Self.initials(of: name))
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
            }
            .frame(width: 54, height: 54)

            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: name)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(verbatim: detail)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(.white.opacity(0.18), lineWidth: 1)
        }
        .environment(\.colorScheme, .dark)
    }

    /// One or two letters, never an empty circle.
    static func initials(of name: String) -> String {
        let words = name.split(whereSeparator: \.isWhitespace).prefix(2)
        let letters = words.compactMap { $0.first.map(String.init) }.joined()
        return letters.isEmpty ? "?" : letters.uppercased()
    }
}
