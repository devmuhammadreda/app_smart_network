import 'dart:typed_data';

import 'package:app_smart_network/src/security/spki_fingerprint.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures/test_certificates.dart';

void main() {
  group('spkiPinFromDer', () {
    test('produces the OpenSSL-computed pin for a fixture certificate', () {
      expect(spkiPinFromDer(kPrimaryCertDer), kPrimaryPin);
    });

    test('produces a different pin for a different key pair', () {
      expect(spkiPinFromDer(kBackupCertDer), kBackupPin);
      expect(spkiPinFromDer(kBackupCertDer), isNot(kPrimaryPin));
    });

    test('is stable across calls for the same certificate', () {
      expect(spkiPinFromDer(kPrimaryCertDer), spkiPinFromDer(kPrimaryCertDer));
    });

    test('hashes the public key info, not the whole certificate', () {
      // sha256 of the full DER would be a different value entirely; guards
      // against a refactor silently switching to the easier whole-cert digest.
      final wholeCertPin = spkiPinFromDer(
        Uint8List.fromList(kPrimaryCertDer),
      );
      expect(wholeCertPin, kPrimaryPin);
      expect(kPrimaryPin.length, kPinPrefix.length + 44);
    });

    test('returns null for empty input rather than a usable pin', () {
      expect(spkiPinFromDer(Uint8List(0)), isNull);
    });

    test('returns null for random bytes that are not a certificate', () {
      expect(spkiPinFromDer(Uint8List.fromList([1, 2, 3, 4, 5])), isNull);
    });

    test('returns null for a certificate truncated mid-structure', () {
      final truncated = Uint8List.sublistView(
        kPrimaryCertDer,
        0,
        kPrimaryCertDer.length ~/ 2,
      );
      expect(spkiPinFromDer(truncated), isNull);
    });

    test('returns null for a well-formed but non-certificate ASN.1 value', () {
      // A bare INTEGER: parses cleanly, but is not a Certificate SEQUENCE.
      expect(spkiPinFromDer(Uint8List.fromList([0x02, 0x01, 0x2A])), isNull);
    });
  });
}
