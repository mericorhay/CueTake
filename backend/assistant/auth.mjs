// Account boundary. No model-provider or shared app token is an account credential.
// D1 supplies atomic, single-use challenges and immediately revocable sessions.
const encoder = new TextEncoder();
const APPLE = "https://appleid.apple.com";
const SESSION_SECONDS = 30 * 24 * 60 * 60;
let keyCache;
const reply = (value, status = 200) => new Response(JSON.stringify(value), {
  status, headers: { "content-type": "application/json", "cache-control": "no-store" },
});
const fail = (code, status = 400) => Object.assign(new Error(code), { status });
export const encode = bytes => btoa(String.fromCharCode(...new Uint8Array(bytes)))
  .replaceAll("+", "-").replaceAll("/", "_").replace(/=+$/, "");
const decode = value => Uint8Array.from(atob(value.replaceAll("-", "+").replaceAll("_", "/")), c => c.charCodeAt(0));
const random = () => encode(crypto.getRandomValues(new Uint8Array(32)));
export const digest = async value => encode(await crypto.subtle.digest("SHA-256", encoder.encode(value)));
const now = () => Math.floor(Date.now() / 1000);

export async function verifyAppleToken(token, audience, nonce, keys, time = now()) {
  if (typeof token !== "string" || token.length > 12000) throw fail("invalid_identity", 401);
  try {
    const parts = token.split(".");
    if (parts.length !== 3) throw new Error();
    const header = JSON.parse(new TextDecoder().decode(decode(parts[0])));
    const claims = JSON.parse(new TextDecoder().decode(decode(parts[1])));
    if (header.alg !== "RS256" || typeof header.kid !== "string") throw new Error();
    const jwk = keys.find(k => k.kid === header.kid && k.kty === "RSA" && k.alg === "RS256" && k.use === "sig");
    if (!jwk) throw new Error();
    const key = await crypto.subtle.importKey("jwk", jwk, { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["verify"]);
    const valid = await crypto.subtle.verify("RSASSA-PKCS1-v1_5", key, decode(parts[2]), encoder.encode(`${parts[0]}.${parts[1]}`));
    if (!valid || claims.iss !== APPLE || claims.aud !== audience || claims.nonce !== nonce ||
        typeof claims.sub !== "string" || !claims.sub || !Number.isFinite(claims.exp) || claims.exp <= time ||
        !Number.isFinite(claims.iat) || claims.iat > time + 60 || claims.iat < time - 600) throw new Error();
    return claims;
  } catch { throw fail("invalid_identity", 401); }
}

async function appleKeys(kid) {
  if (!keyCache || keyCache.until < Date.now() || !keyCache.keys.some(k => k.kid === kid)) {
    const response = await fetch(`${APPLE}/auth/keys`, { signal: AbortSignal.timeout(10000) });
    if (!response.ok) throw fail("apple_unavailable", 503);
    const { keys } = await response.json();
    if (!Array.isArray(keys)) throw fail("apple_unavailable", 503);
    keyCache = { keys, until: Date.now() + 3600000 };
  }
  return keyCache.keys;
}

async function clientSecret(env) {
  const header = encode(encoder.encode(JSON.stringify({ alg: "ES256", kid: env.APPLE_AUTH_KEY_ID })));
  const payload = encode(encoder.encode(JSON.stringify({ iss: env.APPLE_AUTH_TEAM_ID, iat: now(), exp: now() + 300,
    aud: APPLE, sub: env.APPLE_AUTH_CLIENT_ID })));
  const pem = env.APPLE_AUTH_PRIVATE_KEY.replace(/-----[^-]+-----/g, "").replace(/\s/g, "");
  const key = await crypto.subtle.importKey("pkcs8", decode(pem), { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);
  const signature = await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, encoder.encode(`${header}.${payload}`));
  return `${header}.${payload}.${encode(signature)}`;
}

async function appleRequest(path, fields, env) {
  const response = await fetch(`${APPLE}/auth/${path}`, {
    method: "POST", headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ client_id: env.APPLE_AUTH_CLIENT_ID, client_secret: await clientSecret(env), ...fields }),
    signal: AbortSignal.timeout(15000),
  });
  if (!response.ok) throw fail(response.status >= 500 ? "apple_unavailable" : "apple_rejected", response.status >= 500 ? 503 : 401);
  return path === "revoke" ? null : response.json();
}

