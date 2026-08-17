import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';

import 'spki_fingerprint.dart';

/// PEM label of an X.509 certificate.
const String kPemLabelCertificate = 'CERTIFICATE';

/// PEM label of a bare `SubjectPublicKeyInfo`.
const String kPemLabelPublicKey = 'PUBLIC KEY';

/// Matches a PEM header and captures its label.
final RegExp _beginBlock = RegExp(r'-----BEGIN ([A-Z0-9 ]+)-----');

/// Derives the `sha256/<base64>` SPKI pin for the PEM asset at [path].
///
/// Accepts exactly two kinds of input, and treats them differently because
/// they are structurally different things:
///
/// * `CERTIFICATE` — a full X.509 certificate. Its `SubjectPublicKeyInfo` has
///   to be located by walking the ASN.1, which is what [spkiPinFromDer] does.
/// * `PUBLIC KEY` — the body already *is* a `SubjectPublicKeyInfo`, so it is
///   hashed directly. Routing it through [spkiPinFromDer] would fail: there is
///   no TBSCertificate to walk.
///
/// Supporting bare public keys is what lets a backup pin be derived from a
/// keypair that has no certificate yet, so pinning can ship without waiting on
/// a CA to issue anything.
///
/// Throws [ArgumentError] naming [path] for every failure: a missing or
/// unreadable asset, a file with no PEM block, a label that is neither of the
/// two above, a file holding more than one block, a body that is not valid
/// base64, or a certificate that cannot be parsed. Consumers wiring up several
/// certificates need to know *which* one was wrong.
Future<String> spkiPinFromPemAsset(AssetBundle bundle, String path) async {
  final pem = await _loadAsset(bundle, path);
  final matches = _beginBlock.allMatches(pem).toList();

  if (matches.isEmpty) {
    throw ArgumentError.value(
      path,
      'certificatePaths',
      'Asset "$path" is not a PEM file: no "-----BEGIN ...-----" block found. '
          'Expected a $kPemLabelCertificate or $kPemLabelPublicKey block.',
    );
  }

  // A chain file would otherwise pin whichever certificate happens to come
  // first, which is a silent guess at which link the consumer meant.
  if (matches.length > 1) {
    throw ArgumentError.value(
      path,
      'certificatePaths',
      'Asset "$path" holds ${matches.length} PEM blocks. Pin one certificate '
          'per file: with a chain there is no way to tell which link was '
          'meant, and pinning the wrong one fails at runtime, not here. '
          'Split the file and list each pin explicitly.',
    );
  }

  final label = matches.first.group(1)!.trim();
  if (label != kPemLabelCertificate && label != kPemLabelPublicKey) {
    throw ArgumentError.value(
      path,
      'certificatePaths',
      'Asset "$path" is a "$label" block. Certificate pinning accepts a '
          '$kPemLabelCertificate or a $kPemLabelPublicKey block only. Never '
          'ship a private key inside an app bundle.',
    );
  }

  final der = _decodeBody(pem, matches.first.end, label, path);

  if (label == kPemLabelPublicKey) {
    // Already a SubjectPublicKeyInfo — hash it as-is.
    return kPinPrefix + base64.encode(sha256.convert(der).bytes);
  }

  final pin = spkiPinFromDer(der);
  if (pin == null) {
    throw ArgumentError.value(
      path,
      'certificatePaths',
      'Asset "$path" could not be parsed as an X.509 certificate. A '
          'certificate this package cannot read has not been shown to match '
          'anything, so it cannot be pinned.',
    );
  }
  return pin;
}

/// Reads [path] from [bundle] as text.
///
/// Any bundle failure — a missing asset, an unregistered one, an unreadable
/// file — becomes an [ArgumentError] naming [path], so the caller sees one
/// error type regardless of how the load went wrong.
Future<String> _loadAsset(AssetBundle bundle, String path) async {
  try {
    return await bundle.loadString(path);
  } catch (error) {
    throw ArgumentError.value(
      path,
      'certificatePaths',
      'Asset "$path" could not be loaded ($error). Check the path and make '
          'sure it is declared under "assets:" in pubspec.yaml.',
    );
  }
}

/// Decodes the base64 body that follows the BEGIN header ending at [bodyStart].
Uint8List _decodeBody(
  String pem,
  int bodyStart,
  String label,
  String path,
) {
  final end = pem.indexOf('-----END', bodyStart);
  if (end == -1) {
    throw ArgumentError.value(
      path,
      'certificatePaths',
      'Asset "$path" opens a "$label" block that is never closed by a '
          'matching "-----END $label-----".',
    );
  }

  // Strip the line breaks PEM wraps its payload at, plus any stray whitespace.
  final body = pem.substring(bodyStart, end).replaceAll(RegExp(r'\s'), '');
  try {
    return base64.decode(body);
  } on FormatException catch (error) {
    throw ArgumentError.value(
      path,
      'certificatePaths',
      'Asset "$path" has a "$label" block whose body is not valid base64 '
          '(${error.message}).',
    );
  }
}
