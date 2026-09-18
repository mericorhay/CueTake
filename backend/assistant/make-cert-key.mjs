// Makes the key that signs CueTake certificates and prints it, private half included, for
// piping straight into the worker's secrets — it is never written to disk:
//
//   node make-cert-key.mjs | npx wrangler secret put CERT_SIGNING_KEY
//
// Run it once. A new key makes every certificate signed with the old one stop verifying.
const pair = await crypto.subtle.generateKey({ name: "Ed25519" }, true, ["sign", "verify"]);
const jwk = await crypto.subtle.exportKey("jwk", pair.privateKey);
process.stdout.write(JSON.stringify(jwk));
