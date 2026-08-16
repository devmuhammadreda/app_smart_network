import 'package:app_smart_network/app_smart_network.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures/test_certificates.dart';

void main() {
  group('CertificatePinningConfig construction', () {
    test('accepts a host with a primary and a backup pin', () {
      final config = CertificatePinningConfig(
        pins: {
          'api.example.com': [kPrimaryPin, kBackupPin],
        },
      );

      expect(config.pins['api.example.com'], [kPrimaryPin, kBackupPin]);
      expect(config.enforce, isTrue);
      expect(config.includeSubdomains, isFalse);
    });

    test('lower-cases host keys so matching is case-insensitive', () {
      final config = CertificatePinningConfig(
        pins: {
          'API.Example.COM': [kPrimaryPin, kBackupPin],
        },
      );

      expect(config.pins.keys, ['api.example.com']);
    });

    test('exposes pins as an unmodifiable view', () {
      final config = CertificatePinningConfig(
        pins: {
          'api.example.com': [kPrimaryPin, kBackupPin],
        },
      );

      expect(() => config.pins['other.com'] = [], throwsUnsupportedError);
      expect(
        () => config.pins['api.example.com']!.add(kUnrelatedPin),
        throwsUnsupportedError,
      );
    });

    test('does not alias the caller\'s map', () {
      final source = {
        'api.example.com': [kPrimaryPin, kBackupPin],
      };
      final config = CertificatePinningConfig(pins: source);

      source['evil.com'] = [kUnrelatedPin, kPrimaryPin];

      expect(config.pins.containsKey('evil.com'), isFalse);
    });
  });

  group('CertificatePinningConfig rejects unsafe configuration', () {
    test('throws when a host has only one pin', () {
      expect(
        () => CertificatePinningConfig(
          pins: {
            'api.example.com': [kPrimaryPin],
          },
        ),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message.toString(),
            'message',
            contains('backup'),
          ),
        ),
      );
    });

    test('throws when a host has two pins that are identical', () {
      expect(
        () => CertificatePinningConfig(
          pins: {
            'api.example.com': [kPrimaryPin, kPrimaryPin],
          },
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('throws when the pins map is empty', () {
      expect(
        () => CertificatePinningConfig(pins: {}),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('throws when a pin is missing the sha256/ prefix', () {
      expect(
        () => CertificatePinningConfig(
          pins: {
            'api.example.com': [
              'U1lYtAEMYq6Unbc802/QoAWjlMzc9sv4z+5DbEInlEI=',
              kBackupPin,
            ],
          },
        ),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message.toString(),
            'message',
            contains('sha256/'),
          ),
        ),
      );
    });

    test('throws when a pin is not valid base64', () {
      expect(
        () => CertificatePinningConfig(
          pins: {
            'api.example.com': ['sha256/not-base64!!!', kBackupPin],
          },
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('throws when a pin decodes to the wrong digest length', () {
      expect(
        () => CertificatePinningConfig(
          pins: {
            'api.example.com': ['sha256/YWJj', kBackupPin],
          },
        ),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message.toString(),
            'message',
            contains('32'),
          ),
        ),
      );
    });

    test('throws when a host is blank', () {
      expect(
        () => CertificatePinningConfig(
          pins: {
            '  ': [kPrimaryPin, kBackupPin],
          },
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
