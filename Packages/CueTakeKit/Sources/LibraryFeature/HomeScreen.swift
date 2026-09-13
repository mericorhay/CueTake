import DesignSystem
import Domain
import SwiftUI

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

    public init(
        id: UUID = UUID(),
        title: String,
        meta: String,
        duration: String,
        fill: CardFill,
        height: CGFloat = 200
    ) {
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

    public init(
        recents: [LibraryItem] = LibraryItem.sampleRecents,
        onCreate: @escaping () -> Void,
        onOpenProject: @escaping (LibraryItem) -> Void,
        onOpenAllProjects: @escaping () -> Void,
        onOpenWorkflow: @escaping () -> Void
    ) {
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
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 0) {
                DSKicker(
                    String(localized: "home.greeting.stamp", bundle: .module),
                    size: 11,
                    tracking: 0.14,
                    color: DS.Palette.ink(0.4)
                )
                DSHeadline(
                    String(localized: "home.greeting.title", bundle: .module),
                    size: 34
                )
                .padding(.top, 10)
            }

            Spacer(minLength: 0)

            // The mark where the placeholder circle was: the one spot on the home screen that says
            // whose app this is, top right, where a profile picture would otherwise sit.
            DSBrandMark(height: 30)
                .padding(.top, 24)
        }
        .padding(.horizontal, 22)
    }

    // MARK: - Create

    private var createCard: some View {
        Button(action: onCreate) {
            ZStack(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 0) {
                    DSKicker(
                        String(localized: "home.create.kicker", bundle: .module),
                        size: 10,
                        tracking: 0.18,
                        color: DS.Palette.inkInverse(0.6)
                    )
                    DSHeadline(
                        String(localized: "home.create.title", bundle: .module),
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
            }
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.hero, style: .continuous))
            .shadow(color: DS.Palette.accent(0.32), radius: 30, y: 24)
        }
        .buttonStyle(.dsPressCard)
        .padding(.horizontal, 22)
        .padding(.top, 26)
    }

    // MARK: - Recent

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                sectionLabel(String(localized: "home.section.recent", bundle: .module))
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
                    message: String(localized: "home.empty", bundle: .module),
                    action: String(localized: "home.empty.action", bundle: .module),
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
        .background(item.fill.view)
        .overlay(alignment: .topLeading) {
            durationChip(item.duration)
                .padding(11)
        }
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
    }

    private func durationChip(_ text: String) -> some View {
        Text(text)
            .dsFont(.mono, .medium, 9, letterSpacing: 0.1)
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
            sectionLabel(String(localized: "home.section.workflows", bundle: .module))

            Button(action: onOpenWorkflow) {
                HStack(spacing: 13) {
                    Text("PR")
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
                            .foregroundStyle(DS.Palette.ink(0.4))
                    }

                    Spacer(minLength: 0)

                    Text("›")
                        .font(.system(size: 17))
                        .foregroundStyle(DS.Palette.ink(0.3))
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
            .foregroundStyle(DS.Palette.ink(0.45))
    }
}
