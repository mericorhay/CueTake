import CryptoKit
import DeviceCheck
import Foundation

/// Proves to our server, with Apple as the witness, that a request comes from the real CueTake app
/// on a real iPhone.
///
/// Once per install a key is made in the Secure Enclave and Apple attests it; the server checks
/// Apple's chain and hands back a signed device token. Each certificate or review request then
/// carries that token and the key's signature over a fresh challenge from the server.
///
/// Everything here is best effort. On the simulator, on a build without the App Attest
/// entitlement, or offline, `proof()` is nil and the request goes without it: the server decides
/// whether that is acceptable (`REQUIRE_ATTEST`).
public actor AppAttestor {
    private let client: AssistantClient
    private let defaults: UserDefaults
    private static let keyIDKey = "attest.keyID"
    private static let deviceKey = "attest.device"

    public init(client: AssistantClient, defaults: UserDefaults = .standard) {
        self.client = client
        self.defaults = defaults
    }

    /// Proof for one request, or nil when this phone or build cannot give it.
    public func proof() async -> AssistantClient.AttestProof? {
        guard DCAppAttestService.shared.isSupported, client.isConfigured else { return nil }
        do {
            let device = try await deviceToken()
            guard let keyID = defaults.string(forKey: Self.keyIDKey) else { return nil }
            let challenge = try await client.attestChallenge()
            let hash = Data(SHA256.hash(data: Data(challenge.payload.utf8)))
            let assertion = try await DCAppAttestService.shared.generateAssertion(keyID, clientDataHash: hash)
            return AssistantClient.AttestProof(device: device, challenge: challenge, assertion: assertion.base64EncodedString())
        } catch let error as DCError where error.code == .invalidKey {
            // The key is gone (a restore onto another phone): start again next time.
            forget()
            return nil
        } catch {
            return nil
        }
    }

    /// The server's signed word that this install's key was attested, made once and reused
    /// until it expires.
    private func deviceToken() async throws -> AssistantClient.Signed {
        if let data = defaults.data(forKey: Self.deviceKey),
           let saved = try? JSONDecoder().decode(AssistantClient.Signed.self, from: data),
           !Self.expired(saved) {
            return saved
        }
        let keyID: String
        if let saved = defaults.string(forKey: Self.keyIDKey) {
            keyID = saved
        } else {
            keyID = try await DCAppAttestService.shared.generateKey()
            defaults.set(keyID, forKey: Self.keyIDKey)
        }
        let challenge = try await client.attestChallenge()
        let hash = Data(SHA256.hash(data: Data(challenge.payload.utf8)))
        let attestation = try await DCAppAttestService.shared.attestKey(keyID, clientDataHash: hash)
        let token = try await client.attestRegister(keyID: keyID, attestation: attestation, challenge: challenge)
        if let data = try? JSONEncoder().encode(token) { defaults.set(data, forKey: Self.deviceKey) }
        return token
    }

    private func forget() {
        defaults.removeObject(forKey: Self.keyIDKey)
        defaults.removeObject(forKey: Self.deviceKey)
    }

    /// A day's margin, so a token never expires between being read and being checked.
    static func expired(_ token: AssistantClient.Signed) -> Bool {
        var text = token.payload.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while text.count % 4 != 0 { text += "=" }
        guard let data = Data(base64Encoded: text),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let exp = object["exp"] as? Double
        else { return true }
        return exp < Date.now.timeIntervalSince1970 + 86_400
    }
}

extension AssistantClient {
    /// Something the server signed and the app hands back unchanged.
    public struct Signed: Codable, Hashable, Sendable {
        public var payload: String
        public var signature: String

        public init(payload: String, signature: String) {
            self.payload = payload
            self.signature = signature
        }
    }

    /// What a request carries to prove where it came from.
    public struct AttestProof: Encodable, Sendable {
        public var device: Signed
        public var challenge: Signed
        public var assertion: String
    }

    private struct RegisterRequest: Encodable {
        var keyID: String
        var attestation: String
        var challenge: Signed
    }

    private struct Empty: Encodable {}

    func attestChallenge() async throws -> Signed {
        let data = try await postSigned("attest/challenge", Empty())
        return try JSONDecoder().decode(Signed.self, from: data)
    }

    func attestRegister(keyID: String, attestation: Data, challenge: Signed) async throws -> Signed {
        let data = try await postSigned(
            "attest/register",
            RegisterRequest(keyID: keyID, attestation: attestation.base64EncodedString(), challenge: challenge)
        )
        return try JSONDecoder().decode(Signed.self, from: data)
    }

    private func postSigned(_ path: String, _ body: some Encodable) async throws -> Data {
        guard let endpoint else { throw AssistantError.notConfigured }
        var request = URLRequest(url: endpoint.url.appending(path: path))
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(endpoint.appToken, forHTTPHeaderField: "x-cuetake-app")
        request.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw AssistantError.rejected(status: (response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        return data
    }
}
