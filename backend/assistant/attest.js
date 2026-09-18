// App Attest: proof, from Apple, that a request comes from the real CueTake app on a real iPhone.
//
// POST /attest/challenge  (app token)                       -> { payload, signature }
// POST /attest/register   (app token) { keyID, attestation, challenge }
//                                                            -> { payload, signature }  (the device token)
//
// The phone makes a key in its Secure Enclave and asks Apple to attest it; this worker checks
// Apple's certificate chain up to the App Attest root below, that the attestation answers our
// challenge, and that it names this app — then signs a device token holding the key's public half.
// Later requests carry an assertion: that key's signature over a fresh challenge, which only the
// same app on the same phone can make.
//
// Nothing is stored. Challenges and device tokens are signed by this worker (see certificates.js),
// so any instance can check them.

import { signPayload, readSigned, base64url, fromBase64url } from "./certificates.js";

const TEAM_AND_BUNDLE = "XYB3NLV654.com.orhay.cuetake";
const CHALLENGE_SECONDS = 300;
const DEVICE_DAYS = 180;

// Apple App Attestation Root CA, from https://www.apple.com/certificateauthority/
// SHA-256 1C:B9:82:3B:A2:8B:A6:AD:2D:33:A0:06:94:1D:E2:AE:4F:51:3E:F1:D4:E8:31:B9:F7:E0:FA:7B:62:42:C9:32
const APPLE_ROOT = `MIICITCCAaegAwIBAgIQC/O+DvHN0uD7jG5yH2IXmDAKBggqhkjOPQQDAzBSMSYw
JAYDVQQDDB1BcHBsZSBBcHAgQXR0ZXN0YXRpb24gUm9vdCBDQTETMBEGA1UECgwK
QXBwbGUgSW5jLjETMBEGA1UECAwKQ2FsaWZvcm5pYTAeFw0yMDAzMTgxODMyNTNa
Fw00NTAzMTUwMDAwMDBaMFIxJjAkBgNVBAMMHUFwcGxlIEFwcCBBdHRlc3RhdGlv
biBSb290IENBMRMwEQYDVQQKDApBcHBsZSBJbmMuMRMwEQYDVQQIDApDYWxpZm9y
bmlhMHYwEAYHKoZIzj0CAQYFK4EEACIDYgAERTHhmLW07ATaFQIEVwTtT4dyctdh
NbJhFs/Ii2FdCgAHGbpphY3+d8qjuDngIN3WVhQUBHAoMeQ/cLiP1sOUtgjqK9au
Yen1mMEvRq9Sk3Jm5X8U62H+xTD3FE9TgS41o0IwQDAPBgNVHRMBAf8EBTADAQH/
MB0GA1UdDgQWBBSskRBTM72+aEH/pwyp5frq5eWKoTAOBgNVHQ8BAf8EBAMCAQYw
CgYIKoZIzj0EAwMDaAAwZQIwQgFGnByvsiVbpTKwSga0kP0e8EeDS4+sQmTvb7vn
53O5+FRXgeLhpJ06ysC5PrOyAjEAp5U4xDgEgllF7En3VcE3iexZZtKeYnpqtijV
oyFraWVIyd/dganmrduC1bmTBGwD`;

// ---------------------------------------------------------------- bytes

function fromBase64(text) {
  const raw = atob(String(text).replace(/\s+/g, ""));
  const bytes = new Uint8Array(raw.length);
  for (let i = 0; i < raw.length; i++) bytes[i] = raw.charCodeAt(i);
  return bytes;
}

function concat(...parts) {
  const out = new Uint8Array(parts.reduce((n, p) => n + p.length, 0));
  let at = 0;
  for (const part of parts) {
    out.set(part, at);
    at += part.length;
  }
  return out;
}

function equal(a, b) {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a[i] ^ b[i];
  return diff === 0;
}

async function sha256(bytes) {
  return new Uint8Array(await crypto.subtle.digest("SHA-256", bytes));
}

// ---------------------------------------------------------------- CBOR (the subset attestations use)

export function decodeCBOR(bytes) {
  let at = 0;
  function length(info) {
    if (info < 24) return info;
    if (info === 24) return bytes[at++];
    if (info === 25) { const v = (bytes[at] << 8) | bytes[at + 1]; at += 2; return v; }
    if (info === 26) { const v = ((bytes[at] << 24) >>> 0) + (bytes[at + 1] << 16) + (bytes[at + 2] << 8) + bytes[at + 3]; at += 4; return v; }
    throw new Error("cbor length");
  }
  function item() {
    const head = bytes[at++];
    const major = head >> 5;
    const info = head & 31;
    switch (major) {
      case 0: return length(info);
      case 1: return -1 - length(info);
      case 2: { const n = length(info); const v = bytes.slice(at, at + n); at += n; return v; }
      case 3: { const n = length(info); const v = new TextDecoder().decode(bytes.slice(at, at + n)); at += n; return v; }
      case 4: { const n = length(info); const list = []; for (let i = 0; i < n; i++) list.push(item()); return list; }
      case 5: { const n = length(info); const map = {}; for (let i = 0; i < n; i++) { const k = item(); map[k] = item(); } return map; }
      default: throw new Error("cbor type " + major);
    }
  }
  return item();
}

