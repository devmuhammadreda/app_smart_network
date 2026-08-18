import 'dart:collection';

/// Minimum fingerprints a configuration must carry.
///
/// One fingerprint means the app stops working the moment that certificate is
/// replaced, with no recovery path short of a store release.
const int kMinimumFingerprints = 2;

/// Number of hex characters in a SHA-256 fingerprint (32 bytes).
const int kSha256HexLength = 64;

/// Matches a fingerprint once separators and whitespace have been stripped.
final RegExp _hexOnly = RegExp(r'^[0-9A-F]+$');

/// SSL/TLS certificate pinning, backed by `http_certificate_pinning`.
///
/// Pins are the **SHA-256 of the whole DER certificate** — the value printed
/// by `openssl x509 -fingerprint -sha256`. Colons and whitespace are optional
/// and case does not matter; everything is normalised to bare uppercase hex.
///
/// ```bash
/// openssl s_client -connect api.example.com:443 -servername api.example.com \
///   < /dev/null 2>/dev/null \
///   | openssl x509 -fingerprint -sha256 -noout
/// ```
///
/// ```dart
/// ApiService.initialize(NetworkConfig(
///   baseUrl: 'https://api.example.com',
///   certificatePinning: CertificatePinningConfig(
///     allowedSHAFingerprints: [
///       'AA:BB:...',  // certificate in production today
///       'CC:DD:...',  // successor certificate, already issued
///     ],
///   ),
/// ));
/// ```
///
/// ## A whole-certificate pin dies with the certificate
///
/// The digest covers the entire certificate, so **renewal breaks the pin even
/// when the key pair is reused**. Both entries must therefore be certificates
/// that already exist and whose renewal you control — a placeholder second
/// entry is not a backup. Ship the successor's fingerprint before the current
/// certificate expires, or the app stops connecting on renewal day.
///
/// ## Android and iOS only
///
/// `http_certificate_pinning` is a native plugin with no web or desktop
/// implementation. On any other platform the pinning check cannot run and the
/// request fails; this package is intended for mobile targets.
///
/// ## How the check runs
///
/// Verification happens in `onRequest` over a separate connection to the same
/// host, before the real request goes out. It costs one extra TLS handshake
/// per request and is not the same connection the request rides on.
///
/// Every rule below is checked at construction rather than on the first
/// request, so a mistake fails at startup instead of in production.
class CertificatePinningConfig {
  /// Accepted certificate fingerprints, normalised to bare uppercase hex and
  /// unmodifiable.
  final List<String> allowedSHAFingerprints;

  /// Connection timeout for the pinning check, in seconds.
  ///
  /// `0` leaves the platform default in place.
  final int timeout;

  /// Creates a pinning configuration, validating every fingerprint.
  ///
  /// Throws [ArgumentError] when [allowedSHAFingerprints] holds fewer than
  /// [kMinimumFingerprints] distinct values, when any entry is not a
  /// well-formed SHA-256 hex digest, or when [timeout] is negative.
  CertificatePinningConfig({
    required List<String> allowedSHAFingerprints,
    this.timeout = 60,
  }) : allowedSHAFingerprints = _validate(allowedSHAFingerprints, timeout);

  static List<String> _validate(List<String> fingerprints, int timeout) {
    if (timeout < 0) {
      throw ArgumentError.value(
        timeout,
        'timeout',
        'Certificate pinning timeout cannot be negative. Use 0 for the '
            'platform default.',
      );
    }

    if (fingerprints.isEmpty) {
      throw ArgumentError.value(
        fingerprints,
        'allowedSHAFingerprints',
        'Certificate pinning was configured with no fingerprints. Remove '
            'certificatePinning entirely, or add at least '
            '$kMinimumFingerprints — an empty list produces an app that looks '
            'pinned but is not.',
      );
    }

    final normalized = fingerprints.map(_normalize).toList();

    if (normalized.toSet().length < kMinimumFingerprints) {
      throw ArgumentError.value(
        fingerprints,
        'allowedSHAFingerprints',
        'Certificate pinning needs at least $kMinimumFingerprints distinct '
            'fingerprints, got ${normalized.toSet().length}. The second must '
            'be the successor certificate: a whole-certificate pin stops '
            'matching the day the server renews, and with one pin that bricks '
            'every installed app with no recovery path.',
      );
    }

    return UnmodifiableListView(normalized);
  }

  /// Strips separators and whitespace, then upper-cases.
  ///
  /// `openssl` prints colon-separated pairs while the native check compares
  /// bare hex, so accepting either form removes a silent-mismatch trap.
  static String _normalize(String fingerprint) {
    final stripped = fingerprint
        .replaceAll(RegExp(r'[\s:]'), '')
        .toUpperCase();

    if (stripped.length != kSha256HexLength || !_hexOnly.hasMatch(stripped)) {
      throw ArgumentError.value(
        fingerprint,
        'allowedSHAFingerprints',
        'Fingerprint must be a SHA-256 digest: $kSha256HexLength hex '
            'characters, optionally colon-separated. Got '
            '${stripped.length} character(s) after stripping separators. '
            'Generate one with: openssl x509 -fingerprint -sha256 -noout',
      );
    }

    return stripped;
  }
}
