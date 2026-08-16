import 'dart:collection';
import 'dart:convert';

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
