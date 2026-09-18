import SwiftUI

/// Where the user is in the making of a video, as the screen around them knows it.
///
/// Set once, by the app, around whatever screen is showing. Every screen's back button reads it,
/// which is how the answer to "where am I" ends up in the one place on every screen that people
/// already look at when they feel lost: the top-left corner, next to the way back.
public struct DSJourneyContext {
    /// Stage names in order, already localised.
    public var stages: [String]
    /// The stage this screen belongs to. Nil for screens outside the main path, which show the
    /// map entry without a step count.
    public var current: Int?
    public var completed: Set<Int>
    public var onOpenMap: () -> Void

    public init(stages: [String], current: Int?, completed: Set<Int>, onOpenMap: @escaping () -> Void) {
        self.stages = stages
        self.current = current
        self.completed = completed
        self.onOpenMap = onOpenMap
    }
}

extension EnvironmentValues {
    @Entry public var dsJourney: DSJourneyContext? = nil
}

/// The way back, and the way to see where you are.
///
/// One capsule, two targets. The chevron goes back, exactly as the plain circle did. The stage
/// half — a progress ring and the stage's name — opens the journey map. Paired rather than
/// separated because they answer the same worry: a user who reaches for "back" is usually a user
/// who is not sure where they are.
///
/// Without a journey in the environment it draws the plain circle it replaces, so screens outside
/// the main path look exactly as they did.
public struct DSBackButton: View {
    private let size: CGFloat
    private let fontSize: CGFloat
    private let style: DSCircleButton.Style
    private let action: () -> Void

    @Environment(\.dsJourney) private var journey
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        size: CGFloat = 36,
        fontSize: CGFloat = 16,
        style: DSCircleButton.Style = .flat,
        action: @escaping () -> Void
    ) {
        self.size = size
        self.fontSize = fontSize
        self.style = style
        self.action = action
    }

    public var body: some View {
        if let journey {
            capsule(journey)
        } else {
            DSCircleButton("←", size: size, fontSize: fontSize, style: style, action: action)
        }
    }

    private func capsule(_ journey: DSJourneyContext) -> some View {
        let height = max(34, size)
        let progress = journey.current.map { Double($0 + 1) / Double(max(1, journey.stages.count)) } ?? 0

        return HStack(spacing: 0) {
            Button(action: action) {
                Image(systemName: "chevron.left")
                    .font(.system(size: fontSize - 2, weight: .semibold))
                    .foregroundStyle(DS.Palette.ink(0.9))
                    .frame(width: height, height: height)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.dsPressIcon)
            .accessibilityLabel(Text("Back"))

            Rectangle()
                .fill(DS.Palette.hairline(0.14))
                .frame(width: 1, height: height * 0.46)

            Button(action: journey.onOpenMap) {
                HStack(spacing: 6) {
                    ZStack {
                        Circle()
                            .stroke(DS.Palette.hairline(0.2), lineWidth: 2)
                        Circle()
                            .trim(from: 0, to: progress)
                            .stroke(DS.Palette.lime, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .animation(reduceMotion ? nil : DS.Motion.settle, value: progress)
                        if journey.current == nil {
                            Image(systemName: "map")
                                .font(.system(size: 7, weight: .bold))
                                .foregroundStyle(DS.Palette.ink(0.7))
                        }
                    }
                    .frame(width: 14, height: 14)

                    Text(journey.current.flatMap { journey.stages.indices.contains($0) ? journey.stages[$0] : nil } ?? "•••")
                        .dsFont(.sans, .semibold, 12)
                        .foregroundStyle(DS.Palette.ink(0.9))
                        .lineLimit(1)
                        .fixedSize()
                        .contentTransition(.opacity)

                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(DS.Palette.ink(0.56))
                }
                .padding(.leading, 9)
                .padding(.trailing, 11)
                .frame(height: height)
                .contentShape(Rectangle())
            }
            .buttonStyle(.dsPress(radius: height / 2))
        }
        .glassEffect(.regular.tint(DS.Palette.glass(0.25)).interactive(), in: .capsule)
        .fixedSize()
    }
}
