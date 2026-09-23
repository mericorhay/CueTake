import DesignSystem
import Domain
import Foundation
import SwiftUI
import UIKit

/// Card shown in the Recent rail and the Projects grid.
public struct LibraryItem: Identifiable, Hashable {
    public let id: UUID
    public var title: String
    public var meta: String
    public var duration: String
    /// The card's background, taken verbatim from the design. Recents and projects share tints
    /// but not their alphas, so each card carries its own fill rather than an index into a ramp.
    public var fill: CardFill
    /// Height used by the Projects grid.
    public var height: CGFloat
    /// Frames from the project's own clips. Shown instead of the fill when there is one.
    public var cover: UIImage?

    public init(
        id: UUID = UUID(),
        title: String,
        meta: String,
        duration: String,
        fill: CardFill,
        height: CGFloat = 200,
        cover: UIImage? = nil
    ) {
        self.cover = cover
        self.id = id
        self.title = title
        self.meta = meta
        self.duration = duration
        self.fill = fill
        self.height = height
    }
}

public enum CardFill: Hashable {
    case gradient(angle: Double, from: Color, to: Color)
    case solid(Color)

    @ViewBuilder
    var view: some View {
        switch self {
        case .gradient(let angle, let from, let to):
            DS.gradient(angle, [from, to])
        case .solid(let color):
            color
        }
    }
}

extension CardFill {
    /// The design's card fills, cycled by position.
    ///
    /// A library has any number of projects; the design drew three. Cycling keeps the rhythm the
    /// design established — warm, lime, neutral — however long the list gets, instead of inventing
    /// a colour per project or letting everything past the third one go grey.
    public static func ramp(at index: Int, alpha: Double = 0.35) -> CardFill {
        switch index % 3 {
        case 0: .gradient(angle: 165, from: DS.Palette.accent(alpha), to: Color(hex: 0x121216))
        case 1: .gradient(angle: 165, from: DS.Palette.lime(alpha * 0.63), to: Color(hex: 0x121216))
        default: .gradient(angle: 160, from: Color(hex: 0x141418), to: Color(hex: 0x0F0F12))
        }
    }
}

extension LibraryItem {
    /// The design's three recent cards, with their own fills.
    public static let sampleRecents: [LibraryItem] = [
        LibraryItem(
            title: "iPhone 17 Pro Max Camera",
            meta: "Edited 2h ago",
            duration: "0:30",
            fill: .gradient(angle: 165, from: DS.Palette.accent(0.35), to: Color(hex: 0x121216))
        ),
        LibraryItem(
            title: "Studio Light Setup",
            meta: "Yesterday",
            duration: "0:45",
            fill: .gradient(angle: 165, from: DS.Palette.lime(0.22), to: Color(hex: 0x121216))
        ),
        LibraryItem(
            title: "3 Editing Habits",
            meta: "Draft",
            duration: "1:02",
            fill: .gradient(angle: 160, from: Color(hex: 0x141418), to: Color(hex: 0x0F0F12))
        ),
    ]
}

public struct HomeScreen: View {
    private let recents: [LibraryItem]
    private let onCreate: () -> Void
    private let onOpenProject: (LibraryItem) -> Void
    private let onOpenAllProjects: () -> Void
    private let onOpenWorkflow: () -> Void
    private let onTeleprompter: () -> Void
    private let onSuflor: () -> Void