export async function seal(value, secret, owner) {
  const key = await crypto.subtle.importKey("raw", decode(secret), "AES-GCM", false, ["encrypt"]);
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const ciphertext = await crypto.subtle.encrypt({ name: "AES-GCM", iv, additionalData: encoder.encode(owner) }, key, encoder.encode(value));
  return `${encode(iv)}.${encode(ciphertext)}`;
}
export async function unseal(value, secret, owner) {
  const [iv, ciphertext] = value.split(".");
  const key = await crypto.subtle.importKey("raw", decode(secret), "AES-GCM", false, ["decrypt"]);
  return new TextDecoder().decode(await crypto.subtle.decrypt({ name: "AES-GCM", iv: decode(iv), additionalData: encoder.encode(owner) }, key, decode(ciphertext)));
}

async function bodyJSON(request) {
  if (!request.headers.get("content-type")?.startsWith("application/json")) throw fail("invalid_body");
  // Bound the stream as well as Content-Length, which is optional and untrusted.
  const reader = request.body?.getReader();
  if (!reader) throw fail("invalid_body");
  let size = 0, parts = [];
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    size += value.length;
    if (size > 16000) { await reader.cancel(); throw fail("too_large", 413); }
    parts.push(value);
  }
  try {
    const bytes = new Uint8Array(size); let at = 0;
    for (const part of parts) { bytes.set(part, at); at += part.length; }
    const body = JSON.parse(new TextDecoder().decode(bytes));
    if (!body || Array.isArray(body) || typeof body !== "object") throw new Error();
    return body;
  } catch { throw fail("invalid_body"); }
}

async function session(request, env) {
  const token = request.headers.get("authorization")?.match(/^Bearer ([A-Za-z0-9_-]{43})$/)?.[1];
  if (!token) throw fail("unauthorized", 401);
  const hash = await digest(token);
  const row = await env.AUTH_DB.prepare(`SELECT u.*, s.expires_at FROM auth_sessions s
    JOIN auth_users u ON u.id = s.user_id WHERE s.token_hash = ? AND s.expires_at > ?`).bind(hash, now()).first();
  if (!row) throw fail("unauthorized", 401);
  return { ...row, hash };
}
const publicUser = user => ({ id: user.id, name: user.name });
const configured = env => [env.AUTH_DB, env.AUTH_LIMITER, env.APPLE_AUTH_CLIENT_ID, env.APPLE_AUTH_TEAM_ID,
  env.APPLE_AUTH_KEY_ID, env.APPLE_AUTH_PRIVATE_KEY, env.AUTH_ENCRYPTION_KEY].every(Boolean);

