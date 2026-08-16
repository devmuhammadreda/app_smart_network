import 'dart:convert';
import 'dart:typed_data';

import 'package:asn1lib/asn1lib.dart';
import 'package:crypto/crypto.dart';

/// Prefix every pin carries, matching HPKP and OkHttp's `CertificatePinner`.
const String kPinPrefix = 'sha256/';

/// Length in bytes of a SHA-256 digest.
const int kSha256DigestLength = 32;

/// Index of `subjectPublicKeyInfo` inside a v1 `TBSCertificate`.
///
/// RFC 5280 orders the fields serialNumber, signature, issuer, validity,
/// subject, subjectPublicKeyInfo. A v2/v3 certificate prefixes them with an
/// explicit `[0] version` tag, shifting everything one slot to the right.
const int _kSpkiIndexV1 = 5;

/// BER tag of the `[0] EXPLICIT Version` field of a `TBSCertificate`.
const int _kVersionTag = 0xA0;

/// Returns the `sha256/<base64>` SPKI pin for the DER-encoded certificate
/// [der], or `null` when [der] cannot be parsed as a certificate.
///
/// The digest covers the `SubjectPublicKeyInfo` structure only — not the whole
/// certificate — so a pin survives certificate renewal as long as the key pair
/// is reused. It is byte-for-byte the output of:
///
/// ```bash
/// openssl x509 -pubkey -noout | openssl pkey -pubin -outform der \
///   | openssl dgst -sha256 -binary | openssl enc -base64
/// ```
///
/// Returning `null` is the *failure* signal and callers must treat it as a
/// rejection: a certificate this function cannot understand has not been
/// proven to match any pin.
String? spkiPinFromDer(Uint8List der) {
  final spki = _extractSpki(der);
  if (spki == null) return null;
  return kPinPrefix + base64.encode(sha256.convert(spki).bytes);
}

/// Returns the exact DER bytes of the certificate's `SubjectPublicKeyInfo`.
///
/// Every parse step is guarded and any malformed input yields `null` rather
/// than a partially-trusted result; `asn1lib` throws a range of exception
/// types on damaged input, so the whole walk is wrapped.
Uint8List? _extractSpki(Uint8List der) {
  try {
    // Copy first. `asn1lib` decodes into views over the *backing buffer* of
    // the input, so a slice handed to us would let a declared length read
    // beyond the certificate into unrelated memory. An exact-sized copy makes
    // any such over-read a RangeError, caught below.
    final bytes = Uint8List.fromList(der);

    final certificate = ASN1Parser(bytes).nextObject();
    if (certificate is! ASN1Sequence) return null;
    if (certificate.elements.isEmpty) return null;

    // `asn1lib` trusts the length header without checking it against the
    // bytes actually supplied, so a certificate claiming to be longer than it
    // is parses "successfully". Reject rather than hash a truncated structure.
    if (certificate.totalEncodedByteLength > bytes.length) return null;

    final tbsCertificate = certificate.elements.first;
    if (tbsCertificate is! ASN1Sequence) return null;

    final fields = tbsCertificate.elements;
    if (fields.isEmpty) return null;

    final hasVersionField = fields.first.tag == _kVersionTag;
    final spkiIndex = hasVersionField ? _kSpkiIndexV1 + 1 : _kSpkiIndexV1;
    if (fields.length <= spkiIndex) return null;

    final spki = fields[spkiIndex];
    if (spki is! ASN1Sequence) return null;

    // `encodedBytes` may run past this element into its siblings, so trim to
    // the element's own tag-length-value span before hashing.
    final length = spki.totalEncodedByteLength;
    final encoded = spki.encodedBytes;
    if (length <= 0 || length > encoded.length) return null;

    return Uint8List.sublistView(encoded, 0, length);
  } catch (_) {
    return null;
  }
}
