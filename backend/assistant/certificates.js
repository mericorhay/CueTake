// Certificates: signed by this worker, checked by anyone.
//
// POST /certify  (app token)  { level, name, hours, projects, workflowRuns, tasks, installID, issued }
//   -> { payload, signature, verifyURL }
// GET  /verify?c=<payload>&s=<signature>   a page anyone can open, saying whether it holds
// GET  /certificate-key                    the public key, for anyone who wants to check by hand
// POST /review   (app token)  { installID, projectID, title, locale, document }
//   -> { score, passed, strengths, improvements, payload, signature }
//   A finished project read against the rubric below by the model, and the verdict signed, so
//   /certify can trust a Workflow Specialist's review came from here and not from the phone.
//
// Nothing is stored. The signature is the record: a certificate this worker signed verifies for
// ever, one it did not never does. The private key lives only in the secret CERT_SIGNING_KEY
// (an Ed25519 JWK; make one with `node make-cert-key.mjs | npx wrangler secret put CERT_SIGNING_KEY`).
//
// What the signature proves is that CueTake issued the certificate for the numbers in it. The
// numbers come from the phone; App Attest is what will, later, prove the phone ran the real app.

import { isAttested } from "./attest.js";

const LEVELS = {
  creator: { title: "CueTake Creator", hours: 20, projects: 8, tasks: 0, runs: 0 },
  advancedCreator: { title: "CueTake Advanced Creator", hours: 40, projects: 15, tasks: 11, runs: 0 },
  workflowSpecialist: { title: "CueTake Workflow Specialist", hours: 60, projects: 25, tasks: 11, runs: 10 },
};

