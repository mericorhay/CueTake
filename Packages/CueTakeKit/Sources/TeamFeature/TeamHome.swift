import CloudKit
import DesignSystem
import SwiftUI
import TeamSync
import UIKit

/// The teams this phone belongs to, and the ways to make, join and fill one.
struct TeamHome: View {
    let tools: TeamTools
    let onClose: () -> Void

    @State private var newName = ""
    @State private var busy = false
    @State private var problem: String?
    @State private var pairing: Pairing?
    @State private var inviting: Invite?
    @State private var leaving: TeamInfo?

    private struct Pairing: Identifiable {
        let id = UUID()
        let role: PairingRole
        let team: TeamInfo?
    }

    private struct Invite: Identifiable {
        let id = UUID()
        let share: CKShare
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    DSKicker(String(localized: "team.title", bundle: .module))
                    Spacer(minLength: 0)
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(DS.Palette.ink(0.6))
                            .frame(width: 30, height: 30)
                            .background(Circle().fill(DS.Palette.hairline(0.08)))
                    }
                    .buttonStyle(.dsPressIcon)
                    .accessibilityLabel(Text("team.close", bundle: .module))
                }

                Text("team.headline", bundle: .module)
                    .dsFont(.archivo, .bold, 28)
                    .foregroundStyle(DS.Palette.ink)

                if let problem {
                    Text(verbatim: problem)
                        .dsFont(.sans, .medium, 12)
                        .foregroundStyle(DS.Palette.accentWarm)
                }

                ForEach(tools.teams) { team in
                    card(team)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                makeRow

                Button {
                    pairing = Pairing(role: .joiner, team: nil)
                } label: {
                    Label(String(localized: "team.joinNearby", bundle: .module), systemImage: "iphone.gen3.radiowaves.left.and.right")
                        .dsFont(.sans, .semibold, 14)
                        .foregroundStyle(DS.Palette.ink)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(DS.Palette.hairline(0.07)))
                }
                .buttonStyle(.dsPress(radius: 16))

                Text("team.point.private", bundle: .module)
                    .dsFont(.sans, .regular, 11)
                    .foregroundStyle(DS.Palette.ink(0.56))
            }
            .padding(.horizontal, 22)
            .padding(.top, 24)
            .padding(.bottom, 40)
            .animation(DS.Motion.settle, value: tools.teams.map(\.id))
        }
        .scrollIndicators(.hidden)
        .background(DS.Palette.screen.ignoresSafeArea())
        .task { await tools.refresh() }
        .fullScreenCover(item: $pairing) { meeting in
            PairingView(role: meeting.role, team: meeting.team, tools: tools) {
                pairing = nil
                Task { await tools.refresh() }
            }
        }
        .sheet(item: $inviting) { invite in
            CloudSharingSheet(share: invite.share, container: tools.container)
                .ignoresSafeArea()
        }
        .confirmationDialog(
            String(localized: "team.leave.title \(leaving?.name ?? "")", bundle: .module),
            isPresented: Binding(get: { leaving != nil }, set: { if !$0 { leaving = nil } }),
            titleVisibility: .visible
        ) {
            if let team = leaving {
                Button(leaveTitle(for: team), role: .destructive) {
                    run { try await tools.leave(team) }
                }
            }
        } message: {
            if leaving?.isOwner == true {
                Text("team.leave.endMessage", bundle: .module)
            } else {
                Text("team.leave.leaveMessage", bundle: .module)
            }
        }
    }

    private func leaveTitle(for team: TeamInfo) -> String {
        if team.isOwner {
            return String(localized: "team.leave.end", bundle: .module)
        }
        return String(localized: "team.leave.leave", bundle: .module)
    }

    // MARK: - Parts

    private func card(_ team: TeamInfo) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: team.isOwner ? "person.2.crop.square.stack.fill" : "person.2.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(DS.Palette.lime)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: team.name)
                        .dsFont(.sans, .semibold, 16)
                        .foregroundStyle(DS.Palette.ink)
                    Text("team.projects \(team.projects.count)", bundle: .module)
                        .dsFont(.sans, .regular, 11)
                        .foregroundStyle(DS.Palette.ink(0.5))
                }
                Spacer(minLength: 0)
                Menu {
                    Button(role: .destructive) { leaving = team } label: {
                        if team.isOwner {
                            Label(String(localized: "team.leave.end", bundle: .module), systemImage: "trash")
                        } else {
                            Label(String(localized: "team.leave.leave", bundle: .module), systemImage: "rectangle.portrait.and.arrow.right")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(DS.Palette.ink(0.6))
                        .frame(width: 32, height: 32)
                }
            }

            if let current = tools.currentProject, !team.projects.contains(current.id) {
                action("square.and.arrow.up.on.square", String(localized: "team.addProject \(current.title)", bundle: .module)) {
                    busy = true
                    Task {
                        await tools.addCurrentProject(team)
                        busy = false
                    }
                }
            }

            if team.isOwner {
                HStack(spacing: 8) {
                    action("iphone.gen3.radiowaves.left.and.right", String(localized: "team.inviteNearby", bundle: .module)) {
                        pairing = Pairing(role: .inviter, team: team)
                    }
                    action("link", String(localized: "team.inviteLink", bundle: .module)) {
                        run { inviting = Invite(share: try await tools.share(team)) }
                    }
                }
            }
        }
        .padding(16)
        .dsCard(radius: DS.Radius.card)
    }

    private var makeRow: some View {
        HStack(spacing: 8) {
            TextField(String(localized: "team.make.placeholder", bundle: .module), text: $newName)
                .dsFont(.sans, .regular, 14)
                .foregroundStyle(DS.Palette.ink)
                .submitLabel(.done)
                .onSubmit(make)
                .padding(.horizontal, 14)
                .frame(height: 44)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(DS.Palette.hairline(0.07)))
            Button(action: make) {
                Text("team.make", bundle: .module)
                    .dsFont(.sans, .semibold, 13)
                    .foregroundStyle(DS.Palette.inkInverse)
                    .padding(.horizontal, 16)
                    .frame(height: 44)
                    .background(Capsule().fill(DS.Palette.lime))
            }
            .buttonStyle(.dsPress(radius: 22))
            .disabled(busy || newName.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private func action(_ symbol: String, _ title: String, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            Label(title, systemImage: symbol)
                .dsFont(.sans, .medium, 12)
                .foregroundStyle(DS.Palette.ink(0.85))
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(DS.Palette.hairline(0.07)))
        }
        .buttonStyle(.dsPress(radius: 12))
        .disabled(busy)
    }

    private func make() {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        run {
            _ = try await tools.makeTeam(name)
            newName = ""
            await tools.refresh()
        }
    }

    /// Runs one of the actions above, saying plainly when iCloud turned it down.
    private func run(_ work: @escaping () async throws -> Void) {
        busy = true
        problem = nil
        Task {
            do {
                try await work()
            } catch {
                problem = String(localized: "team.problem", bundle: .module)
            }
            busy = false
        }
    }
}

/// The system's own invite sheet: Messages, Mail, a link, and who may edit.
struct CloudSharingSheet: UIViewControllerRepresentable {
    let share: CKShare
    let container: CKContainer

    func makeUIViewController(context: Context) -> UICloudSharingController {
        let controller = UICloudSharingController(share: share, container: container)
        controller.availablePermissions = [.allowPrivate, .allowReadWrite]
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: UICloudSharingController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(title: share[CKShare.SystemFieldKey.title] as? String ?? "CueTake") }

    final class Coordinator: NSObject, UICloudSharingControllerDelegate {
        let title: String
        init(title: String) { self.title = title }

        func itemTitle(for csc: UICloudSharingController) -> String? { title }
        func cloudSharingController(_ csc: UICloudSharingController, failedToSaveShareWithError error: any Error) {}
    }
}
