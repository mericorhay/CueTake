import test from "node:test";
import assert from "node:assert/strict";
import { DatabaseSync } from "node:sqlite";
import { readFileSync } from "node:fs";
import { handleAuth, verifyAppleToken, encode, seal, unseal } from "./auth.mjs";

const rsa = await crypto.subtle.generateKey({ name: "RSASSA-PKCS1-v1_5", modulusLength: 2048,
  publicExponent: new Uint8Array([1, 0, 1]), hash: "SHA-256" }, true, ["sign", "verify"]);
const jwk = { ...await crypto.subtle.exportKey("jwk", rsa.publicKey), kid: "test-key", alg: "RS256", use: "sig" };
const ec = await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"]);
const privateKey = `-----BEGIN PRIVATE KEY-----\n${encode(await crypto.subtle.exportKey("pkcs8", ec.privateKey))}\n-----END PRIVATE KEY-----`;
const encryptionKey = encode(crypto.getRandomValues(new Uint8Array(32)));
const encoder = new TextEncoder();
const timestamp = () => Math.floor(Date.now() / 1000);
async function token(nonce, overrides = {}, signingKey = rsa.privateKey) {
  const header = encode(encoder.encode(JSON.stringify({ alg: "RS256", kid: jwk.kid })));
  const payload = encode(encoder.encode(JSON.stringify({ iss: "https://appleid.apple.com", aud: "com.orhay.cuetake",
    sub: "apple-user-one", nonce, iat: timestamp(), exp: timestamp() + 300, ...overrides })));
  return `${header}.${payload}.${encode(await crypto.subtle.sign("RSASSA-PKCS1-v1_5", signingKey, encoder.encode(`${header}.${payload}`)))}`;
}

function fixture() {
  const db = new DatabaseSync(":memory:");
  db.exec(readFileSync(new URL("./migrations/0001_accounts.sql", import.meta.url), "utf8"));
  const prepare = sql => ({
    values: [],
    bind(...values) { this.values = values; return this; },
    async first() { return db.prepare(sql).get(...this.values) || null; },
    async run() { return db.prepare(sql).run(...this.values); },
  });
  const env = { AUTH_DB: { prepare, async batch(statements) {
    db.exec("BEGIN");
    try { const result = []; for (const s of statements) result.push(await s.run()); db.exec("COMMIT"); return result; }
    catch (error) { db.exec("ROLLBACK"); throw error; }
  } }, AUTH_LIMITER: { async limit() { return { success: true }; } },
  APPLE_AUTH_CLIENT_ID: "com.orhay.cuetake", APPLE_AUTH_TEAM_ID: "TEAM", APPLE_AUTH_KEY_ID: "KEY",
  APPLE_AUTH_PRIVATE_KEY: privateKey, AUTH_ENCRYPTION_KEY: encryptionKey };
  let exchangeToken, revokeStatus = 200, exchanges = 0;
  const originalFetch = globalThis.fetch;
  globalThis.fetch = async (url, options) => {
    if (url.endsWith("/auth/keys")) return Response.json({ keys: [jwk] });
    if (url.endsWith("/auth/token")) {
      exchanges++;
      assert.equal(options.body.get("grant_type"), "authorization_code");
      return Response.json({ id_token: exchangeToken, refresh_token: "secret-apple-refresh" });
    }
    if (url.endsWith("/auth/revoke")) {
      assert.equal(options.body.get("token"), "secret-apple-refresh");
      return new Response("", { status: revokeStatus });
    }
    throw Error("Unexpected outbound request");
  };
  async function call(path, method = "GET", body, bearer) {
    return handleAuth(new Request(`https://example.com/auth/${path}`, { method,
      headers: { "content-type": "application/json", ...(bearer ? { authorization: `Bearer ${bearer}` } : {}) },
      body: body ? JSON.stringify(body) : undefined }), env, `/auth/${path}`);
  }
  async function credentials() {
    const challenge = await (await call("challenge", "POST")).json();
    exchangeToken = await token(challenge.nonce);
    return { challenge: challenge.id, identityToken: exchangeToken, code: "one-time-code", name: "Creator" };
  }
  async function login() { return (await call("apple", "POST", await credentials())).json(); }
  return { env, db, call, login, credentials, setRevoke: status => { revokeStatus = status; },
    exchanges: () => exchanges, close() { globalThis.fetch = originalFetch; db.close(); } };
}

test("Apple signature, issuer, audience, expiry, nonce and algorithm are mandatory", async () => {
  const valid = await token("nonce");
  assert.equal((await verifyAppleToken(valid, "com.orhay.cuetake", "nonce", [jwk])).sub, "apple-user-one");
  for (const override of [{ aud: "other.app" }, { iss: "https://attacker.example" }, { exp: timestamp() - 1 },
    { nonce: "different" }, { iat: timestamp() + 3600 }, { iat: timestamp() - 1000 }, { sub: "" }]) {
    await assert.rejects(verifyAppleToken(await token("nonce", override), "com.orhay.cuetake", "nonce", [jwk]));
  }
  const parts = valid.split(".");
  parts[0] = encode(encoder.encode(JSON.stringify({ alg: "none", kid: jwk.kid })));
  await assert.rejects(verifyAppleToken(parts.join("."), "com.orhay.cuetake", "nonce", [jwk]));
  const impostor = await crypto.subtle.generateKey({ name: "RSASSA-PKCS1-v1_5", modulusLength: 2048,
    publicExponent: new Uint8Array([1,0,1]), hash: "SHA-256" }, true, ["sign", "verify"]);
  await assert.rejects(verifyAppleToken(await token("nonce", {}, impostor.privateKey), "com.orhay.cuetake", "nonce", [jwk]));
});