export function base64url(bytes) {
  let text = "";
  for (const byte of new Uint8Array(bytes)) text += String.fromCharCode(byte);
  return btoa(text).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

export function fromBase64url(text) {
  const padded = text.replace(/-/g, "+").replace(/_/g, "/") + "===".slice((text.length + 3) % 4);
  const raw = atob(padded);
  const bytes = new Uint8Array(raw.length);
  for (let i = 0; i < raw.length; i++) bytes[i] = raw.charCodeAt(i);
  return bytes;
}

function signingJWK(env) {
  if (!env.CERT_SIGNING_KEY) return null;
  try {
    return JSON.parse(env.CERT_SIGNING_KEY);
  } catch {
    return null;
  }
}

async function privateKey(env) {
  const jwk = signingJWK(env);
  if (!jwk) return null;
  return crypto.subtle.importKey("jwk", jwk, { name: "Ed25519" }, false, ["sign"]);
}

async function publicKey(env) {
  const jwk = signingJWK(env);
  if (!jwk) return null;
  return crypto.subtle.importKey("jwk", { kty: jwk.kty, crv: jwk.crv, x: jwk.x }, { name: "Ed25519" }, false, ["verify"]);
}

function clean(text, limit) {
  return String(text ?? "").replace(/[\u0000-\u001f<>]/g, "").trim().slice(0, limit);
}

export async function handleCertify(body, env, origin) {
  const key = await privateKey(env);
  if (!key) return { status: 501, body: { error: "certificates not configured" } };
  const level = LEVELS[body.level];
  if (!level) return { status: 400, body: { error: "unknown level" } };
  const hours = Number(body.hours);
  const projects = Number(body.projects);
  const runs = Number(body.workflowRuns ?? 0);
  const tasks = Array.isArray(body.tasks) ? body.tasks.length : 0;
  // The worker applies the same bar the app does: a request below it is not signed, whatever it says.
  if (!(hours >= level.hours) || !(projects >= level.projects) || tasks < level.tasks || runs < level.runs) {
    return { status: 422, body: { error: "requirements not met" } };
  }
  // Proof the request came from the real app. Required once REQUIRE_ATTEST is set; until then a
  // certificate that has it says so.
  const attested = await isAttested(body.attest, env);
  if (env.REQUIRE_ATTEST === "1" && !attested) return { status: 403, body: { error: "attestation required" } };
  if (body.level === "workflowSpecialist") {
    const review = await readSigned(body.review, env);
    if (!review || review.kind !== "review" || !review.passed || review.install !== clean(body.installID, 40)) {
      return { status: 422, body: { error: "review required" } };
    }
  }
  const issued = new Date().toISOString().slice(0, 10);
  const payload = {
    v: 1,
    id: clean(body.id, 20),
    level: body.level,
    title: level.title,
    name: clean(body.name, 60),
    hours: Math.floor(hours),
    projects: Math.floor(projects),
    issued,
    install: clean(body.installID, 40),
    attested,
  };
  const encoded = base64url(new TextEncoder().encode(JSON.stringify(payload)));
  const signature = base64url(await crypto.subtle.sign({ name: "Ed25519" }, key, new TextEncoder().encode(encoded)));
  const verifyURL = `${origin}/verify?c=${encoded}&s=${signature}`;
  return { status: 200, body: { payload: encoded, signature, verifyURL } };
}

export async function handleVerify(url, env) {
  const encoded = url.searchParams.get("c") || "";
  const signature = url.searchParams.get("s") || "";
  let payload = null;
  let valid = false;
  try {
    const key = await publicKey(env);
    if (key && encoded && signature) {
      valid = await crypto.subtle.verify({ name: "Ed25519" }, key, fromBase64url(signature), new TextEncoder().encode(encoded));
      payload = JSON.parse(new TextDecoder().decode(fromBase64url(encoded)));
    }
  } catch {
    valid = false;
  }
  return new Response(page(valid ? payload : null), {
    status: valid ? 200 : 404,
    headers: { "content-type": "text/html; charset=utf-8", "cache-control": "public, max-age=300" },
  });
}

export async function handleCertificateKey(env) {
  const jwk = signingJWK(env);
  if (!jwk) return new Response("not configured", { status: 501 });
  return new Response(JSON.stringify({ kty: jwk.kty, crv: jwk.crv, x: jwk.x }), {
    headers: { "content-type": "application/json" },
  });
}

/** A payload this worker signed, decoded; null when the signature does not hold. */
export async function readSigned(signed, env) {
  if (!signed || typeof signed.payload !== "string" || typeof signed.signature !== "string") return null;
  try {
    const key = await publicKey(env);
    if (!key) return null;
    const ok = await crypto.subtle.verify(
      { name: "Ed25519" }, key, fromBase64url(signed.signature), new TextEncoder().encode(signed.payload)
    );
    return ok ? JSON.parse(new TextDecoder().decode(fromBase64url(signed.payload))) : null;
  } catch {
    return null;
  }
}

export async function signPayload(payload, env) {
  const key = await privateKey(env);
  if (!key) return null;
  const encoded = base64url(new TextEncoder().encode(JSON.stringify(payload)));
  const signature = base64url(await crypto.subtle.sign({ name: "Ed25519" }, key, new TextEncoder().encode(encoded)));
  return { payload: encoded, signature };
}

export const REVIEW_PROMPT = `You review a finished short video project made in CueTake, an iPhone editor for people who talk to camera, for the "Workflow Specialist" certificate. You receive the project as JSON: clips with their words and captions, effects, overlays, audio, added videos, camera moves, transitions and style.

Judge the craft the project shows, not the topic. Score each criterion 0-20, add them for a total of 0-100:
1. Structure: a clear opening hook in the first seconds, a point, an ending or call to action.
2. Pacing: dead air, fillers and false starts cut; clips neither rushed nor dragging.
3. Captions: present, readable, timed to the words, a style that suits the video.
4. Sound: voice clear; music, if any, sits under the voice (levels, ducking, fades).
5. Visual polish: framing, a consistent look, overlays or effects that serve the message rather than decorate.

Be strict and fair: 70 is a solid, publishable video; 90 is excellent. A project with almost nothing in it scores low.
Answer with ONE JSON object only: {"scores":[n,n,n,n,n],"strengths":["...","..."],"improvements":["...","..."]}
Two or three short, specific items in each list, in the language of <locale>, naming what in the project you mean.`;

export async function handleReview(body, env, ask) {
  if (!(await privateKey(env))) return { status: 501, body: { error: "certificates not configured" } };
  // About five thousand tokens: under the free tier's per-minute budget with the rubric and reply.
  const document = String(body.document || "").slice(0, 20_000);
  if (env.REQUIRE_ATTEST === "1" && !(await isAttested(body.attest, env))) {
    return { status: 403, body: { error: "attestation required" } };
  }
  if (document.length < 50) return { status: 400, body: { error: "document is required" } };
  const content =
    `<project title="${clean(body.title, 80)}">
${document}
</project>
<locale>${clean(body.locale, 20)}</locale>`;
  const answer = await ask(REVIEW_PROMPT, content, 1500);
  if (answer.error) return { status: 502, body: { error: "upstream" } };
  let verdict = answer.reply;
  if (typeof verdict === "string") {
    try { verdict = JSON.parse(verdict.slice(verdict.indexOf("{"), verdict.lastIndexOf("}") + 1)); } catch { verdict = null; }
  }
  const scores = Array.isArray(verdict?.scores) ? verdict.scores.slice(0, 5).map((n) => Math.min(20, Math.max(0, Number(n) || 0))) : [];
  if (scores.length !== 5) return { status: 502, body: { error: "unreadable review" } };
  const score = Math.round(scores.reduce((a, b) => a + b, 0));
  const passed = score >= 70;
  const list = (items) => (Array.isArray(items) ? items.slice(0, 3).map((t) => clean(t, 200)).filter(Boolean) : []);
  const signed = await signPayload({
    v: 1,
    kind: "review",
    install: clean(body.installID, 40),
    project: clean(body.projectID, 40),
    score,
    passed,
    date: new Date().toISOString().slice(0, 10),
  }, env);
  return {
    status: 200,
    body: { score, passed, strengths: list(verdict.strengths), improvements: list(verdict.improvements), ...signed },
  };
}

function escape(text) {
  return String(text ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]);
}

