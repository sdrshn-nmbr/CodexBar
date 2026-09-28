#!/usr/bin/env bash
# Creates a self-signed code-signing identity in the login keychain for signing glance builds.
# A stable signature lets macOS keep privacy grants and Keychain access across automatic updates.
# Trusting the certificate for code signing asks for your Mac password once.
set -euo pipefail

NAME="${GLANCE_SIGN_IDENTITY:-CodexBar Glance Local Signing}"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -p codesigning -v | grep -q "\"$NAME\""; then
  echo "Signing identity '$NAME' already exists."
  exit 0
fi

work=$(mktemp -d /tmp/glance-sign.XXXX)
cd "$work"
cat >cert.cnf <<EOF
[ req ]
distinguished_name = dn
x509_extensions = ext
prompt = no
[ dn ]
CN = $NAME
[ ext ]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
subjectKeyIdentifier = hash
EOF

/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -keyout key.pem -out cert.pem -config cert.cnf 2>/dev/null
pass=$(/usr/bin/openssl rand -hex 16)
/usr/bin/openssl pkcs12 -export -inkey key.pem -in cert.pem -name "$NAME" -out id.p12 -passout "pass:$pass"
# Only codesign may use the key, so background syncs sign without Keychain prompts.
security import id.p12 -k "$KEYCHAIN" -P "$pass" -T /usr/bin/codesign
unlink key.pem
unlink id.p12
echo "Trusting '$NAME' for code signing; macOS will ask for your password."
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" cert.pem
security find-identity -p codesigning -v | grep "\"$NAME\""

