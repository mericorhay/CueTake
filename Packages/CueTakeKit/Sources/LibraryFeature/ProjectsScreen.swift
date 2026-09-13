import DesignSystem
import SwiftUI

public struct ProjectsScreen: View {
    private let projects: [LibraryItem]
    private let onOpenProject: (LibraryItem) -> Void
    private let onDeleteProjects: ([LibraryItem]) -> Void

    public init(
        projects: [LibraryItem] = LibraryItem.sampleProjects,
        onDeleteProjects: @escaping ([LibraryItem]) -> Void = { _ in },
        onOpenProject: @escaping (LibraryItem) -> Void
    ) {
        self.projects = projects
        self.onDeleteProjects = onDeleteProjects
        self.onOpenProject = onOpenProject
    }

    /// Nil when browsing; the chosen projects while selecting. Selecting starts with a long press on
    /// a card — the way Photos and Files work — and a tap then picks or drops a project.
    @State private var selection: Set<LibraryItem.ID>?
    @State private var confirmingDelete = false
    @State private var pressTick = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isSelecting: Bool { selection != nil }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                DSHeadline(String(localized: "projects.title", bundle: .module), size: 34)

                Text(LocalizedStringKey(isSelecting ? "projects.select.hintActive" : "projects.select.hint"), bundle: .module)
                    .dsFont(.sans, .regular, 13)
                    .foregroundStyle(DS.Palette.ink(0.42))
                    .padding(.top, 6)