function page(payload) {
  const ok = Boolean(payload);
  const heading = ok ? "Geçerli sertifika · Valid certificate" : "Doğrulanamadı · Not verified";
  const body = ok
    ? `<p class="level">${escape(payload.title)}</p>
       ${payload.name ? `<p class="name">${escape(payload.name)}</p>` : ""}
       <dl>
         <dt>Sertifika · Certificate</dt><dd>${escape(payload.id)}</dd>
         <dt>Verilme · Issued</dt><dd>${escape(payload.issued)}</dd>
         <dt>Aktif çalışma · Active work</dt><dd>${escape(payload.hours)} sa · h</dd>
         <dt>Bitmiş proje · Finished projects</dt><dd>${escape(payload.projects)}</dd>
         <dt>Cihaz · Device</dt><dd>${payload.attested ? "Apple App Attest ✓" : "—"}</dd>
       </dl>
       <p class="note">Bu sertifika CueTake tarafından imzalandı. · Signed by CueTake.</p>`
    : `<p class="note">Bu bağlantı CueTake tarafından imzalanmış bir sertifikaya ait değil ya da değiştirilmiş. · This link is not a certificate signed by CueTake, or it was altered.</p>`;
  return `<!doctype html><html lang="tr"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>CueTake · ${ok ? "Sertifika" : "Doğrulanamadı"}</title>
<style>
:root{color-scheme:dark;--bg:#0b0b0d;--ink:#f5f5f7;--dim:#a3a3aa;--ok:#c8ff3d;--bad:#ff5a4e}
*{box-sizing:border-box}body{margin:0;min-height:100vh;display:grid;place-items:center;background:var(--bg);color:var(--ink);font:16px/1.5 -apple-system,system-ui,sans-serif;padding:24px}
main{max-width:440px;width:100%;border:1px solid #2a2a30;border-radius:28px;padding:32px;background:linear-gradient(160deg,#17171b,#0f0f12)}
.mark{font-weight:800;letter-spacing:.02em;color:var(--dim);font-size:13px;text-transform:uppercase}
h1{font-size:22px;margin:10px 0 18px;color:${ok ? "var(--ok)" : "var(--bad)"}}
.level{font-size:26px;font-weight:800;margin:0}.name{font-size:18px;margin:6px 0 0}
dl{display:grid;grid-template-columns:auto 1fr;gap:8px 16px;margin:24px 0;font-variant-numeric:tabular-nums}
dt{color:var(--dim);font-size:13px}dd{margin:0;text-align:right}
.note{color:var(--dim);font-size:13px;margin:0}
</style></head><body><main><div class="mark">CueTake</div><h1>${heading}</h1>${body}</main></body></html>`;
}
