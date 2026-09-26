import DesignSystem
import SwiftUI

/// The one test account, for App Review and our own testing: signed in, every CueTake+ tool is
/// open without a purchase. Reached by tapping the version five times; the credentials are checked
/// on our server, never kept in the app.
public struct ReviewAccess {
    public enum Result: Sendable {
        case signedIn
        case wrongCredentials
        case unavailable
    }

    public var isOn: Bool
    public var signIn: (String, String) async -> Result
    public var signOut: () -> Void

    public init(isOn: Bool, signIn: @escaping (String, String) async -> Result, signOut: @escaping () -> Void) {
        self.isOn = isOn
        self.signIn = signIn
        self.signOut = signOut
    }
}

struct ReviewLoginSheet: View {
    let access: ReviewAccess
    let close: () -> Void

    @State private var username = ""
    @State private var password = ""
    @State private var working = false
    @State private var problem: String?
    @FocusState private var field: Field?

    private enum Field { case username, password }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                SettingsSheetHeader(
                    icon: "person.badge.key",
                    title: settingsText("settings.review.title"),
                    detail: settingsText(access.isOn ? "settings.review.on" : "settings.review.detail"),
                    close: close
                )
                if access.isOn {
                    Button(role: .destructive) {
                        access.signOut()
                        close()
                    } label: {
                        Text("settings.review.signOut", bundle: .module)
                            .font(DS.sans(.semibold, 15))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(DS.Palette.surface, in: RoundedRectangle(cornerRadius: 18))
                    }
                    .tint(DS.Palette.accent)
                } else {
                    VStack(spacing: 1) {
                        TextField(settingsText("settings.review.username"), text: $username)
                            .textContentType(.username)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .submitLabel(.next)
                            .focused($field, equals: .username)
                            .onSubmit { field = .password }
                            .padding(18)
                        Divider().overlay(DS.Palette.hairline(0.08))
                        SecureField(settingsText("settings.review.password"), text: $password)
                            .textContentType(.password)
                            .submitLabel(.go)
                            .focused($field, equals: .password)
                            .onSubmit(signIn)
                            .padding(18)
                    }
                    .font(DS.sans(.regular, 16))
                    .foregroundStyle(DS.Palette.ink)
                    .background(DS.Palette.surface, in: RoundedRectangle(cornerRadius: 24))

                    if let problem {
                        Text(problem)
                            .font(DS.sans(.regular, 13))
                            .foregroundStyle(DS.Palette.accent)
                            .accessibilityAddTraits(.updatesFrequently)
                    }

                    Button(action: signIn) {
                        ZStack {
                            if working {
                                ProgressView().tint(DS.Palette.inkInverse)
                            } else {
                                Text("settings.review.signIn", bundle: .module)
                            }
                        }
                        .font(DS.sans(.semibold, 16))
                        .foregroundStyle(DS.Palette.inkInverse)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(DS.Palette.accent, in: Capsule())
                    }
                    .buttonStyle(SettingsPressStyle())
                    .disabled(working || username.isEmpty || password.isEmpty)
                    .opacity(username.isEmpty || password.isEmpty ? 0.5 : 1)
                }
            }
            .padding(22).padding(.top, 14).padding(.bottom, 28)
        }
        .scrollIndicators(.hidden)
        .background(DS.Palette.screen)
        .onAppear { if !access.isOn { field = .username } }
    }

    private func signIn() {
        guard !working, !username.isEmpty, !password.isEmpty else { return }
        working = true
        problem = nil
        Task {
            let result = await access.signIn(username.trimmingCharacters(in: .whitespaces), password)
            working = false
            switch result {
            case .signedIn: close()
            case .wrongCredentials: problem = settingsText("settings.review.wrong")
            case .unavailable: problem = settingsText("settings.review.unavailable")
            }
        }
    }
}
