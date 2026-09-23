import DesignSystem
import AccountEngine
import AuthenticationServices
import Foundation
import Observation
import Persistence

@MainActor @Observable
public final class AccountModel {
    public private(set) var account: CreatorAccount?
    public private(set) var isBusy = false
    public private(set) var isPreparing = false
    public private(set) var ready = false
    public private(set) var deletionPending = false
    public private(set) var message: String?
    public private(set) var verified = false
    public private(set) var isUnavailable = false

    private let client: AccountClient
    private let appleSignInEnabled: Bool
    private let keychain = KeychainStore(account: "creator.account.session.v1")
    private var session: AccountSession?
    private var challenge: AccountChallenge?
    private var challengeDate = Date.distantPast
    private var requestedChallenge: AccountChallenge?
    private var generation = 0
    private var isRefreshing = false

    public init(client: AccountClient = .bundled(), appleSignInEnabled: Bool? = nil) {
        self.client = client
        let configured = Bundle.main.object(forInfoDictionaryKey: "CueTakeAppleSignInEnabled")
        self.appleSignInEnabled = appleSignInEnabled ?? ((configured as? Bool == true) || (configured as? String == "YES"))
        if let value = keychain.read(), let data = value.data(using: .utf8),
           let saved = try? JSONDecoder().decode(AccountSession.self, from: data),
           saved.expiresAt > Date().timeIntervalSince1970 {
            session = saved
            account = saved.user
            deletionPending = saved.deletionPending ?? false
        } else { keychain.delete() }
    }

    public func prepare() async {
        guard session == nil, !isBusy, !isPreparing else { return }
        guard appleSignInEnabled else { show(AccountError.notConfigured); return }
        isPreparing = true
        isUnavailable = false
        ready = false
        message = nil
        defer { isPreparing = false }
        do {
            let value = try await client.challenge()
            try Task.checkCancellation()
            challenge = value
            challengeDate = Date()
            ready = true
        } catch is CancellationError { }
        catch { show(error) }
    }

    public func configure(_ request: ASAuthorizationAppleIDRequest) {
        guard let challenge, Date().timeIntervalSince(challengeDate) < 280 else {
            ready = false
            message = AppLocalization.string("account.expired", bundle: .module)
            return
        }
        isBusy = true
        ready = false
        requestedChallenge = challenge
        request.requestedScopes = [.fullName]
        request.nonce = challenge.nonce
        request.state = challenge.id
    }

    public func complete(_ result: Result<ASAuthorization, Error>) async {
        let attemptGeneration = generation
        defer { isBusy = false; requestedChallenge = nil; challenge = nil; ready = false }
        do {
            let authorization = try result.get()
            guard let challenge = requestedChallenge,
                  let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  credential.state == challenge.id,
                  let tokenData = credential.identityToken, let token = String(data: tokenData, encoding: .utf8),
                  let codeData = credential.authorizationCode, let code = String(data: codeData, encoding: .utf8)
            else { throw AccountError.unauthorized }
            let name = credential.fullName.map { PersonNameComponentsFormatter().string(from: $0) }
            var value = try await client.signIn(challenge: challenge.id, code: code, identityToken: token, name: name)
            guard attemptGeneration == generation else {
                try? await client.end(token: value.token, deleting: false)
                return
            }
            value.appleUserID = credential.user
            do { try persist(value) }
            catch {
                try? await client.end(token: value.token, deleting: false)
                throw error
            }
            session = value
            account = value.user
            verified = true
            deletionPending = value.deletionPending ?? false
            message = nil
        } catch let error as ASAuthorizationError where error.code == .canceled {
            message = nil
        } catch { show(error) }
    }

    public func refresh() async {
        guard let saved = session, !isBusy, !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            if let appleID = saved.appleUserID {
                let state = try await ASAuthorizationAppleIDProvider().credentialState(forUserID: appleID)
                guard session?.token == saved.token else { return }
                guard state == .authorized else { await revokeLocalSession(); return }
            }
            let status = try await client.status(token: saved.token)
            // A late refresh must never restore an account after the user signed out.
            guard session?.token == saved.token else { return }
            var updated = saved
            updated.user = status.user
            updated.expiresAt = status.expiresAt
            updated.deletionPending = status.deletionPending
            try persist(updated)
            session = updated
            account = updated.user
            deletionPending = status.deletionPending
            verified = true
            message = nil
        } catch AccountError.unauthorized {
            if session?.token == saved.token { clear() }
        } catch {
            guard session?.token == saved.token else { return }
            verified = false
            // Offline is not logout. Cached identity grants no server authority.
            show(error)
        }
    }

    public func end(deleting: Bool) async {
        guard let saved = session, !isBusy else { return }
        isBusy = true
        message = nil
        isUnavailable = false
        defer { isBusy = false }
        do {
            try await client.end(token: saved.token, deleting: deleting)
            clear()
        } catch AccountError.unauthorized {
            clear()
            if deleting { message = AppLocalization.string("account.delete.reauth", bundle: .module) }
        } catch { show(error) }
    }

    public func revokeLocalSession() async {
        let token = session?.token
        clear()
        if let token { try? await client.end(token: token, deleting: false) }
    }

    private func persist(_ value: AccountSession) throws {
        let data = try JSONEncoder().encode(value)
        guard let text = String(data: data, encoding: .utf8), keychain.save(text) else { throw AccountError.secureStorage }
    }

    private func clear() {
        generation += 1
        keychain.delete()
        session = nil
        account = nil
        challenge = nil
        requestedChallenge = nil
        ready = false
        verified = false
        deletionPending = false
        message = nil
    }

    private func show(_ error: Error) {
        if case AccountError.notConfigured = error { isUnavailable = true }
        let key: String.LocalizationValue
        switch error {
        case AccountError.notConfigured: key = "account.unavailable"
        case AccountError.rateLimited: key = "account.rateLimited"
        case AccountError.unauthorized: key = "account.expired"
        case AccountError.secureStorage: key = "account.storageError"
        default: key = "account.networkError"
        }
        message = AppLocalization.string(key, bundle: .module)
    }
}