    public init(
        recents: [LibraryItem] = LibraryItem.sampleRecents,
        onCreate: @escaping () -> Void,
        onOpenProject: @escaping (LibraryItem) -> Void,
        onOpenAllProjects: @escaping () -> Void,
        onOpenWorkflow: @escaping () -> Void,
        onTeleprompter: @escaping () -> Void = {},
        onSuflor: @escaping () -> Void = {}
    ) {
        self.onTeleprompter = onTeleprompter
        self.onSuflor = onSuflor
        self.recents = recents
        self.onCreate = onCreate
        self.onOpenProject = onOpenProject
        self.onOpenAllProjects = onOpenAllProjects
        self.onOpenWorkflow = onOpenWorkflow
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                createCard
                teleprompterCard
                suflorCard
                recentSection
                workflowSection
            }
            .padding(.top, 64)
            .padding(.bottom, 108)
        }
        .scrollIndicators(.hidden)
        .dsScreenLayout(scrolls: true)
        .background(DS.Palette.screen)
        .dsEnter(.screen())
    }

    // MARK: - Header

    private var header: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 0) {
                    DSKicker(
                        greetingStamp(at: context.date),
                        size: 11,
                        tracking: 0.14,
                        color: DS.Palette.ink(0.56)
                    )
                    DSHeadline(greetingTitle, size: 34)
                        .padding(.top, 10)
                }

                Spacer(minLength: 0)

                DSBrandMark(height: 30)
                    .padding(.top, 24)
            }
        }
        .padding(.horizontal, 22)
    }

    private var greetingTitle: String {
        AppLocalization.string("home.greeting.title.anonymous", bundle: .module)
    }

    private func greetingStamp(at date: Date) -> String {
        let locale = AppLocalization.locale
        let weekday = date.formatted(Date.FormatStyle().weekday(.wide).locale(locale)).uppercased(with: locale)
        let time = date.formatted(Date.FormatStyle().hour().minute().locale(locale))
        return "\(weekday) · \(time)"
    }

    // MARK: - Create

    private var createCard: some View {
        Button(action: onCreate) {
            ZStack(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 0) {
                    DSKicker(
                        AppLocalization.string("home.create.kicker", bundle: .module),
                        size: 10,
                        tracking: 0.18,
                        color: DS.Palette.inkInverse(0.6)
                    )
                    DSHeadline(
                        AppLocalization.string("home.create.title", bundle: .module),
                        size: 30,
                        color: DS.Palette.inkInverse
                    )
                    .padding(.top, 38)
                    Text("home.create.subtitle", bundle: .module)
                        .dsFont(.sans, .regular, 13)
                        .foregroundStyle(DS.Palette.inkInverse(0.66))
                        .padding(.top, 6)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(24)
            // The sheen sits between the fill and the text, as it does in the design.
            .background {
                ZStack {
                    DS.gradient(150, [DS.Palette.accent, DS.Palette.accentWarm])
                    SweepShine()
                }
            }
            .overlay(alignment: .bottomTrailing) {
                Text("→")
                    .font(.system(size: 20))
                    .foregroundStyle(DS.Palette.accent)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(DS.Palette.inkInverse))
                    .padding(22)
                    .accessibilityHidden(true)
            }
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.hero, style: .continuous))
            .shadow(color: DS.Palette.accent(0.32), radius: 30, y: 24)
        }
        .buttonStyle(.dsPressCard)
        .padding(.horizontal, 22)
        .padding(.top, 26)
    }

    // MARK: - Teleprompter

    /// Straight to reading: paste or type the words, then the camera. For people who already know
    /// what they will say and want nothing between them and the take.
    private var teleprompterCard: some View {
        Button(action: onTeleprompter) {
            HStack(spacing: 14) {
                Image(systemName: "text.viewfinder")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(DS.Palette.inkInverse)
                    .frame(width: 46, height: 46)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(DS.Palette.lime))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text("home.teleprompter.title", bundle: .module)
                        .dsFont(.sans, .semibold, 16)
                        .foregroundStyle(DS.Palette.ink)
                    Text("home.teleprompter.subtitle", bundle: .module)
                        .dsFont(.sans, .regular, 13)
                        .foregroundStyle(DS.Palette.ink(0.6))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DS.Palette.ink(0.52))
                    .accessibilityHidden(true)
            }
            .padding(14)
            .frame(minHeight: 44)
            .dsCard(radius: 20)
        }
        .buttonStyle(.dsPressCard)
        .accessibilityHint(Text("home.teleprompter.hint", bundle: .module))
        .padding(.horizontal, 22)
        .padding(.top, 12)
    }

    // MARK: - Suflör

    /// The prompter for a live stream on another app: it floats in the corner of TikTok or
    /// Instagram and rolls the brand's lines at the speaker's pace.
    private var suflorCard: some View {
        Button(action: onSuflor) {
            HStack(spacing: 14) {
                SuflorMiniWindow()
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 7) {
                        Text("home.suflor.title", bundle: .module)
                            .dsFont(.sans, .semibold, 16)
                            .foregroundStyle(DS.Palette.ink)
                        Text("home.suflor.badge", bundle: .module)
                            .dsFont(.mono, .medium, 9, letterSpacing: 0.14)
                            .foregroundStyle(DS.Palette.inkInverse)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(DS.Palette.accent))
                    }
                    Text("home.suflor.subtitle", bundle: .module)
                        .dsFont(.sans, .regular, 13)
                        .foregroundStyle(DS.Palette.ink(0.6))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DS.Palette.ink(0.52))
                    .accessibilityHidden(true)
            }
            .padding(14)
            .frame(minHeight: 44)
            .dsCard(radius: 20)
        }
        .buttonStyle(.dsPressCard)
        .accessibilityHint(Text("home.suflor.hint", bundle: .module))
        .padding(.horizontal, 22)
        .padding(.top, 10)
    }

    // MARK: - Recent

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                sectionLabel(AppLocalization.string("home.section.recent", bundle: .module))
                Spacer(minLength: 0)
                Button(action: onOpenAllProjects) {
                    Text("home.recent.all", bundle: .module)
                        .dsFont(.sans, .medium, 13)
                        .foregroundStyle(DS.Palette.accent)
                }
                .buttonStyle(.dsPress)
            }
            .padding(.horizontal, 22)
            .padding(.top, 32)
            .padding(.bottom, 12)

            if recents.isEmpty {
                LibraryEmptyState(
                    message: AppLocalization.string("home.empty", bundle: .module),
                    action: AppLocalization.string("home.empty.action", bundle: .module),
                    onTap: onCreate
                )
                .padding(.horizontal, 22)
            }

            ScrollView(.horizontal) {
                HStack(spacing: 13) {
                    ForEach(recents) { item in
                        Button {
                            onOpenProject(item)
                        } label: {
                            recentCard(item)
                        }
                        .buttonStyle(.dsPressCard)
                    }
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 4)
            }
            .scrollIndicators(.hidden)
        }
    }

    private func recentCard(_ item: LibraryItem) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Spacer(minLength: 0)
            // line-height:1.15 is tighter than the font's leading, so this one wraps through UILabel.
            TightText(item.title, .archivo, .bold, 15, lineHeight: 1.15)
            Text(item.meta)
                .dsFont(.sans, .regular, 11)
                .foregroundStyle(DS.Palette.ink(0.5))
        }
        .padding(13)
        .frame(width: 158, height: 210, alignment: .bottomLeading)
        .background { LibraryCardBackground(item: item) }
        .overlay(alignment: .topLeading) {
            durationChip(item.duration)
                .padding(11)
        }
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
    }

    private func durationChip(_ text: String) -> some View {
        Text(text)
            .dsFont(.mono, .medium, 10, letterSpacing: 0.1)
            .foregroundStyle(DS.Palette.ink)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .dsGlass(
                tint: DS.Palette.inkInverse(0.5),
                in: RoundedRectangle(cornerRadius: DS.Radius.xs, style: .continuous),
                border: nil
            )
    }

    // MARK: - Workflows

    private var workflowSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel(AppLocalization.string("home.section.workflows", bundle: .module))

            Button(action: onOpenWorkflow) {
                HStack(spacing: 13) {
                    Text("PR")
                        .accessibilityHidden(true)
                        .dsFont(.archivo, .bold, 13)
                        .foregroundStyle(DS.Palette.inkInverse)
                        .frame(width: 34, height: 34)
                        .background(
                            RoundedRectangle(cornerRadius: DS.Radius.s, style: .continuous)
                                .fill(DS.Palette.lime)
                        )

                    VStack(alignment: .leading, spacing: 3) {
                        Text("home.workflow.name", bundle: .module)
                            .dsFont(.sans, .semibold, 14)
                            .foregroundStyle(DS.Palette.ink)
                        Text("home.workflow.meta", bundle: .module)
                            .dsFont(.mono, .medium, 11)
                            .foregroundStyle(DS.Palette.ink(0.56))
                    }

                    Spacer(minLength: 0)

                    Text("›")
                        .font(.system(size: 17))
                        .foregroundStyle(DS.Palette.ink(0.52))
                        .accessibilityHidden(true)
                }
                .padding(15)
                .dsCard(radius: 18)
            }
            .buttonStyle(.dsPress)
        }
        .padding(.horizontal, 22)
        .padding(.top, 30)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .dsFont(.sans, .semibold, 13, letterSpacing: 0.12)
            .foregroundStyle(DS.Palette.ink(0.56))
    }
}

