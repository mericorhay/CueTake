import BumpKit
import DesignSystem
import SwiftUI

/// Where a team is made and joined.
///
/// Until sharing is switched on for the app (it needs iCloud on the developer account, see
/// `isSharingAvailable`), this screen says so plainly and lets the light be tried: better an
/// honest "not yet" than a button that pretends.
public struct TeamScreen: View {
    /// Whether the app can reach shared iCloud storage. False until the account side is done.
    let isSharingAvailable: Bool
    /// What a build with teams can do. Nil shows the honest "not yet" screen.
    let tools: TeamTools?
    let onClose: () -> Void

    @State private var phase: BumpPhase = .idle
    @State private var closeness: Double?
    @State private var rehearsal: Task<Void, Never>?

    public init(isSharingAvailable: Bool, tools: TeamTools? = nil, onClose: @escaping () -> Void) {
        self.isSharingAvailable = isSharingAvailable
        self.tools = tools
        self.onClose = onClose
    }

    public var body: some View {
        if isSharingAvailable, let tools {
            TeamHome(tools: tools, onClose: onClose)
        } else {
            preview
        }
    }

    private var preview: some View {
        BumpStage(phase: phase, closeness: closeness) {
            content
        } card: {
            BumpPersonCard(
                name: String(localized: "team.preview.name", bundle: .module),
                detail: String(localized: "team.preview.detail", bundle: .module)
            )
        }
        .background(DS.Palette.screen.ignoresSafeArea())
        .onDisappear { rehearsal?.cancel() }
    }

    private var content: some View {
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

                Text("team.explainer", bundle: .module)
                    .dsFont(.sans, .regular, 14)
                    .foregroundStyle(DS.Palette.ink(0.65))

                VStack(alignment: .leading, spacing: 12) {
                    point("person.2.fill", "team.point.invite")
                    point("arrow.triangle.2.circlepath", "team.point.sync")
                    point("lock.fill", "team.point.private")
                }
                .padding(16)
                .dsCard(radius: DS.Radius.card)

                if !isSharingAvailable {
                    Label {
                        Text("team.notYet", bundle: .module)
                    } icon: {
                        Image(systemName: "hourglass")
                    }
                    .dsFont(.sans, .medium, 12)
                    .foregroundStyle(DS.Palette.accentWarm)
                }

                Button(action: rehearse) {
                    Label(String(localized: "team.tryLight", bundle: .module), systemImage: "sparkles")
                        .dsFont(.sans, .semibold, 15)
                        .foregroundStyle(DS.Palette.inkInverse)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(Capsule().fill(DS.Palette.lime))
                }
                .buttonStyle(.dsPress(radius: 26))
                .disabled(rehearsal != nil)

                Text("team.tryLight.note", bundle: .module)
                    .dsFont(.sans, .regular, 11)
                    .foregroundStyle(DS.Palette.ink(0.56))
            }
            .padding(.horizontal, 22)
            .padding(.top, 24)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
    }

    private func point(_ symbol: String, _ key: String.LocalizationValue) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DS.Palette.lime)
                .frame(width: 22)
            Text(String(localized: key, bundle: .module))
                .dsFont(.sans, .regular, 13)
                .foregroundStyle(DS.Palette.ink(0.8))
        }
    }

    /// The whole meeting, played on this phone alone: looking, touching, joined, and back.
    private func rehearse() {
        rehearsal?.cancel()
        rehearsal = Task {
            // However it ends, the button comes back and the light goes out.
            defer {
                phase = .idle
                closeness = nil
                rehearsal = nil
            }
            phase = .sensing
            // The other phone coming closer, as the distance readings would say it.
            for step in 0...12 {
                closeness = Double(step) / 12
                try? await Task.sleep(for: .milliseconds(110))
                guard !Task.isCancelled else { return }
            }
            phase = .contact
            try? await Task.sleep(for: .seconds(0.9))
            guard !Task.isCancelled else { return }
            phase = .connected
            try? await Task.sleep(for: .seconds(2.6))
            guard !Task.isCancelled else { return }
        }
    }
}
