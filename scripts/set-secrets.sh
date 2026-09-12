#!/usr/bin/env bash
# Loads the signing secrets into the repo's Actions secrets.
#
# Run it from Git Bash:
#   bash scripts/set-secrets.sh
#
# Every value is read from a local file or typed at the prompt; nothing is
# echoed back and nothing leaves this machine except the gh API call.
set -euo pipefail

REPO="${REPO:-Galapagos-GCS/CueTake}"
DESKTOP="$HOME/Desktop"
DOWNLOADS="$HOME/Downloads"

ok()   { printf '  \033[32m✓\033[0m %s\n' "$1"; }
bad()  { printf '  \033[31m✗\033[0m %s\n' "$1"; }
info() { printf '\n\033[1m%s\033[0m\n' "$1"; }

# A previous attempt piped the output of a command that did not exist, which
# silently stored an empty secret. Refuse to send anything empty.
set_from_file() {
  local name="$1" path="$2"
  if [ ! -f "$path" ]; then bad "$name — dosya yok: $path"; return 1; fi
  if [ ! -s "$path" ]; then bad "$name — dosya bos: $path"; return 1; fi
  gh secret set "$name" -R "$REPO" < "$path"
  ok "$name  ($(wc -c < "$path" | tr -d ' ') bayt)"
}

info "Dosyadan okunan secret'lar"

set_from_file IOS_DISTRIBUTION_CERT_P12 "$DESKTOP/IOS_DISTRIBUTION_CERT_P12.txt"
set_from_file IOS_PROVISIONING_PROFILE  "$DESKTOP/IOS_PROVISIONING_PROFILE.txt"

# The key file is named after its own key id, so find it rather than hardcode it.
AUTHKEY=$(ls -1 "$DOWNLOADS"/AuthKey_*.p8 2>/dev/null | head -1 || true)
if [ -n "$AUTHKEY" ]; then
  set_from_file APP_STORE_CONNECT_API_KEY "$AUTHKEY"
  KEY_ID=$(basename "$AUTHKEY" .p8 | sed 's/^AuthKey_//')
  gh secret set APP_STORE_CONNECT_API_KEY_ID -R "$REPO" -b "$KEY_ID"
  ok "APP_STORE_CONNECT_API_KEY_ID  ($KEY_ID)"
else
  bad "AuthKey_*.p8 bulunamadi: $DOWNLOADS"
fi

gh secret set APPLE_TEAM_ID -R "$REPO" -b "XYB3NLV654"
ok "APPLE_TEAM_ID  (XYB3NLV654)"

info "Issuer ID"
echo "  App Store Connect > Users and Access > Integrations, sayfanin ustunde."
echo "  36 karakterlik UUID olmali: 8-4-4-4-12 haneli, tireli."

# The last two attempts stored 17 and then 12 characters, so the format is
# checked here rather than discovered 20 minutes into a TestFlight run.
while true; do
  read -rsp "  Issuer ID: " ISSUER; echo
  if [[ "$ISSUER" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]]; then
    printf '%s' "$ISSUER" | gh secret set APP_STORE_CONNECT_ISSUER_ID -R "$REPO"
    ok "APP_STORE_CONNECT_ISSUER_ID  (${#ISSUER} karakter, biçim dogru)"
    break
  fi
  bad "Bu bir UUID degil (${#ISSUER} karakter girildi). Tekrar dene, bos birakip Ctrl+C ile cikabilirsin."
done

info "Sertifika parolasi"
echo "  Zaten girdiysen bos birakip Enter'a bas, dokunulmaz."
read -rsp "  p12 parolasi: " P12PASS; echo
if [ -n "$P12PASS" ]; then
  printf '%s' "$P12PASS" | gh secret set IOS_CERTIFICATE_PASSWORD -R "$REPO"
  ok "IOS_CERTIFICATE_PASSWORD  (${#P12PASS} karakter)"
else
  ok "IOS_CERTIFICATE_PASSWORD  (degistirilmedi)"
fi

info "Repodaki secret'lar"
gh secret list -R "$REPO"