// ---------------------------------------------------------------- DER / X.509

function readDER(bytes, at = 0) {
  const tag = bytes[at];
  let length = bytes[at + 1];
  let header = 2;
  if (length & 0x80) {
    const count = length & 0x7f;
    length = 0;
    for (let i = 0; i < count; i++) length = length * 256 + bytes[at + 2 + i];
    header = 2 + count;
  }
  const end = at + header + length;
  // Offsets are within `bytes`; `raw` is the whole element, header included, wherever it came from.
  return { tag, start: at, header, end, raw: bytes.slice(at, end), value: bytes.slice(at + header, end) };
}

function children(node) {
  const list = [];
  let at = 0;
  while (at < node.value.length) {
    const child = readDER(node.value, at);
    list.push(child);
    at = child.end;
  }
  return list;
}

const OID = {
  ecdsaSHA256: "2a8648ce3d040302",
  ecdsaSHA384: "2a8648ce3d040303",
  p256: "2a8648ce3d030107",
  p384: "2b81040022",
  // 1.2.840.113635.100.8.2, where Apple writes the attestation nonce.
  nonce: "2a864886f763640802",
};

function hex(bytes) {
  return Array.from(bytes, (b) => b.toString(16).padStart(2, "0")).join("");
}

export function parseCertificate(der) {
  const cert = readDER(der);
  const [tbs, algorithm, signature] = children(cert);
  const fields = children(tbs);
  let index = fields[0].tag === 0xa0 ? 1 : 0; // explicit version
  index += 1; // serial
  index += 1; // signature algorithm inside tbs
  index += 1; // issuer
  const validity = children(fields[index++]);
  index += 1; // subject
  const spki = fields[index++];
  const extensions = fields.find((f) => f.tag === 0xa3);
  const spkiParts = children(spki);
  const curve = hex(children(spkiParts[0])[1].value);
  const point = spkiParts[1].value.slice(1); // bit string: skip the unused-bits byte
  return {
    tbs: tbs.raw,
    algorithm: hex(children(algorithm)[0].value),
    signature: signature.value.slice(1),
    spki: spki.raw,
    curve,
    point,
    notBefore: parseTime(validity[0]),
    notAfter: parseTime(validity[1]),
    extensions: extensions ? children(children(extensions)[0]) : [],
  };
}

function parseTime(node) {
  const text = new TextDecoder().decode(node.value);
  const full = node.tag === 0x17 ? (Number(text.slice(0, 2)) < 50 ? "20" : "19") + text : text;
  return Date.UTC(+full.slice(0, 4), +full.slice(4, 6) - 1, +full.slice(6, 8), +full.slice(8, 10), +full.slice(10, 12), +full.slice(12, 14));
}

/** An ECDSA signature in DER turned into the r‖s form WebCrypto verifies. */
function rawSignature(der, size) {
  const [r, s] = children(readDER(der));
  const fit = (v) => {
    let bytes = v.value;
    while (bytes.length > size && bytes[0] === 0) bytes = bytes.slice(1);
    const out = new Uint8Array(size);
    out.set(bytes, size - bytes.length);
    return out;
  };
  return concat(fit(r), fit(s));
}

async function verifiedBy(cert, issuer) {
  const namedCurve = issuer.curve === OID.p384 ? "P-384" : "P-256";
  const size = namedCurve === "P-384" ? 48 : 32;
  const hash = cert.algorithm === OID.ecdsaSHA384 ? "SHA-384" : "SHA-256";
  const key = await crypto.subtle.importKey("spki", issuer.spki, { name: "ECDSA", namedCurve }, false, ["verify"]);
  return crypto.subtle.verify({ name: "ECDSA", hash }, key, rawSignature(cert.signature, size), cert.tbs);
}

function current(cert, now) {
  return cert.notBefore <= now && now <= cert.notAfter;
}

/** The nonce Apple wrote into the leaf certificate's own extension. */
function certificateNonce(leaf) {
  for (const extension of leaf.extensions) {
    const parts = children(extension);
    if (hex(parts[0].value) !== OID.nonce) continue;
    const octet = parts[parts.length - 1];
    // OCTET STRING { SEQUENCE { [1] { OCTET STRING nonce } } }
    const sequence = readDER(octet.value);
    const tagged = children(sequence)[0];
    return readDER(tagged.value).value;
  }
  return null;
}

export async function rootCertificate() {
  return parseCertificate(fromBase64(APPLE_ROOT));
}

