import 'dart:io';

import '../config/certificate_pinning_config.dart';
import 'spki_fingerprint.dart';

/// Evaluates a leaf certificate against the configured SPKI pins.
///
/// Wired into Dio through `IOHttpClientAdapter.validateCertificate`, which
/// runs on every connection and sees the leaf certificate whether or not the
/// chain validated. (`badCertificateCallback` fires only *after* chain
/// validation has already failed, so it can never add pinning on top of an
/// otherwise-valid certificate.)
class CertificatePinner {
  CertificatePinner(this.config);

  final CertificatePinningConfig config;

  /// Returns `true` when the connection to [host] may proceed.
  ///
  /// A host with no configured pins is not pinned and passes straight through
  /// to normal TLS validation — failing closed on unknown hosts would break
  /// analytics, crash reporting, image CDNs and every other host the app talks
  /// to besides its own API.
  bool validate(X509Certificate? certificate, String host, int port) {
    final expected = pinsFor(host);
    if (expected == null) return true;

    final presented =
        certificate == null ? null : spkiPinFromDer(certificate.der);

    // A null pin means the certificate was absent or unparseable. Neither has
    // been shown to match, so neither is a pass.
    if (presented != null && expected.contains(presented)) return true;

    _report(host, presented);
    return !config.enforce;
  }

  /// Returns the pins governing [host], or `null` when [host] is not pinned.
  ///
  /// An exact entry always wins; only then does a parent domain apply, and
  /// only when [CertificatePinningConfig.includeSubdomains] is set.
  List<String>? pinsFor(String host) {
    final normalized = host.trim().toLowerCase();

    final exact = config.pins[normalized];
    if (exact != null) return exact;

    if (!config.includeSubdomains) return null;

    // Walk up one label at a time. Comparing against ".$parent" rather than a
    // bare suffix keeps "notexample.com" from inheriting "example.com".
    var index = normalized.indexOf('.');
    while (index != -1 && index + 1 < normalized.length) {
      final parent = normalized.substring(index + 1);
      final pins = config.pins[parent];
      if (pins != null) return pins;
      index = normalized.indexOf('.', index + 1);
    }

    return null;
  }

  /// Hands the mismatch to [CertificatePinningConfig.onPinFailure].
  ///
  /// The callback is consumer code running on a security-critical path, so a
  /// throw inside it must never be able to convert a rejection into a pass.
  void _report(String host, String? presented) {
    final onPinFailure = config.onPinFailure;
    if (onPinFailure == null) return;
    try {
      onPinFailure(host, presented == null ? const [] : [presented]);
    } catch (_) {
      // Telemetry is best-effort; the pinning decision stands regardless.
    }
  }
}