test("refresh credentials are authenticated, encrypted and bound to one account", async () => {
  const encrypted = await seal("apple-refresh", encryptionKey, "owner");
  assert.ok(!encrypted.includes("apple-refresh"));
  assert.equal(await unseal(encrypted, encryptionKey, "owner"), "apple-refresh");
  await assert.rejects(unseal(encrypted, encryptionKey, "someone-else"));
});

test("login → restore → logout uses hashed, immediately revocable sessions", async () => {
  const f = fixture();
  try {
    const session = await f.login();
    assert.equal(session.user.name, "Creator");
    assert.equal(session.token.length, 43);
    const stored = f.db.prepare("SELECT * FROM auth_sessions").get();
    assert.notEqual(stored.token_hash, session.token);
    assert.ok(!f.db.prepare("SELECT refresh_token FROM auth_users").get().refresh_token.includes("secret-apple-refresh"));
    assert.equal((await f.call("session", "GET", null, session.token)).status, 200);
    assert.equal((await f.call("logout", "POST", null, session.token)).status, 200);
    assert.equal((await f.call("session", "GET", null, session.token)).status, 401);
  } finally { f.close(); }
});

test("parallel replay consumes a challenge exactly once before Apple exchange", async () => {
  const f = fixture();
  try {
    const body = await f.credentials();
    const responses = await Promise.all([f.call("apple", "POST", body), f.call("apple", "POST", body)]);
    assert.deepEqual(responses.map(r => r.status).sort(), [200, 401]);
    assert.equal(f.exchanges(), 1);
  } finally { f.close(); }
});

test("account deletion revokes Apple and removes all sessions, including other devices", async () => {
  const f = fixture();
  try {
    const first = await f.login(), second = await f.login();
    assert.equal(first.user.id, second.user.id);
    assert.equal((await f.call("account", "DELETE", null, first.token)).status, 200);
    assert.equal((await f.call("session", "GET", null, second.token)).status, 401);
    assert.equal(f.db.prepare("SELECT count(*) AS n FROM auth_users").get().n, 0);
  } finally { f.close(); }
});

test("Apple outage never reports deletion success; reauthentication can resume deletion", async () => {
  const f = fixture();
  try {
    const session = await f.login();
    f.setRevoke(503);
    assert.equal((await f.call("account", "DELETE", null, session.token)).status, 503);
    const status = await (await f.call("session", "GET", null, session.token)).json();
    assert.equal(status.deletionPending, true);
    const reauthenticated = await f.login();
    assert.equal(reauthenticated.deletionPending, true);
    f.setRevoke(200);
    assert.equal((await f.call("account", "DELETE", null, reauthenticated.token)).status, 200);
  } finally { f.close(); }
});

test("missing setup, invalid credentials, rate limits, expired challenges and oversized bodies fail closed", async () => {
  assert.equal((await handleAuth(new Request("https://example.com/auth/status"), {}, "/auth/status")).status, 200);
  assert.equal((await handleAuth(new Request("https://example.com/auth/challenge", { method: "POST" }), {}, "/auth/challenge")).status, 503);
  const f = fixture();
  try {
    assert.equal((await f.call("session")).status, 401);
    const body = await f.credentials();
    f.db.exec("UPDATE auth_challenges SET expires_at = 0");
    assert.equal((await f.call("apple", "POST", body)).status, 401);
    assert.equal((await f.call("apple", "POST", { name: "x".repeat(17000) })).status, 413);
    f.env.AUTH_LIMITER.limit = async () => ({ success: false });
    assert.equal((await f.call("challenge", "POST")).status, 429);
  } finally { f.close(); }
});

test("an active deletion lease excludes new sessions and a second deletion", async () => {
  const f = fixture();
  try {
    const session = await f.login();
    f.db.prepare("UPDATE auth_users SET deleting = ?").run(timestamp() + 60);
    assert.equal((await f.call("account", "DELETE", null, session.token)).status, 409);
    assert.equal((await f.call("apple", "POST", await f.credentials())).status, 409);
    assert.equal(f.db.prepare("SELECT count(*) AS n FROM auth_sessions").get().n, 1);
  } finally { f.close(); }
});

test("expired or fabricated sessions cannot read or delete an account", async () => {
  const f = fixture();
  try {
    const session = await f.login();
    const fabricated = encode(crypto.getRandomValues(new Uint8Array(32)));
    assert.equal((await f.call("account", "DELETE", null, fabricated)).status, 401);
    f.db.exec("UPDATE auth_sessions SET expires_at = 0");
    assert.equal((await f.call("session", "GET", null, session.token)).status, 401);
    assert.equal((await f.call("account", "DELETE", null, session.token)).status, 401);
    assert.equal(f.db.prepare("SELECT count(*) AS n FROM auth_users").get().n, 1);
  } finally { f.close(); }
});
