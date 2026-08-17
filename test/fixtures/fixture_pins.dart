import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Golden SPKI pins for the certificate fixtures.
///
/// Every value here was produced by OpenSSL, not by this package:
///
/// ```bash
/// openssl x509 -in <file> -pubkey -noout | openssl pkey -pubin -outform der \
///   | openssl dgst -sha256 -binary | openssl enc -base64
/// ```
///
/// That is the whole point of asserting them: the tests cross-validate
/// `spkiPinFromDer` against an independent implementation rather than against
/// itself. Re-run `test/fixtures/generate_fixtures.sh` after changing any
/// generated fixture and paste the pins it prints back in here.

/// A CA-issued production leaf certificate (v3, RSA-2048).
///
/// The one fixture that came off a real TLS handshake rather than being minted
/// for the test suite.
const String kRealCertPath = 'certs/tamweelymf1.com.pem';
const String kRealCertPin =
    'sha256/TvPGqP7UyeYcr3iVfMePuNpfBCfx8z3V34Y1bUxzWe0=';

/// The same public key as [kRealCertPath], extracted to a bare
/// `SubjectPublicKeyInfo`. Must yield [kRealCertPin] exactly.
const String kRealPublicKeyPath = 'certs/tamweelymf1.com.pub.pem';

/// A v1 certificate: no `[0] EXPLICIT version` tag, so `subjectPublicKeyInfo`
/// sits at TBSCertificate index 5. Real-world certificates are all v3, so this
/// is the only fixture reaching that branch of the parser.
const String kV1CertPath = 'certs/v1_rsa.pem';
const String kV1CertPin = 'sha256/t6VPd4ZWwRvJTnDAy6OxxqzUH9pej2ctlNcFm26lGUg=';
const String kV1PublicKeyPath = 'certs/v1_rsa.pub.pem';

/// A v3 EC P-256 certificate: a different key algorithm and a far shorter key,
/// so the digest cannot accidentally depend on RSA's shape.
const String kEcCertPath = 'certs/ec_p256.pem';
const String kEcCertPin = 'sha256/oVFiQZ17nhcEGx5d61WOXO0lMnd/RcZaY3nr/woAF34=';
const String kEcPublicKeyPath = 'certs/ec_p256.pub.pem';

// ── Malformed inputs, one per rejection case ──────────────────────────────

/// No BEGIN block at all.
const String kNotPemPath = 'malformed/not_pem.txt';

/// Two certificates in one file. Rejected rather than silently pinning
/// whichever one happens to come first.
const String kChainPath = 'malformed/chain.pem';

/// A well-formed PEM block labelled `CERTIFICATE REQUEST` — a realistic thing
/// to bundle by mistake, and free of any secret.
const String kWrongLabelPath = 'malformed/wrong_label.pem';

/// `CERTIFICATE` over base64 that decodes cleanly but is not a certificate.
const String kUnparseablePath = 'malformed/unparseable.pem';

/// `CERTIFICATE` over bytes that are not valid base64.
const String kBadBase64Path = 'malformed/bad_base64.pem';

/// A path with no file behind it.
const String kMissingPath = 'certs/does_not_exist.pem';

/// Serves the fixture files from disk under an [AssetBundle], so `fromAssets`
/// can be exercised without a Flutter asset bundle or a running app.
///
/// Extends [CachingAssetBundle] to inherit `loadString`/`loadStructuredData`;
/// only [load] needs a real implementation.
class FixtureAssetBundle extends CachingAssetBundle {
  FixtureAssetBundle({this.root = 'test/fixtures'});

  final String root;

  @override
  Future<ByteData> load(String key) async {
    final file = File('$root/$key');
    if (!file.existsSync()) {
      // Mirrors how rootBundle reports an asset that is not in the manifest.
      throw FlutterError('Unable to load asset: $key');
    }
    final bytes = await file.readAsBytes();
    return ByteData.view(Uint8List.fromList(bytes).buffer);
  }
}
