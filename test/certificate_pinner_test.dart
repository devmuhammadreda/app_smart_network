import 'dart:io';
import 'dart:typed_data';

import 'package:app_smart_network/app_smart_network.dart';
import 'package:app_smart_network/src/security/certificate_pinner.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures/test_certificates.dart';

/// Wraps a real DER certificate in the [X509Certificate] interface.
///
/// Only [der] is exercised by the pinner; the certificate bytes themselves are
/// genuine OpenSSL output, so the code under test sees real input.
class _Cert implements X509Certificate {
  _Cert(this.der);

  @override
  final Uint8List der;

  @override
  DateTime get endValidity => DateTime(2036);
  @override
  DateTime get startValidity => DateTime(2026);
  @override
  String get issuer => 'CN=api.example.com';
  @override
  String get subject => 'CN=api.example.com';
  @override
  String get pem => throw UnimplementedError();
  @override
  Uint8List get sha1 => throw UnimplementedError();
}

const _port = 443;

CertificatePinner _pinnerFor(
  Map<String, List<String>> pins, {
  bool enforce = true,
  bool includeSubdomains = false,
  OnPinFailureCallback? onPinFailure,
}) {
  return CertificatePinner(
    CertificatePinningConfig(
      pins: pins,
      enforce: enforce,
      includeSubdomains: includeSubdomains,
      onPinFailure: onPinFailure,
    ),
  );
}

