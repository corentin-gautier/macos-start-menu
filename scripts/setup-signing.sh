#!/bin/bash
# Creates a self-signed code signing certificate in the login keychain.
# Signing every build with the same certificate keeps the Accessibility
# permission across rebuilds (an ad-hoc signature changes with each build,
# and macOS then asks for the permission again).
set -euo pipefail

NAME="Mac Start Menu Local Signing"

if security find-certificate -c "$NAME" >/dev/null 2>&1; then
    echo "Certificate \"$NAME\" already exists."
    exit 0
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
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
EOF

openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -keyout "$TMP/key.pem" -out "$TMP/cert.pem" -config "$TMP/cert.cnf" 2>/dev/null
# macOS `security` only reads PKCS#12 files with the legacy algorithms.
LEGACY=""
openssl pkcs12 -help 2>&1 | grep -q -- "-legacy" && LEGACY="-legacy"
openssl pkcs12 -export $LEGACY -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
    -out "$TMP/identity.p12" -passout pass:startmenu -name "$NAME"

security import "$TMP/identity.p12" -k "$HOME/Library/Keychains/login.keychain-db" \
    -P startmenu -T /usr/bin/codesign >/dev/null

echo "Created certificate \"$NAME\" in the login keychain."
