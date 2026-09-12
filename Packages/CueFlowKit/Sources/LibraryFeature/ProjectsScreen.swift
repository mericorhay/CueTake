import DesignSystem
import SwiftUI

public struct ProjectsScreen: View {
    private let projects: [LibraryItem]
    private let onOpenProject: (LibraryItem) -> Void

    public init(
        projects: [LibraryItem] = LibraryItem.sampleProjects,
        onOpenProject: @escaping (LibraryItem) -> Void
    ) {
        self.projects = projects
        self.onOpenProject = onOpenProject
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                DSHeadline(String(localized: "projects.title", bundle: .module), size: 34)

                Text("projects.subtitle", bundle: .module)
                    .dsFont(.sans, .regular, 13)
                    .foregroundStyle(DS.Palette.ink(0.42))
                    .padding(.top, 6)

                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 12, alignment: .top),
                        GridItem(.flexible(), spacing: 12, alignment: .top),
                    ],
                    spacing: 12
                ) {
                    ForEach(projects) { project in
                        Button {
                            onOpenProject(project)
                        } label: {
                            card(project)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 22)
            }
            .padding(.horizontal, 22)
            .padding(.top, 64)
            .padding(.bottom, 108)
        }
        .scrollIndicators(.hidden)
        .background(DS.Palette.screen)
        .dsEnter(.screen())
    }

    private func card(_ project: LibraryItem) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Spacer(minLength: 0)
            TightText(project.title, .archivo, .bold, 14, lineHeight: 1.15)
            Text(project.meta)
                .dsFont(.mono, .medium, 10)
                .foregroundStyle(DS.Palette.ink(0.5))
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: project.height, alignment: .bottomLeading)
        .background(project.gradient)
        .overlay(alignment: .topTrailing) {
            Text(project.duration)
                .dsFont(.mono, .medium, 9)
                .foregroundStyle(DS.Palette.ink)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(DS.Palette.inkInverse(0.55))
                )
                .padding(10)
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

extension LibraryItem {
    /// The design's six project cards, including their staggered heights.
    public static let sampleProjects: [LibraryItem] = [
        LibraryItem(title: "iPhone 17 Pro Max Camera", meta: "0:30 · exported", duration: "0:30", tint: 0, height: 206),
        LibraryItem(title: "Studio Light Setup", meta: "0:45 · draft", duration: "0:45", tint: 1, height: 164),
        LibraryItem(title: "3 Editing Habits", meta: "1:02 · draft", duration: "1:02", tint: 2, height: 158),
        LibraryItem(title: "Mic Comparison", meta: "0:38 · exported", duration: "0:38", tint: 3, height: 200),
        LibraryItem(title: "Why I Left 4K60", meta: "0:52 · exported", duration: "0:52", tint: 2, height: 170),
        LibraryItem(title: "Desk Tour 2026", meta: "1:14 · draft", duration: "1:14", tint: 4, height: 194),
    ]
}
