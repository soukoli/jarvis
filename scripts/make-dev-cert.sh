#!/usr/bin/env zsh
# Create a self-signed "Jarvis Dev" code-signing certificate in the login keychain.
#
# Why: macOS binds Accessibility/Microphone grants to the app's signing identity. Ad-hoc signed
# builds change identity on every rebuild, so System Settings shows Jarvis as allowed while the
# new build is actually denied. A stable local certificate fixes that. scripts/build.sh and
# scripts/package.sh pick it up automatically.
#
# The first codesign with the new key may show a keychain prompt: choose "Always Allow".
set -euo pipefail
NAME="Jarvis Dev"
KC="$HOME/Library/Keychains/login.keychain-db"
if security find-identity -v -p codesigning | grep -q "\"$NAME\""; then
  echo "identity \"$NAME\" already exists"; exit 0
fi
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
openssl req -x509 -newkey rsa:2048 -nodes -keyout "$TMP/key.pem" -out "$TMP/cert.pem" -days 3650 \
  -subj "/CN=$NAME/O=Jarvis local development" \
  -addext "keyUsage=critical,digitalSignature" \
  -addext "extendedKeyUsage=critical,codeSigning" \
  -addext "basicConstraints=critical,CA:false" >/dev/null 2>&1
openssl pkcs12 -export -legacy -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -out "$TMP/dev.p12" -passout pass:jarvis -name "$NAME"
security import "$TMP/dev.p12" -k "$KC" -P jarvis -T /usr/bin/codesign -T /usr/bin/security
security add-trusted-cert -r trustRoot -p codeSign -k "$KC" "$TMP/cert.pem"
security find-identity -v -p codesigning | grep "$NAME"
echo "done. Remove old 'Jarvis' entries in System Settings → Privacy & Security → Accessibility, then grant the new one once."
