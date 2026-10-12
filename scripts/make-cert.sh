#!/bin/bash
# Creates the self-signed code-signing identity every build is signed with (run once).
# A stable identity lets macOS keep the Accessibility grant across rebuilds and updates.
set -euo pipefail
NAME="ping-signals Local Signing"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
if security find-identity -v -p codesigning | grep -q "$NAME"; then
  echo "Identity already exists: $NAME"; exit 0
fi
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/cert.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOF
openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$TMP/cert.cnf" \
  -keyout "$TMP/key.pem" -out "$TMP/cert.pem"
openssl pkcs12 -export -legacy -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -name "$NAME" \
  -passout pass:ps -out "$TMP/id.p12"
security import "$TMP/id.p12" -k "$KEYCHAIN" -P ps -T /usr/bin/codesign
# Asks for the login password once (GUI prompt): trusts the certificate for code signing.
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$TMP/cert.pem"
security find-identity -v -p codesigning | grep "$NAME"
