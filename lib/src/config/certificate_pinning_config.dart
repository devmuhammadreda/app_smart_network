import 'dart:collection';
import 'dart:convert';

import 'package:flutter/services.dart';

import '../security/pem_key_loader.dart';
import '../security/spki_fingerprint.dart';

/// Reports a pin mismatch for [host].
///
/// [presentedPins] holds the SPKI pins actually offered by the server, for
/// telemetry. It is empty when the certificate could not be parsed at all.
/// **Never surface these values to the user** — they belong in a security
/// event, not an error message.
typedef OnPinFailureCallback = void Function(
  String host,
  List<String> presentedPins,
);

/// Minimum pins per host. One pin means a lost or rotated key bricks every
/// installed app with no recovery path.
const int kMinimumPinsPerHost = 2;

/// SSL/TLS public-key pinning, keyed by host.
///
/// Pins are the base64 SHA-256 of a certificate's `SubjectPublicKeyInfo`, in
/// the conventional `sha256/<base64>` form shared with HPKP and OkHttp's
/// `CertificatePinner`. Generate one with:
///
/// ```bash
/// openssl s_client -connect api.example.com:443 -servername api.example.com \
///   < /dev/null 2>/dev/null \
///   | openssl x509 -pubkey -noout \
///   | openssl pkey -pubin -outform der \
///   | openssl dgst -sha256 -binary \
///   | openssl enc -base64
/// ```
///
/// ```dart
/// ApiService.initialize(NetworkConfig(
///   baseUrl: 'https://api.example.com',
///   certificatePinning: CertificatePinningConfig(
///     pins: {
///       'api.example.com': [
///         'sha256/<current key>',
///         'sha256/<backup key, held offline>',
///       ],
///     },
///   ),
/// ));
/// ```
///
/// Because the SPKI — not the whole certificate — is hashed, a pin keeps
/// working across certificate renewal as long as the key pair is reused.
///
/// Every rule here is checked at construction rather than on the first
/// request, so a mistake fails the build instead of the first API call in
/// production.
class CertificatePinningConfig {
  /// Host to accepted SPKI pins, lower-cased and unmodifiable.
  final Map<String, List<String>> pins;

  /// When `false`, mismatches are reported to [onPinFailure] but the
  /// connection proceeds.
  ///
  /// Intended for a staged rollout: ship with `false` to measure how often
  /// real users would have been disconnected, then flip it on. **Never ship
  /// `false` as the final state** — it collects pin failures without
  /// preventing any of them.
  final bool enforce;

  /// Whether a host's pins also cover its subdomains.
  ///
  /// With `example.com` pinned, this extends the pins to `api.example.com`
  /// but never to `notexample.com`. An exact host entry always wins over an
  /// inherited one.
  final bool includeSubdomains;

  /// Invoked on every pin mismatch, whether or not [enforce] blocks it.
  final OnPinFailureCallback? onPinFailure;

  /// Creates a pinning configuration, validating every pin.
  ///
  /// Throws [ArgumentError] when [pins] is empty, when any host carries fewer
  /// than [kMinimumPinsPerHost] distinct pins, or when any pin is not a
  /// well-formed `sha256/<base64 of 32 bytes>` string.
  CertificatePinningConfig({
    required Map<String, List<String>> pins,
    this.enforce = true,
    this.includeSubdomains = false,
    this.onPinFailure,
  }) : pins = _validate(pins);

