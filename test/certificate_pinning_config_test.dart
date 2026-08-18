import 'package:app_smart_network/app_smart_network.dart';
import 'package:flutter_test/flutter_test.dart';

/// SHA-256 fingerprints in the colon-separated form `openssl` prints.
const kPrimaryFingerprint =
    'AA:BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77:88:99:'
    'AA:BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77:88:99';
const kBackupFingerprint =
    '11:22:33:44:55:66:77:88:99:AA:BB:CC:DD:EE:FF:00:'
    '11:22:33:44:55:66:77:88:99:AA:BB:CC:DD:EE:FF:00';

/// The same two values as the bare hex the native check compares against.
const kPrimaryBare =
    'AABBCCDDEEFF00112233445566778899AABBCCDDEEFF00112233445566778899';
const kBackupBare =
    '112233445566778899AABBCCDDEEFF00112233445566778899AABBCCDDEEFF00';

void main() {
  group('CertificatePinningConfig construction', () {
    test('accepts a primary and a successor fingerprint', () {
      // Arrange / Act
      final config = CertificatePinningConfig(
        allowedSHAFingerprints: [kPrimaryFingerprint, kBackupFingerprint],
      );

      // Assert
      expect(config.allowedSHAFingerprints, [kPrimaryBare, kBackupBare]);
      expect(config.timeout, 60);
    });

    test('strips colons so openssl output can be pasted verbatim', () {
      final config = CertificatePinningConfig(
        allowedSHAFingerprints: [kPrimaryFingerprint, kBackupFingerprint],
      );

      expect(config.allowedSHAFingerprints.first, isNot(contains(':')));
    });

    test('upper-cases lower-case hex so case never causes a silent miss', () {
      final config = CertificatePinningConfig(
        allowedSHAFingerprints: [
          kPrimaryBare.toLowerCase(),
          kBackupBare.toLowerCase(),
        ],
      );

      expect(config.allowedSHAFingerprints, [kPrimaryBare, kBackupBare]);
    });

    test('strips surrounding whitespace and embedded line breaks', () {
      final config = CertificatePinningConfig(
        allowedSHAFingerprints: ['  $kPrimaryBare\n', ' $kBackupBare '],
      );

      expect(config.allowedSHAFingerprints, [kPrimaryBare, kBackupBare]);
    });

    test('exposes fingerprints as an unmodifiable view', () {
      final config = CertificatePinningConfig(
        allowedSHAFingerprints: [kPrimaryBare, kBackupBare],
      );

      expect(
        () => config.allowedSHAFingerprints.add(kPrimaryBare),
        throwsUnsupportedError,
      );
    });

    test('does not alias the caller\'s list', () {
      // A later mutation of the caller's list must not silently change what
      // the app pins.
      final source = [kPrimaryBare, kBackupBare];
      final config = CertificatePinningConfig(allowedSHAFingerprints: source);

      source.add('DEADBEEF');

      expect(config.allowedSHAFingerprints, hasLength(2));
    });

    test('accepts a custom timeout', () {
      final config = CertificatePinningConfig(
        allowedSHAFingerprints: [kPrimaryBare, kBackupBare],
        timeout: 15,
      );

      expect(config.timeout, 15);
    });

    test('accepts timeout 0 as "platform default"', () {
      final config = CertificatePinningConfig(
        allowedSHAFingerprints: [kPrimaryBare, kBackupBare],
        timeout: 0,
      );

      expect(config.timeout, 0);
    });
  });

  group('CertificatePinningConfig validation', () {
    test('rejects an empty fingerprint list', () {
      expect(
        () => CertificatePinningConfig(allowedSHAFingerprints: const []),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('no fingerprints'),
          ),
        ),
      );
    });

    test('rejects a single fingerprint, naming the renewal risk', () {
      expect(
        () => CertificatePinningConfig(
          allowedSHAFingerprints: const [kPrimaryBare],
        ),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            allOf(contains('at least 2'), contains('renews')),
          ),
        ),
      );
    });

    test('rejects a duplicate second fingerprint', () {
      // Two entries that normalise to the same value are one pin, and give
      // none of the protection a real successor certificate would.
      expect(
        () => CertificatePinningConfig(
          allowedSHAFingerprints: [kPrimaryFingerprint, kPrimaryBare],
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('rejects a fingerprint that is too short', () {
      expect(
        () => CertificatePinningConfig(
          allowedSHAFingerprints: ['AA:BB:CC', kBackupBare],
        ),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('64 hex'),
          ),
        ),
      );
    });

    test('rejects a fingerprint that is too long', () {
      expect(
        () => CertificatePinningConfig(
          allowedSHAFingerprints: ['${kPrimaryBare}AA', kBackupBare],
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('rejects non-hex characters', () {
      expect(
        () => CertificatePinningConfig(
          allowedSHAFingerprints: [
            'ZZ${kPrimaryBare.substring(2)}',
            kBackupBare,
          ],
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('rejects a SHA-1 fingerprint', () {
      // SHA-1 is 40 hex characters; the interceptor always asks for SHA-256,
      // so a SHA-1 value would never match anything at runtime.
      expect(
        () => CertificatePinningConfig(
          allowedSHAFingerprints: [
            'DA39A3EE5E6B4B0D3255BFEF95601890AFD80709',
            kBackupBare,
          ],
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('rejects a base64 SPKI pin left over from 1.x', () {
      expect(
        () => CertificatePinningConfig(
          allowedSHAFingerprints: [
            'sha256/U1lYtAEMYq6Unbc802/QoAWjlMzc9sv4z+5DbEInlEI=',
            kBackupBare,
          ],
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('rejects a negative timeout', () {
      expect(
        () => CertificatePinningConfig(
          allowedSHAFingerprints: [kPrimaryBare, kBackupBare],
          timeout: -1,
        ),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('negative'),
          ),
        ),
      );
    });
  });
}