/// A card's picture: the project's cover as it is, with a shade along the bottom only so the title
/// stays readable; the design's tint when there is no footage yet.
struct LibraryCardBackground: View {
    let item: LibraryItem

    var body: some View {
        if let cover = item.cover {
            Color.clear
                .overlay {
                    Image(uiImage: cover)
                        .resizable()
                        .scaledToFill()
                }
                .clipped()
                .overlay(alignment: .bottom) {
                    LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .top, endPoint: .bottom)
                        .frame(height: 90)
                }
                .transition(.opacity)
        } else {
            item.fill.view
        }
    }
}

/// A tiny floating window with lines rolling up through it and a live dot breathing: the suflör
/// explained without a word.
private struct SuflorMiniWindow: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let widths: [CGFloat] = [24, 30, 18, 28, 22, 32, 16, 26]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 11, style: .continuous).fill(DS.Palette.screen)
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(widths.indices, id: \.self) { index in
                        Capsule()
                            .fill(index % 3 == 1 ? DS.Palette.lime : DS.Palette.ink(0.8))
                            .frame(width: widths[index], height: 3)
                    }
                }
                .padding(.leading, 7)
                .offset(y: 30 - CGFloat((t * 7).truncatingRemainder(dividingBy: 28)))
                Circle()
                    .fill(DS.Palette.accent)
                    .frame(width: 5, height: 5)
                    .opacity(0.5 + 0.5 * abs(sin(t * .pi)))
                    .offset(x: 34, y: 5)
            }
            .frame(width: 46, height: 60)
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(DS.Palette.lime(0.35), lineWidth: 1))
            .offset(y: reduceMotion ? 0 : CGFloat(sin(t * 1.3)) * 1.5)
        }
        .frame(width: 46, height: 60)
    }
}
