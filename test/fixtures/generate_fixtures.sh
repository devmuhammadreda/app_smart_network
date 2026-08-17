#!/usr/bin/env bash
# Regenerates the certificate fixtures used by the pinning tests.
#
# Every golden pin asserted in Dart is produced here by OpenSSL, so the tests
# cross-validate lib/src/security/spki_fingerprint.dart against an independent
# implementation rather than against itself.
#
# Usage:  ./test/fixtures/generate_fixtures.sh [scratch-dir]
#
# Intermediate private keys and CSRs are written to a scratch directory
# (default: a mktemp dir) and are deliberately left in place -- this script
# deletes nothing. They are throwaway test keys and never enter the repo.
#
# The real leaf certificate (tamweelymf1.com.pem) is NOT generated: it is a
# CA-issued production certificate copied in verbatim, and is the one fixture
# proving the parser handles a certificate off a real TLS handshake. Leaf
# certificates are public by construction; no private key is involved.
set -euo pipefail

OPENSSL="${OPENSSL:-openssl}"
# OpenSSL 3 unconditionally adds subjectKeyIdentifier/authorityKeyIdentifier
# when signing, which forces the certificate to v3 and makes a v1 fixture
# impossible with `x509 -req` alone (-clrext does not downgrade it either).
# macOS ships LibreSSL at /usr/bin/openssl, which still emits v1. Override
# OPENSSL_V1 if your platform puts a suitable binary elsewhere.
OPENSSL_V1="${OPENSSL_V1:-/usr/bin/openssl}"
cd "$(dirname "$0")"
tmp="${1:-$(mktemp -d)}"
mkdir -p "$tmp"

# Regenerating mints fresh key pairs, which changes every golden pin and breaks
# the tests until fixture_pins.dart is updated to match. Refuse to do that by
# accident: pass --force when you actually mean to, then paste the printed pins
# into test/fixtures/fixture_pins.dart.
if [ -f certs/v1_rsa.pem ] && [ "${FORCE:-}" != "1" ] && [ "${2:-}" != "--force" ]; then
  echo "Fixtures already exist; not regenerating (that would change every pin)."
  echo "Re-run with FORCE=1 to regenerate, then update test/fixtures/fixture_pins.dart."
  exit 0
fi

pin() { # <pem file> -> base64 SHA-256 of the SubjectPublicKeyInfo
  "$OPENSSL" x509 -in "$1" -pubkey -noout \
    | "$OPENSSL" pkey -pubin -outform der \
    | "$OPENSSL" dgst -sha256 -binary \
    | "$OPENSSL" enc -base64
}

# --- v1 RSA ---------------------------------------------------------------
# Signing a CSR with `x509 -req` and no -extfile yields a v1 certificate: no
# extensions, therefore no [0] EXPLICIT version tag, therefore
# subjectPublicKeyInfo sits at TBSCertificate index 5 instead of 6. This is
# the parser branch a real-world v3 certificate never reaches.
"$OPENSSL" req -new -newkey rsa:2048 -nodes \
  -keyout "$tmp/v1.key" -out "$tmp/v1.csr" -subj "/CN=v1-rsa.test" 2>/dev/null
"$OPENSSL_V1" x509 -req -in "$tmp/v1.csr" -signkey "$tmp/v1.key" \
  -days 36500 -out certs/v1_rsa.pem 2>/dev/null

# Fail loudly rather than silently shipping a second v3 fixture: the whole
# point of this file is to reach the no-version-tag branch of the parser.
if ! "$OPENSSL" x509 -in certs/v1_rsa.pem -noout -text | grep -q 'Version: 1'; then
  echo "ERROR: certs/v1_rsa.pem is not a v1 certificate." >&2
  echo "       Set OPENSSL_V1 to an openssl that emits v1 (LibreSSL does)." >&2
  exit 1
fi
"$OPENSSL" x509 -in certs/v1_rsa.pem -pubkey -noout > certs/v1_rsa.pub.pem

# --- v3 EC P-256 ----------------------------------------------------------
# Exercises a non-RSA SubjectPublicKeyInfo: a different algorithm OID and a
# much shorter key, so the digest cannot accidentally depend on RSA's shape.
"$OPENSSL" req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes \
  -keyout "$tmp/ec.key" -out certs/ec_p256.pem \
  -days 36500 -subj "/CN=ec-p256.test" 2>/dev/null
"$OPENSSL" x509 -in certs/ec_p256.pem -pubkey -noout > certs/ec_p256.pub.pem

# --- PUBLIC KEY extracted from the real leaf ------------------------------
# The round-trip fixture: same key as tamweelymf1.com.pem, presented as a bare
# SubjectPublicKeyInfo. Both must yield byte-identical pins.
"$OPENSSL" x509 -in certs/tamweelymf1.com.pem -pubkey -noout \
  > certs/tamweelymf1.com.pub.pem

# --- malformed inputs -----------------------------------------------------
printf 'this file is not a PEM block at all\n' > malformed/not_pem.txt

# Two certificates in one file: a chain. Rejected rather than silently pinning
# whichever certificate happens to be first.
cat certs/v1_rsa.pem certs/ec_p256.pem > malformed/chain.pem

# A valid PEM block whose label is neither CERTIFICATE nor PUBLIC KEY.
# A certificate signing request: a realistic thing to bundle by mistake, and
# unlike a private key it contains no secret, so pub.dev's secret scanner does
# not refuse to publish the fixture.
cp "$tmp/v1.csr" malformed/wrong_label.pem

# CERTIFICATE label over base64 that decodes cleanly but is not a certificate,
# so spkiPinFromDer returns null.
{ echo '-----BEGIN CERTIFICATE-----'
  printf 'bm90IGEgY2VydGlmaWNhdGUsIGp1c3QgcGxhaW4gdGV4dCBieXRlcw==\n'
  echo '-----END CERTIFICATE-----'; } > malformed/unparseable.pem

# CERTIFICATE label over bytes that are not valid base64 at all.
{ echo '-----BEGIN CERTIFICATE-----'
  echo '!!!! not base64 !!!!'
  echo '-----END CERTIFICATE-----'; } > malformed/bad_base64.pem

# --- report ---------------------------------------------------------------
echo "fixture pins:"
for f in certs/tamweelymf1.com.pem certs/v1_rsa.pem certs/ec_p256.pem; do
  printf '  %-28s sha256/%s\n' "$(basename "$f")" "$(pin "$f")"
done