export async function handleAuth(request, env, path) {
  try {
    if (path === "/auth/status" && request.method === "GET") return reply({ available: configured(env) });
    if (!configured(env)) return reply({ error: "not_configured" }, 503);
    const limited = await env.AUTH_LIMITER.limit({ key: `auth:${request.headers.get("cf-connecting-ip") || "unknown"}` });
    if (!limited.success) return reply({ error: "rate_limited" }, 429);
    if (path === "/auth/challenge" && request.method === "POST") {
      const id = random(), nonce = random();
      await env.AUTH_DB.batch([
        env.AUTH_DB.prepare("DELETE FROM auth_challenges WHERE expires_at <= ?").bind(now()),
        env.AUTH_DB.prepare("DELETE FROM auth_sessions WHERE expires_at <= ?").bind(now()),
        env.AUTH_DB.prepare("INSERT INTO auth_challenges (id, nonce, expires_at) VALUES (?, ?, ?)").bind(id, nonce, now() + 300),
      ]);
      return reply({ id, nonce });
    }
    if (path === "/auth/apple" && request.method === "POST") {
      const body = await bodyJSON(request);
      if (typeof body.challenge !== "string" || typeof body.code !== "string" || body.code.length > 4096 || !body.code ||
          typeof body.identityToken !== "string") throw fail("invalid_body");
      const challenge = await env.AUTH_DB.prepare("SELECT * FROM auth_challenges WHERE id = ? AND expires_at > ?")
        .bind(body.challenge, now()).first();
      if (!challenge) throw fail("expired_challenge", 401);
      let kid;
      try { kid = JSON.parse(new TextDecoder().decode(decode(body.identityToken.split(".")[0]))).kid; }
      catch { throw fail("invalid_identity", 401); }
      const keys = await appleKeys(kid);
      const claims = await verifyAppleToken(body.identityToken, env.APPLE_AUTH_CLIENT_ID, challenge.nonce, keys);
      // DELETE RETURNING makes two simultaneous exchanges of a challenge impossible.
      const consumed = await env.AUTH_DB.prepare("DELETE FROM auth_challenges WHERE id = ? AND expires_at > ? RETURNING id")
        .bind(challenge.id, now()).first();
      if (!consumed) throw fail("expired_challenge", 401);
      const tokens = await appleRequest("token", { code: body.code, grant_type: "authorization_code" }, env);
      const exchanged = await verifyAppleToken(tokens.id_token, env.APPLE_AUTH_CLIENT_ID, challenge.nonce, keys);
      if (exchanged.sub !== claims.sub || typeof tokens.refresh_token !== "string") throw fail("invalid_identity", 401);
      const id = await digest(`${env.APPLE_AUTH_CLIENT_ID}:${claims.sub}`);
      const name = typeof body.name === "string" ? body.name.replace(/[\p{Cc}\p{Cf}]/gu, "").trim().slice(0, 80) : "";
      const refresh = await seal(tokens.refresh_token, env.AUTH_ENCRYPTION_KEY, id);
      const token = random(), expiresAt = now() + SESSION_SECONDS;
      // Only Apple's stable subject identifies an account; never merge by email or client name.
      await env.AUTH_DB.batch([
        env.AUTH_DB.prepare(`INSERT INTO auth_users (id, name, refresh_token, created_at) VALUES (?, ?, ?, ?)
          ON CONFLICT(id) DO UPDATE SET refresh_token = excluded.refresh_token,
          name = CASE WHEN auth_users.name = '' THEN excluded.name ELSE auth_users.name END
          WHERE auth_users.deleting <= ?`).bind(id, name, refresh, now(), now()),
        env.AUTH_DB.prepare(`INSERT INTO auth_sessions (token_hash, user_id, expires_at)
          SELECT ?, id, ? FROM auth_users WHERE id = ? AND deleting <= ?`).bind(await digest(token), expiresAt, id, now()),
      ]);
      const user = await env.AUTH_DB.prepare("SELECT id, name, deleting FROM auth_users WHERE id = ?").bind(id).first();
      if (!user || user.deleting > now()) throw fail("deletion_pending", 409);
      return reply({ token, expiresAt, user: publicUser(user), deletionPending: !!user.deleting });
    }
    if (path === "/auth/session" && request.method === "GET") {
      const user = await session(request, env);
      return reply({ user: publicUser(user), expiresAt: user.expires_at, deletionPending: !!user.deleting });
    }
    if (path === "/auth/logout" && request.method === "POST") {
      const user = await session(request, env);
      await env.AUTH_DB.prepare("DELETE FROM auth_sessions WHERE token_hash = ?").bind(user.hash).run();
      return reply({ ok: true });
    }
    if (path === "/auth/account" && request.method === "DELETE") {
      const user = await session(request, env);
      // A bounded lease excludes sign-in while revocation is in flight. On failure the
      // pending account can reauthenticate, even if its previous session has expired.
      const lease = now() + 60;
      const locked = await env.AUTH_DB.prepare("UPDATE auth_users SET deleting = ? WHERE id = ? AND deleting <= ? RETURNING refresh_token")
        .bind(lease, user.id, now()).first();
      if (!locked) throw fail("deletion_pending", 409);
      // Keep the row and session on an Apple outage so the user can retry. No false success.
      try {
        await appleRequest("revoke", { token: await unseal(locked.refresh_token, env.AUTH_ENCRYPTION_KEY, user.id), token_type_hint: "refresh_token" }, env);
      } catch {
        await env.AUTH_DB.prepare("UPDATE auth_users SET deleting = -1 WHERE id = ? AND deleting = ?").bind(user.id, lease).run();
        throw fail("revocation_unavailable", 503);
      }
      await env.AUTH_DB.batch([
        env.AUTH_DB.prepare("DELETE FROM auth_sessions WHERE user_id = ?").bind(user.id),
        env.AUTH_DB.prepare("DELETE FROM auth_users WHERE id = ?").bind(user.id),
      ]);
      return reply({ ok: true });
    }
    return reply({ error: "not_found" }, 404);
  } catch (error) {
    // Tokens, names, Apple responses and signing material never enter logs or error bodies.
    return reply({ error: error.status ? error.message : "unavailable" }, error.status || 503);
  }
}
