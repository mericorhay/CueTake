import BumpKit
import DesignSystem
import SwiftUI
import TeamSync
import UIKit

/// Two phones meeting: hold them top to top and the joiner is in the team.
///
/// The light follows what actually happens — a thin line while looking, the burst the moment the
/// phones touch, the card once the invite has gone through — so it never celebrates something
/// that then fails. The person whose team it is always says yes first: being near someone's
/// phone is not permission to join their team.
struct PairingView: View {
    let role: PairingRole
    /// The team being joined into, on the inviter's phone.
    let team: TeamInfo?
    let tools: TeamTools
    let onClose: () -> Void

    @State private var link: NearbyLink?
    @State private var phase: BumpPhase = .sensing
    @State private var peer: String?
    @State private var canMeasure = true
    @State private var waiting: String?
    /// The other phone has said who it is; from here the wait is for people and iCloud, not it.
    @State private var heardFrom = false
    @State private var joined: String?
    @State private var problem: String?

    var body: some View {
        BumpStage(phase: phase) {
            content
        } card: {
            BumpPersonCard(name: cardName, detail: cardDetail)
        }
        .background(Color.black.ignoresSafeArea())
        .task { await run() }
        .onDisappear { link?.stop() }
        .confirmationDialog(
            String(localized: "team.pair.confirm \(peer ?? "")", bundle: .module),
            isPresented: Binding(get: { waiting != nil }, set: { if !$0 { decline() } }),
            titleVisibility: .visible
        ) {
            Button(String(localized: "team.pair.letIn", bundle: .module)) { Task { await letIn() } }
            Button(String(localized: "team.pair.notNow", bundle: .module), role: .cancel) { decline() }
        }
    }

    private var content: some View {
        VStack(spacing: 18) {
            HStack {
                Spacer(minLength: 0)
                Button(action: close) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(.white.opacity(0.12)))
                }
                .accessibilityLabel(Text("team.close", bundle: .module))
            }
            Spacer(minLength: 0)

            Image(systemName: "iphone.gen3.radiowaves.left.and.right")
                .font(.system(size: 58, weight: .light))
                .foregroundStyle(.white.opacity(0.85))
                .symbolEffect(.variableColor.iterative, options: .repeating, isActive: phase == .sensing)

            Text(headline)
                .font(.system(size: 24, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .contentTransition(.opacity)

            Text(detail)
                .font(.system(size: 15))
                .foregroundStyle(.white.opacity(0.65))
                .multilineTextAlignment(.center)
                .contentTransition(.opacity)

            // A phone that cannot measure distance meets by a tap instead of a touch.
            if !canMeasure, peer != nil, phase == .sensing {
                Button {
                    Task { await touched() }
                } label: {
                    Text("team.pair.tap", bundle: .module)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 28)
                        .padding(.vertical, 14)
                        .background(Capsule().fill(.white))
                }
                .transition(.scale.combined(with: .opacity))
            }

            if phase == .connected {
                Button(action: close) {
                    Text("team.pair.done", bundle: .module)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 36)
                        .padding(.vertical, 14)
                        .background(Capsule().fill(.white))
                }
                .transition(.opacity)
            }
            Spacer(minLength: 0)
        }
        .padding(24)
        .animation(.spring(duration: 0.45), value: phase)
        .animation(.spring(duration: 0.45), value: canMeasure)
    }

    // MARK: - Words

    private var headline: String {
        if let problem { return problem }
        switch phase {
        case .idle, .sensing:
            if peer != nil { return String(localized: "team.pair.found", bundle: .module) }
            return role == .inviter
                ? String(localized: "team.pair.lookingInviter", bundle: .module)
                : String(localized: "team.pair.lookingJoiner", bundle: .module)
        case .contact:
            return String(localized: "team.pair.touched", bundle: .module)
        case .connected:
            return String(localized: "team.pair.joined", bundle: .module)
        }
    }

    private var detail: String {
        if let peer, phase == .sensing {
            return canMeasure
                ? String(localized: "team.pair.bringCloser \(peer)", bundle: .module)
                : String(localized: "team.pair.tapToMeet \(peer)", bundle: .module)
        }
        return String(localized: "team.pair.howTo", bundle: .module)
    }

    private var cardName: String {
        role == .inviter ? (peer ?? "") : (joined ?? team?.name ?? "")
    }

    private var cardDetail: String {
        role == .inviter
            ? String(localized: "team.pair.card.joinedYours", bundle: .module)
            : String(localized: "team.pair.card.youJoined", bundle: .module)
    }

    // MARK: - The meeting

    private func run() async {
        let made = NearbyLink(role: role, displayName: UIDevice.current.name)
        link = made
        made.start()
        for await event in made.events {
            switch event {
            case .linked(let name):
                peer = name
                problem = nil
            case .distance(let metres):
                if metres == nil { canMeasure = false }
            case .touched:
                await touched()
            case .received(let message):
                await received(message)
            case .lost:
                if phase != .connected {
                    phase = .sensing
                    peer = nil
                }
            }
        }
    }

    private func touched() async {
        guard phase == .sensing, peer != nil else { return }
        problem = nil
        phase = .contact
        guard role == .joiner else {
            // The other phone answers with who it is within a moment, or it is not going to —
            // not signed in to iCloud, or gone. The light does not wait for ever.
            Task {
                try? await Task.sleep(for: .seconds(12))
                if phase == .contact, !heardFrom { fail("team.pair.failed") }
            }
            return
        }
        do {
            let me = try await tools.me()
            link?.send(.identity(userRecordName: me))
        } catch {
            fail("team.pair.noICloud")
        }
    }

    private func received(_ message: PairingMessage) async {
        switch message {
        case .identity(let name) where role == .inviter:
            heardFrom = true
            waiting = name
        case .invite(let url, let teamName) where role == .joiner:
            do {
                _ = try await tools.join(url)
                joined = teamName
                phase = .connected
                link?.send(.joined)
            } catch {
                fail("team.pair.failed")
            }
        case .declined where role == .joiner:
            fail("team.pair.declined")
        case .joined where role == .inviter:
            phase = .connected
        default:
            break
        }
    }

    private func letIn() async {
        guard let team, let identity = waiting else { return }
        waiting = nil
        do {
            guard let url = try await tools.letIn(identity, team) else {
                fail("team.pair.failed")
                return
            }
            link?.send(.invite(url: url, team: team.name))
            // Their phone accepting is what makes it true; it says so with `.joined`. Until then
            // the light stays at the touch, and gives up if nothing comes.
            Task {
                try? await Task.sleep(for: .seconds(20))
                if phase == .contact { fail("team.pair.failed") }
            }
        } catch {
            fail("team.pair.failed")
        }
    }

    private func decline() {
        guard waiting != nil else { return }
        waiting = nil
        link?.send(.declined)
        phase = .sensing
    }

    private func fail(_ key: String.LocalizationValue) {
        problem = String(localized: key, bundle: .module)
        phase = .sensing
    }

    private func close() {
        link?.stop()
        onClose()
    }
}