                if projects.isEmpty {
                    LibraryEmptyState(
                        message: String(localized: "projects.empty", bundle: .module),
                        action: nil,
                        onTap: nil
                    )
                    .padding(.top, 26)
                }

                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 12, alignment: .top),
                        GridItem(.flexible(), spacing: 12, alignment: .top),
                    ],
                    spacing: 12
                ) {
                    ForEach(projects) { project in
                        card(project)
                            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .onTapGesture {
                                if isSelecting {
                                    toggle(project)
                                } else {
                                    onOpenProject(project)
                                }
                            }
                            .onLongPressGesture(minimumDuration: 0.35) {
                                pressTick += 1
                                withAnimation(DS.Motion.snap) {
                                    if selection == nil { selection = [] }
                                    selection?.insert(project.id)
                                }
                            }
                    }
                }
                .padding(.top, 22)
            }
            .padding(.horizontal, 22)
            .padding(.top, 64)
            .padding(.bottom, isSelecting ? 180 : 108)
        }
        .scrollIndicators(.hidden)
        .dsScreenLayout(scrolls: true)
        .background(DS.Palette.screen)
        .overlay(alignment: .bottom) {
            if let selection {
                selectionBar(selection)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? .easeOut(duration: 0.2) : DS.Motion.settle, value: isSelecting)
        .sensoryFeedback(.impact(weight: .medium), trigger: pressTick)
        // Projects that went away leave the selection.
        .onChange(of: projects.map(\.id)) { _, ids in
            selection = selection.map { $0.intersection(ids) }
        }
        .confirmationDialog(
            String(localized: "projects.select.confirm \(selection?.count ?? 0)", bundle: .module),
            isPresented: $confirmingDelete,
            titleVisibility: .visible
        ) {
            Button(String(localized: "projects.select.delete", bundle: .module), role: .destructive) {
                let chosen = projects.filter { selection?.contains($0.id) == true }
                withAnimation(DS.Motion.settle) { selection = nil }
                onDeleteProjects(chosen)
            }
        } message: {
            Text("projects.select.confirm.message", bundle: .module)
        }
        .dsEnter(.screen())
    }

    private func toggle(_ project: LibraryItem) {
        withAnimation(DS.Motion.snap) {
            if selection?.contains(project.id) == true {
                selection?.remove(project.id)
            } else {
                selection?.insert(project.id)
            }
        }
    }

    /// What can be done with the chosen projects, above the tab bar.
    private func selectionBar(_ chosen: Set<LibraryItem.ID>) -> some View {
        let allChosen = chosen.count == projects.count && !projects.isEmpty
        return HStack(spacing: 10) {
            Button {
                withAnimation(DS.Motion.snap) { selection = nil }
            } label: {
                Text("projects.select.cancel", bundle: .module)
                    .dsFont(.sans, .semibold, 14)
                    .foregroundStyle(DS.Palette.ink)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(Capsule().fill(DS.Palette.hairline(0.1)))
            }
            .buttonStyle(.dsPress(radius: 24))

            VStack(alignment: .leading, spacing: 1) {
                Text("projects.select.count \(chosen.count)", bundle: .module)
                    .dsFont(.sans, .semibold, 14)
                    .foregroundStyle(DS.Palette.ink)
                    .contentTransition(.numericText())
                Button {
                    withAnimation(DS.Motion.snap) {
                        selection = allChosen ? [] : Set(projects.map(\.id))
                    }
                } label: {
                    Text(LocalizedStringKey(allChosen ? "projects.select.none" : "projects.select.all"), bundle: .module)
                        .dsFont(.sans, .medium, 12)
                        .foregroundStyle(DS.Palette.lime)
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                confirmingDelete = true
            } label: {
                Label {
                    Text("projects.select.delete", bundle: .module)
                } icon: {
                    Image(systemName: "trash")
                }
                .dsFont(.sans, .semibold, 14)
                .foregroundStyle(chosen.isEmpty ? DS.Palette.ink(0.3) : DS.Palette.inkInverse)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Capsule().fill(chosen.isEmpty ? DS.Palette.hairline(0.08) : DS.Palette.accent))
            }
            .buttonStyle(.dsPress(radius: 24))
            .disabled(chosen.isEmpty)
        }
        .padding(12)
        .dsGlass(tint: DS.Palette.glassSheet(0.94), in: RoundedRectangle(cornerRadius: 30, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.bottom, 96)
    }

    private func card(_ project: LibraryItem) -> some View {
        let chosen = selection?.contains(project.id) == true
        return VStack(alignment: .leading, spacing: 3) {
            Spacer(minLength: 0)
            TightText(project.title, .archivo, .bold, 14, lineHeight: 1.15)
            Text(project.meta)
                .dsFont(.mono, .medium, 10)
                .foregroundStyle(DS.Palette.ink(0.5))
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: project.height, alignment: .bottomLeading)
        .background { LibraryCardBackground(item: project) }
        .animation(.easeOut(duration: 0.35), value: project.cover)
        .overlay(alignment: .topTrailing) {
            if isSelecting {
                Image(systemName: chosen ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(chosen ? DS.Palette.lime : DS.Palette.ink(0.85))
                    .background(Circle().fill(DS.Palette.inkInverse(0.45)).padding(2))
                    .contentTransition(.symbolEffect(.replace))
                    .padding(9)
                    .transition(.scale.combined(with: .opacity))
            } else {
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
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(DS.Palette.lime, lineWidth: chosen ? 2.5 : 0)
        }
        .scaleEffect(isSelecting && !chosen && !reduceMotion ? 0.96 : 1)
        .opacity(isSelecting && !chosen ? 0.75 : 1)
    }
}

extension LibraryItem {
    /// The design's six project cards, with their own heights and fills. The alphas differ from the
    /// recents rail even where the colour is the same, so they are written out rather than shared.
    public static let sampleProjects: [LibraryItem] = [
        LibraryItem(
            title: "iPhone 17 Pro Max Camera",
            meta: "0:30 · exported",
            duration: "0:30",
            fill: .gradient(angle: 165, from: DS.Palette.accent(0.4), to: Color(hex: 0x121216)),
            height: 206
        ),
        LibraryItem(
            title: "Studio Light Setup",
            meta: "0:45 · draft",
            duration: "0:45",
            fill: .gradient(angle: 165, from: DS.Palette.lime(0.3), to: Color(hex: 0x121216)),
            height: 164
        ),
        LibraryItem(
            title: "3 Editing Habits",
            meta: "1:02 · draft",
            duration: "1:02",
            fill: .solid(DS.Palette.surfaceRaised),
            height: 158
        ),
        LibraryItem(
            title: "Mic Comparison",
            meta: "0:38 · exported",
            duration: "0:38",
            fill: .gradient(angle: 165, from: Color(hex: 0xFF7043, alpha: 0.32), to: Color(hex: 0x121216)),
            height: 200
        ),
        LibraryItem(
            title: "Why I Left 4K60",
            meta: "0:52 · exported",
            duration: "0:52",
            fill: .solid(DS.Palette.surfaceRaised),
            height: 170
        ),
        LibraryItem(
            title: "Desk Tour 2026",
            meta: "1:14 · draft",
            duration: "1:14",
            fill: .gradient(angle: 165, from: Color(hex: 0xF5F5F7, alpha: 0.16), to: Color(hex: 0x121216)),
            height: 194
        ),
    ]
}