/**
 * Checks an attestation. Returns the attested key's public point (65 bytes, uncompressed) or
 * throws saying which check failed.
 */
export async function verifyAttestation({ keyID, attestation, clientData, now = Date.now(), allowDevelopment = false }) {
  const object = decodeCBOR(attestation);
  if (object.fmt !== "apple-appattest") throw new Error("format");
  const [leafDER, intermediateDER] = object.attStmt?.x5c ?? [];
  if (!leafDER || !intermediateDER) throw new Error("chain");
  const root = await rootCertificate();
  const intermediate = parseCertificate(intermediateDER);
  const leaf = parseCertificate(leafDER);
  if (!(await verifiedBy(intermediate, root)) || !(await verifiedBy(leaf, intermediate))) throw new Error("signature chain");
  if (!current(leaf, now) || !current(intermediate, now)) throw new Error("expired");

  const authData = object.authData;
  const clientDataHash = await sha256(clientData);
  const nonce = await sha256(concat(authData, clientDataHash));
  const written = certificateNonce(leaf);
  if (!written || !equal(written, nonce)) throw new Error("nonce");

  if (!equal(await sha256(leaf.point), keyID)) throw new Error("key id");
  if (!equal(authData.slice(0, 32), await sha256(new TextEncoder().encode(TEAM_AND_BUNDLE)))) throw new Error("app id");
  const counter = (authData[33] << 24) | (authData[34] << 16) | (authData[35] << 8) | authData[36];
  if (counter !== 0) throw new Error("counter");
  const aaguid = new TextDecoder().decode(authData.slice(37, 53));
  const production = "appattest\0\0\0\0\0\0\0";
  if (aaguid !== production && !(allowDevelopment && aaguid === "appattestdevelop")) throw new Error("environment");
  const idLength = (authData[53] << 8) | authData[54];
  if (!equal(authData.slice(55, 55 + idLength), keyID)) throw new Error("credential id");
  return leaf.point;
}

/** Checks an assertion made with an attested key over `clientData`. */
export async function verifyAssertion({ point, assertion, clientData }) {
  const object = decodeCBOR(assertion);
  const authData = object.authenticatorData;
  if (!authData || !object.signature) return false;
  if (!equal(authData.slice(0, 32), await sha256(new TextEncoder().encode(TEAM_AND_BUNDLE)))) return false;
  const nonce = await sha256(concat(authData, await sha256(clientData)));
  const key = await crypto.subtle.importKey(
    "raw", point, { name: "ECDSA", namedCurve: "P-256" }, false, ["verify"]
  );
  return crypto.subtle.verify({ name: "ECDSA", hash: "SHA-256" }, key, rawSignature(object.signature, 32), nonce);
}

// ---------------------------------------------------------------- routes

export async function handleChallenge(env) {
  const random = new Uint8Array(16);
  crypto.getRandomValues(random);
  const signed = await signPayload({ kind: "challenge", n: base64url(random), exp: Math.floor(Date.now() / 1000) + CHALLENGE_SECONDS }, env);
  if (!signed) return { status: 501, body: { error: "not configured" } };
  return { status: 200, body: signed };
}

async function freshChallenge(challenge, env) {
  const decoded = await readSigned(challenge, env);
  return decoded && decoded.kind === "challenge" && decoded.exp >= Date.now() / 1000 ? decoded : null;
}

export async function handleRegister(body, env) {
  if (!(await freshChallenge(body.challenge, env))) return { status: 401, body: { error: "challenge" } };
  try {
    const keyID = fromBase64(body.keyID);
    const point = await verifyAttestation({
      keyID,
      attestation: fromBase64(body.attestation),
      clientData: new TextEncoder().encode(body.challenge.payload),
      allowDevelopment: env.ATTEST_DEVELOPMENT === "1",
    });
    const token = await signPayload({
      kind: "device",
      key: base64url(point),
      exp: Math.floor(Date.now() / 1000) + DEVICE_DAYS * 86400,
    }, env);
    return { status: 200, body: token };
  } catch (error) {
    console.log("attestation refused:", error.message);
    return { status: 422, body: { error: "attestation", reason: error.message } };
  }
}

/**
 * Whether a request carries proof from an attested app: its device token, a fresh challenge and
 * the key's assertion over that challenge.
 */
export async function isAttested(proof, env) {
  if (!proof) return false;
  const device = await readSigned(proof.device, env);
  if (!device || device.kind !== "device" || device.exp < Date.now() / 1000) return false;
  if (!(await freshChallenge(proof.challenge, env))) return false;
  try {
    return await verifyAssertion({
      point: fromBase64url(device.key),
      assertion: fromBase64(proof.assertion),
      clientData: new TextEncoder().encode(proof.challenge.payload),
    });
  } catch {
    return false;
  }
}
