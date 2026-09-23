# Settings and Apple accounts — build 141

## Current delivery

- Settings has a creator account card and four focused panels: camera/capture, editing/export,
  AI/connections, device/privacy. Voice profile, certificates and the gated Teams entry remain.
- Archivo headlines, Instrument Sans controls and JetBrains Mono metadata use the existing font
  assets. Content wraps; the page and panels scroll. Entrance/aperture/press motion respects Reduce
  Motion. Apple’s native sign-in button retains Apple's typography and branding.
- Account entry: Settings → account card. No email/password form, and no mandatory account wall.
  This account identifies a creator; it does **not** enable project sync, subscriptions or backup.
- Native Apple authorization → Worker verification against Apple's public keys → Keychain session → account management.
  Guest projects remain local across sign-in, sign-out and account deletion.
- Apple sign-in is **not live until the Apple configuration below is complete**. The build and
  server independently gate availability; no successful login is simulated.

## Architecture and security

`SettingsFeature/AccountModel` owns the UI lifecycle. `AccountEngine/AccountClient` owns HTTPS
transport. The app composition root retains one model through screen changes and checks Apple
credential state on activation; credential revocation clears local identity. Network failures do
not erase local projects or turn a cached identity into verified access. Session writes must
succeed in the device-only Keychain before sign-in succeeds. Redirects are rejected.

`backend/assistant/auth.mjs` is separate from the AI request handlers. It runs in the existing
Cloudflare Worker; `AUTH_DB` is Cloudflare D1 (`cuetake-accounts`). No VM or always-on server.
The old assistant app token is **not** a user credential. Existing AI endpoints are unchanged.

Routes:

| Route | Contract |
|---|---|
| `GET /auth/status` | Availability only; no configuration or secrets |
| `POST /auth/challenge` | 256-bit nonce + challenge, five-minute expiry |
| `POST /auth/apple` | Apple RS256 signature/JWKS, issuer, audience, nonce, issue/expiry times and a single-use challenge; optional authorization-code exchange when a service key is configured |
| `GET /auth/session` | Current identity and session expiry; requires bearer session |
| `POST /auth/logout` | Revokes that server session immediately |
| `DELETE /auth/account` | Revokes an Apple refresh token when one exists, then deletes the account and **all** sessions |

Sessions are random 256-bit values, stored only as SHA-256 hashes in D1, and expire after 30 days
(reauthentication, not indefinite silent renewal). When optional server token lifecycle credentials
are configured, Apple's refresh credential is AES-256-GCM encrypted and bound to the account ID as
authenticated data. Native-only accounts do not create or store an Apple refresh token. No email is requested or stored. The
display name is optional and never used as identity. Never link users by their email or name.
Do not log credentials or return Apple error bodies. Responses have `Cache-Control: no-store`.
Authentication has its own rate limiter and a streaming request-size bound.

Deletion failures keep a retryable pending account, rather than reporting success. A lease excludes
concurrent sign-in during revocation; a pending user can reauthenticate after an expired session
to finish deletion. User-facing deletion explicitly preserves local projects. Future cloud account
data must join the deletion transaction; do not silently broaden today's claim.

## Apple activation (external prerequisite)

1. Apple Developer → Identifiers → `com.orhay.cuetake`: enable **Sign in with Apple**.
2. Regenerate the App Store provisioning profile with Sign in with Apple enabled; replace GitHub
   `IOS_PROVISIONING_PROFILE` with that profile's base64, preserving the other capabilities.
3. Optional server-side authorization-code exchange and Apple refresh-token revocation can be
   enabled with a dedicated Sign in with Apple key associated with this primary App ID:
   - `APPLE_AUTH_KEY_ID`
   - `APPLE_AUTH_PRIVATE_KEY` (the Apple `.p8` PEM)
   This is **not** the existing App Store Connect upload key. Native sign-in remains available
   without it. Team ID: `XYB3NLV654`.
   `AUTH_ENCRYPTION_KEY` is already provisioned. Never rotate it without re-encrypting existing
   refresh credentials. Client/team IDs are nonsecret Worker vars.
4. Run CI, then TestFlight. The release workflow inspects the **actual profile**, derives temporary
   signing entitlements and the `CueTakeAppleSignInEnabled` Info.plist flag. The native sign-in
   control is unavailable if the signed binary lacks the capability. Server setup must also pass.
5. Verify on a real iPhone: fresh authorization, cancel, returning authorization (no name supplied),
   app restart, offline account screen, logout, revoked Apple permission, deletion and re-creation.

For a developer-signed local build, add the Apple sign-in capability in Xcode and set
`CUETAKE_APPLE_SIGN_IN_ENABLED = YES`. Do not turn on this flag without the entitlement.

## Operations and verification

```powershell
node --test backend/assistant/auth.test.mjs
cd backend/assistant
npx wrangler d1 migrations apply AUTH_DB --remote
npx wrangler deploy --keep-vars
```

Keep remote vars when deploying: the Worker already serves AI and certificates. Account routes
must remain optional when Apple secrets are absent. The initial D1 migration is additive.

CI includes cryptographic and D1-backed account tests on Node 24, the simulator app build, package
tests and English, Spanish and Turkish settings/account/capture/editing/AI/privacy/voice/certificates screenshots
as `settings-layouts`. DEBUG launch
arguments only select the UI for these captures; they do not bypass authentication. Screenshots
verify layout, not successful Apple authorization or physical-device animation performance.

Apple references:
- https://developer.apple.com/design/human-interface-guidelines/sign-in-with-apple
- https://developer.apple.com/documentation/signinwithapple/verifying-a-user
- https://developer.apple.com/documentation/technotes/tn3194-handling-account-deletions-and-revoking-tokens-for-sign-in-with-apple