  /// Builds a configuration from certificates bundled as Flutter assets,
  /// deriving each pin instead of taking a hand-pasted hash.
  ///
  /// [certificatePaths] maps a host to the asset paths pinning it. Each asset
  /// is a single PEM block, either of:
  ///
  /// * `-----BEGIN CERTIFICATE-----` — an X.509 certificate, whose
  ///   `SubjectPublicKeyInfo` is located by walking the ASN.1.
  /// * `-----BEGIN PUBLIC KEY-----` — a bare `SubjectPublicKeyInfo`, hashed
  ///   directly.
  ///
  /// The second form is what lets the mandatory backup pin come from a keypair
  /// that has no certificate yet, so pinning can ship without waiting on a CA:
  ///
  /// ```bash
  /// openssl genrsa -out backup.key 2048           # keep offline
  /// openssl rsa -in backup.key -pubout -out backup.pub.pem
  /// ```
  ///
  /// ```dart
  /// final pinning = await CertificatePinningConfig.fromAssets(
  ///   certificatePaths: {
  ///     'api.example.com': [
  ///       'assets/certs/api.example.com.pem',
  ///       'assets/certs/backup.pub.pem',
  ///     ],
  ///   },
  /// );
  /// ApiService.initialize(NetworkConfig(
  ///   baseUrl: 'https://api.example.com',
  ///   certificatePinning: pinning,
  /// ));
  /// ```
  ///
  /// Every asset is read and parsed here, so a bad path or an unreadable
  /// certificate fails during `initialize()` rather than on the first request
  /// in production.
  ///
  /// Throws [ArgumentError] naming the offending path when an asset is missing
  /// or unreadable, is not PEM, carries a label other than the two above,
  /// holds more than one PEM block, or cannot be parsed as a certificate. The
  /// derived pins then go through the same validation as the unnamed
  /// constructor, so the two-distinct-pins rule still applies — note that a
  /// certificate and its own extracted public key collapse to a single pin.
  ///
  /// [bundle] defaults to [rootBundle]; inject one in tests.
  static Future<CertificatePinningConfig> fromAssets({
    required Map<String, List<String>> certificatePaths,
    bool enforce = true,
    bool includeSubdomains = false,
    OnPinFailureCallback? onPinFailure,
    AssetBundle? bundle,
  }) async {
    final source = bundle ?? rootBundle;
    final derived = <String, List<String>>{};

    for (final entry in certificatePaths.entries) {
      final pins = <String>[];
      for (final path in entry.value) {
        pins.add(await spkiPinFromPemAsset(source, path));
      }
      derived[entry.key] = pins;
    }

    // Delegate so every rule the unnamed constructor enforces still holds;
    // this factory only changes where the pins come from.
    return CertificatePinningConfig(
      pins: derived,
      enforce: enforce,
      includeSubdomains: includeSubdomains,
      onPinFailure: onPinFailure,
    );
  }

  static Map<String, List<String>> _validate(Map<String, List<String>> pins) {
    if (pins.isEmpty) {
      throw ArgumentError.value(
        pins,
        'pins',
        'Certificate pinning was configured with no pins. Remove '
            'certificatePinning entirely, or add at least one host — an empty '
            'map produces an app that looks pinned but is not.',
      );
    }

    final validated = <String, List<String>>{};

    for (final entry in pins.entries) {
      final host = entry.key.trim().toLowerCase();
      if (host.isEmpty) {
        throw ArgumentError.value(
          entry.key,
          'pins',
          'Certificate pinning host names cannot be blank.',
        );
      }

      final hostPins = List<String>.unmodifiable(entry.value);
      for (final pin in hostPins) {
        _validatePin(pin, host);
      }

      if (hostPins.toSet().length < kMinimumPinsPerHost) {
        throw ArgumentError.value(
          entry.value,
          'pins',
          'Host "$host" needs at least $kMinimumPinsPerHost distinct pins, '
              'got ${hostPins.toSet().length}. The second must be a backup '
              'key held offline: with a single pin, losing or rotating that '
              'key bricks every installed app with no recovery path.',
        );
      }

      validated[host] = hostPins;
    }

    return UnmodifiableMapView(validated);
  }

  static void _validatePin(String pin, String host) {
    if (!pin.startsWith(kPinPrefix)) {
      throw ArgumentError.value(
        pin,
        'pins',
        'Pin for host "$host" must start with "$kPinPrefix".',
      );
    }

    final encoded = pin.substring(kPinPrefix.length);
    final List<int> digest;
    try {
      digest = base64.decode(encoded);
    } on FormatException {
      throw ArgumentError.value(
        pin,
        'pins',
        'Pin for host "$host" is not valid base64 after "$kPinPrefix".',
      );
    }

    if (digest.length != kSha256DigestLength) {
      throw ArgumentError.value(
        pin,
        'pins',
        'Pin for host "$host" decodes to ${digest.length} bytes; a SHA-256 '
            'pin is exactly $kSha256DigestLength.',
      );
    }
  }
}