void main() {
  final primary = _Cert(kPrimaryCertDer);
  final backup = _Cert(kBackupCertDer);

  group('pinned hosts', () {
    test('allows a certificate whose SPKI matches the primary pin', () {
      final pinner = _pinnerFor({
        'api.example.com': [kPrimaryPin, kBackupPin],
      });

      expect(pinner.validate(primary, 'api.example.com', _port), isTrue);
    });

    test('allows a certificate matching the backup pin only', () {
      final pinner = _pinnerFor({
        'api.example.com': [kPrimaryPin, kUnrelatedPin],
      });

      // `backup` matches neither the first nor the second entry above, so
      // build a config where the backup slot is the one that matches.
      final withBackup = _pinnerFor({
        'api.example.com': [kUnrelatedPin, kBackupPin],
      });

      expect(pinner.validate(backup, 'api.example.com', _port), isFalse);
      expect(withBackup.validate(backup, 'api.example.com', _port), isTrue);
    });

    test('rejects a certificate matching none of the pins', () {
      final pinner = _pinnerFor({
        'api.example.com': [kUnrelatedPin, kBackupPin],
      });

      expect(pinner.validate(primary, 'api.example.com', _port), isFalse);
    });

    test('matches the host case-insensitively', () {
      final pinner = _pinnerFor({
        'API.example.com': [kPrimaryPin, kBackupPin],
      });

      expect(pinner.validate(primary, 'Api.Example.Com', _port), isTrue);
    });

    test('rejects a malformed certificate instead of passing it', () {
      final pinner = _pinnerFor({
        'api.example.com': [kPrimaryPin, kBackupPin],
      });
      final garbage = _Cert(Uint8List.fromList([0xDE, 0xAD, 0xBE, 0xEF]));

      expect(pinner.validate(garbage, 'api.example.com', _port), isFalse);
    });

    test('rejects a null certificate on a pinned host', () {
      final pinner = _pinnerFor({
        'api.example.com': [kPrimaryPin, kBackupPin],
      });

      expect(pinner.validate(null, 'api.example.com', _port), isFalse);
    });
  });

  group('unpinned hosts', () {
    test('passes through untouched when the host has no pins', () {
      final pinner = _pinnerFor({
        'api.example.com': [kPrimaryPin, kBackupPin],
      });

      expect(
          pinner.validate(primary, 'firebase.googleapis.com', _port), isTrue);
      expect(pinner.validate(null, 'cdn.images.example.net', _port), isTrue);
    });

    test('does not report a failure for an unpinned host', () {
      final failures = <String>[];
      final pinner = _pinnerFor(
        {
          'api.example.com': [kPrimaryPin, kBackupPin],
        },
        onPinFailure: (host, _) => failures.add(host),
      );

      pinner.validate(primary, 'analytics.example.net', _port);

      expect(failures, isEmpty);
    });

    test('does not treat a suffix collision as a pinned host', () {
      final pinner = _pinnerFor(
        {
          'example.com': [kPrimaryPin, kBackupPin],
        },
        includeSubdomains: true,
      );

      // "notexample.com" ends with "example.com" as a string but is a
      // different registrable domain.
      expect(pinner.validate(backup, 'notexample.com', _port), isTrue);
    });
  });

  group('includeSubdomains', () {
    test('is off by default, so a subdomain is unpinned', () {
      final pinner = _pinnerFor({
        'example.com': [kPrimaryPin, kBackupPin],
      });

      expect(pinner.validate(backup, 'api.example.com', _port), isTrue);
    });

    test('applies a parent domain\'s pins to a subdomain when on', () {
      final pinner = _pinnerFor(
        {
          'example.com': [kPrimaryPin, kUnrelatedPin],
        },
        includeSubdomains: true,
      );

      expect(pinner.validate(primary, 'api.example.com', _port), isTrue);
      expect(pinner.validate(backup, 'api.example.com', _port), isFalse);
    });

    test('applies to a deeply nested subdomain', () {
      final pinner = _pinnerFor(
        {
          'example.com': [kPrimaryPin, kUnrelatedPin],
        },
        includeSubdomains: true,
      );

      expect(pinner.validate(backup, 'a.b.c.example.com', _port), isFalse);
    });

    test('prefers an exact host entry over an inherited one', () {
      final pinner = _pinnerFor(
        {
          'example.com': [kUnrelatedPin, kPrimaryPin],
          'api.example.com': [kBackupPin, kUnrelatedPin],
        },
        includeSubdomains: true,
      );

      // api.example.com's own pins accept `backup` and reject `primary`, even
      // though the parent entry says the opposite.
      expect(pinner.validate(backup, 'api.example.com', _port), isTrue);
      expect(pinner.validate(primary, 'api.example.com', _port), isFalse);
    });
  });

  group('enforce: false', () {
    test('allows a mismatching certificate through', () {
      final pinner = _pinnerFor(
        {
          'api.example.com': [kUnrelatedPin, kBackupPin],
        },
        enforce: false,
      );

      expect(pinner.validate(primary, 'api.example.com', _port), isTrue);
    });

    test('still reports the mismatch', () {
      String? reportedHost;
      List<String>? reportedPins;
      final pinner = _pinnerFor(
        {
          'api.example.com': [kUnrelatedPin, kBackupPin],
        },
        enforce: false,
        onPinFailure: (host, pins) {
          reportedHost = host;
          reportedPins = pins;
        },
      );

      pinner.validate(primary, 'api.example.com', _port);

      expect(reportedHost, 'api.example.com');
      expect(reportedPins, [kPrimaryPin]);
    });
  });

  group('onPinFailure', () {
    test('reports the presented pin on an enforced mismatch', () {
      List<String>? reportedPins;
      final pinner = _pinnerFor(
        {
          'api.example.com': [kUnrelatedPin, kBackupPin],
        },
        onPinFailure: (_, pins) => reportedPins = pins,
      );

      expect(pinner.validate(primary, 'api.example.com', _port), isFalse);
      expect(reportedPins, [kPrimaryPin]);
    });

    test('reports no pins when the certificate could not be parsed', () {
      List<String>? reportedPins;
      final pinner = _pinnerFor(
        {
          'api.example.com': [kPrimaryPin, kBackupPin],
        },
        onPinFailure: (_, pins) => reportedPins = pins,
      );

      pinner.validate(_Cert(Uint8List(0)), 'api.example.com', _port);

      expect(reportedPins, isEmpty);
    });

    test('is not called when the pin matches', () {
      var called = false;
      final pinner = _pinnerFor(
        {
          'api.example.com': [kPrimaryPin, kBackupPin],
        },
        onPinFailure: (_, __) => called = true,
      );

      pinner.validate(primary, 'api.example.com', _port);

      expect(called, isFalse);
    });

    test('a throwing callback does not turn a rejection into a pass', () {
      final pinner = _pinnerFor(
        {
          'api.example.com': [kUnrelatedPin, kBackupPin],
        },
        onPinFailure: (_, __) => throw StateError('telemetry is down'),
      );

      expect(pinner.validate(primary, 'api.example.com', _port), isFalse);
    });
  });
}
