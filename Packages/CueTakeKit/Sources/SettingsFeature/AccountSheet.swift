import AccountEngine
import AuthenticationServices
import DesignSystem
import SwiftUI

struct AccountSheet: View {
    let model: AccountModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    @State private var confirmsDeletion = false
    @State private var confirmsLogout = false

    var body: some View {
        ScrollView {
            VStack(spacing: 26) {
                HStack {
                    Text("CueTake").font(DS.archivo(.bold, 21)).tracking(-0.7)
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").font(.system(size: 13, weight: .semibold))
                            .frame(width: 44, height: 44).background(DS.Palette.surfaceRaised, in: Circle())
                    }.buttonStyle(SettingsPressStyle()).disabled(model.isBusy)
                        .accessibilityLabel(Text("settings.close", bundle: .module))
                }.foregroundStyle(DS.Palette.ink)

                AccountEmblem(compact: false, connected: model.account != nil)
                    .frame(height: 186)
                    .settingsEntrance(appeared, delay: 0, reduced: reduceMotion)

                VStack(spacing: 14) {
                    Text(model.account == nil ? "account.hero" : "account.welcome", bundle: .module)
                        .font(DS.archivo(.bold, 36)).tracking(-1.4).foregroundStyle(DS.Palette.ink)
                        .multilineTextAlignment(.center).accessibilityAddTraits(.isHeader)
                    if let account = model.account, !account.name.isEmpty {
                        Text(account.name).font(DS.sans(.semibold, 22)).foregroundStyle(DS.Palette.accent)
                    }
                    Text(model.account == nil ? "account.hero.detail" : "account.localProjects", bundle: .module)
                        .font(DS.sans(.regular, 15)).foregroundStyle(DS.Palette.ink(0.6))
                        .lineSpacing(4).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                }.settingsEntrance(appeared, delay: 0.06, reduced: reduceMotion)

                VStack(spacing: 14) {
                    if model.account == nil { signIn }
                    else { signedIn }
                    if let message = model.message {
                        Label(message, systemImage: "info.circle")
                            .font(DS.sans(.regular, 13)).foregroundStyle(DS.Palette.ink(0.75))
                            .fixedSize(horizontal: false, vertical: true).padding(16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(DS.Palette.surfaceRaised, in: RoundedRectangle(cornerRadius: 18))
                            .accessibilityAddTraits(.updatesFrequently)
                    }
                }.settingsEntrance(appeared, delay: 0.12, reduced: reduceMotion)

                VStack(alignment: .leading, spacing: 16) {
                    benefit("faceid", "account.benefit.passwordless")
                    benefit("lock.shield", "account.benefit.private")
                    benefit("film.stack", "account.benefit.local")
                }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
                    .background(DS.Palette.surface, in: RoundedRectangle(cornerRadius: 24))
                    .settingsEntrance(appeared, delay: 0.16, reduced: reduceMotion)

                Text("account.privacy", bundle: .module)
                    .font(DS.sans(.regular, 12)).foregroundStyle(DS.Palette.ink(0.45))
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            }.padding(24).padding(.top, 8).padding(.bottom, 24).frame(maxWidth: 560).frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .background(DS.Palette.screen)
        .interactiveDismissDisabled(model.isBusy)
        .onAppear { appeared = true }
        .animation(reduceMotion ? .easeOut(duration: 0.15) : DS.Motion.settle, value: model.account != nil)
        .sensoryFeedback(.success, trigger: model.account != nil) { _, signedIn in signedIn }
        .task {
            if model.account != nil { await model.refresh() }
            while !Task.isCancelled {
                await model.prepare()
                do { try await Task.sleep(for: .seconds(240)) } catch { break }
            }
        }
        .confirmationDialog(settingsText("account.delete.title"), isPresented: $confirmsDeletion, titleVisibility: .visible) {
            Button(settingsText("account.delete.action"), role: .destructive) { Task { await model.end(deleting: true) } }
            Button(settingsText("account.cancel"), role: .cancel) { }
        } message: { Text("account.delete.detail", bundle: .module) }
        .confirmationDialog(settingsText("account.logout.title"), isPresented: $confirmsLogout, titleVisibility: .visible) {
            Button(settingsText("account.logout"), role: .destructive) { Task { await model.end(deleting: false); await model.prepare() } }
            Button(settingsText("account.cancel"), role: .cancel) { }
        } message: { Text("account.localProjects", bundle: .module) }
    }

    @ViewBuilder private var signIn: some View {
        SignInWithAppleButton(.continue) { request in model.configure(request) } onCompletion: { result in
                Task {
                    await model.complete(result)
                    if model.account == nil && model.message == nil { await model.prepare() }
                }
            }
            .signInWithAppleButtonStyle(.white)
            .frame(height: 56).clipShape(RoundedRectangle(cornerRadius: 16))
            .disabled(!model.ready || model.isBusy)
            .opacity(model.ready ? 1 : 0.45)
        if model.isPreparing {
            HStack(spacing: 10) {
                ProgressView().tint(DS.Palette.accent)
                Text("account.preparing", bundle: .module).font(DS.sans(.regular, 13))
            }.foregroundStyle(DS.Palette.ink(0.6))
        } else if !model.ready && !model.isBusy && !model.isUnavailable {
            Button { Task { await model.prepare() } } label: {
                Text("account.retry", bundle: .module).font(DS.sans(.medium, 14))
                    .foregroundStyle(DS.Palette.accent).frame(minHeight: 44)
            }.buttonStyle(SettingsPressStyle())
        }
        if model.isBusy {
            Label { Text("account.verifying", bundle: .module) } icon: { ProgressView() }
                .font(DS.sans(.regular, 13)).foregroundStyle(DS.Palette.ink(0.6))
        }
        Button { dismiss() } label: {
            Text("account.guest", bundle: .module).font(DS.sans(.medium, 14))
                .foregroundStyle(DS.Palette.ink(0.65)).frame(minHeight: 44)
        }.buttonStyle(SettingsPressStyle()).disabled(model.isBusy)
    }

    @ViewBuilder private var signedIn: some View {
        Label(settingsText(model.verified ? "account.verified" : "account.saved"), systemImage: model.verified ? "checkmark.seal.fill" : "iphone")
            .font(DS.sans(.medium, 14)).foregroundStyle(DS.Palette.lime)
            .padding(.horizontal, 18).padding(.vertical, 12)
            .background(DS.Palette.lime(0.08), in: Capsule())
        if model.deletionPending {
            Text("account.delete.pending", bundle: .module).font(DS.sans(.regular, 14)).foregroundStyle(DS.Palette.accent)
        }
        if model.isBusy { ProgressView().tint(DS.Palette.accent).frame(minHeight: 44) }
        Button { confirmsLogout = true } label: {
            Text("account.logout", bundle: .module).font(DS.sans(.semibold, 16))
                .foregroundStyle(DS.Palette.ink).frame(maxWidth: .infinity).frame(minHeight: 54)
                .background(DS.Palette.surfaceRaised, in: RoundedRectangle(cornerRadius: 16))
        }.buttonStyle(SettingsPressStyle()).disabled(model.isBusy)
        Button { confirmsDeletion = true } label: {
            Text("account.delete.action", bundle: .module).font(DS.sans(.medium, 13))
                .foregroundStyle(DS.Palette.accent).frame(minHeight: 44)
        }.buttonStyle(SettingsPressStyle()).disabled(model.isBusy)
    }

    private func benefit(_ icon: String, _ key: String.LocalizationValue) -> some View {
        Label { Text(settingsText(key)).font(DS.sans(.medium, 14)) } icon: {
            Image(systemName: icon).frame(width: 28).foregroundStyle(DS.Palette.accent)
        }.foregroundStyle(DS.Palette.ink(0.8))
    }
}

/// An aperture, not a stock avatar. A single opening motion settles into the account's seal.
/// No perpetual timers, particle systems or display-link work on a preferences screen.
struct AccountEmblem: View {
    let compact: Bool
    let connected: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var open = false
    var body: some View {
        ZStack {
            Circle().fill(RadialGradient(colors: [DS.Palette.accent(0.2), .clear], center: .center,
                                         startRadius: 0, endRadius: compact ? 40 : 95))
            ForEach(0..<3) { index in
                RoundedRectangle(cornerRadius: compact ? 12 : 30)
                    .strokeBorder(LinearGradient(colors: [DS.Palette.accent.opacity(0.8 - Double(index) * 0.2), DS.Palette.accentWarm.opacity(0.08)],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.5)
                    .frame(width: size(index), height: size(index))
                    .rotationEffect(.degrees(Double(index) * (open ? 16 : 0) - 16))
            }
            Image(systemName: connected ? "checkmark" : "person.crop.square")
                .font(.system(size: compact ? 22 : 42, weight: .light))
                .foregroundStyle(DS.Palette.ink)
                .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
        }
        .accessibilityHidden(true)
        .onAppear {
            withAnimation(reduceMotion ? nil : .spring(response: 0.9, dampingFraction: 0.8)) { open = true }
        }
    }
    private func size(_ index: Int) -> CGFloat { (compact ? 36 : 104) + CGFloat(index) * (compact ? 9 : 22) }
}
