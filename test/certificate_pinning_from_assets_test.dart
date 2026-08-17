import 'package:app_smart_network/app_smart_network.dart';
import 'package:app_smart_network/src/security/certificate_pinner.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures/fixture_pins.dart';

/// Matches an [ArgumentError] whose message names [path].
///
/// Every rejection has to identify *which* asset was at fault: a consumer
/// wiring up five certificates needs to know which one is wrong, and a bare
/// "invalid certificate" would send them hunting.
Matcher throwsArgumentErrorNaming(String path) => throwsA(
      isA<ArgumentError>().having(
        (e) => e.toString(),
        'message',
        contains(path),
      ),
    );

void main() {
  late FixtureAssetBundle bundle;

  setUp(() {
    bundle = FixtureAssetBundle();
  });

  group('fromAssets - pin derivation', () {
    test('derives the OpenSSL-computed pin from a real CA-issued leaf',
        () async {
      // Arrange
      final paths = {
        'api.example.com': [kRealCertPath, kV1CertPath],
      };

      // Act
      final config = await CertificatePinningConfig.fromAssets(
        certificatePaths: paths,
        bundle: bundle,
      );

      // Assert
      expect(config.pins['api.example.com'], contains(kRealCertPin));
    });

    test(
        'a bare PUBLIC KEY yields the same pin as the certificate it came from',
        () async {
      // Arrange — the round-trip proof. tamweelymf1.com.pub.pem is the public
      // key extracted from tamweelymf1.com.pem, so the CERTIFICATE branch
      // (walk the ASN.1 to SubjectPublicKeyInfo) and the PUBLIC KEY branch
      // (the body already *is* a SubjectPublicKeyInfo) must agree exactly.
      final paths = {
        'api.example.com': [kRealPublicKeyPath, kV1CertPath],
      };

      // Act
      final config = await CertificatePinningConfig.fromAssets(
        certificatePaths: paths,
        bundle: bundle,
      );

      // Assert
      expect(config.pins['api.example.com'], contains(kRealCertPin));
    });

    test('parses a v1 certificate, where SPKI sits one index earlier',
        () async {
      // Arrange — v1 has no [0] EXPLICIT version tag, so subjectPublicKeyInfo
      // is at TBSCertificate index 5 rather than 6.
      final paths = {
        'api.example.com': [kV1CertPath, kEcCertPath],
      };

      // Act
      final config = await CertificatePinningConfig.fromAssets(
        certificatePaths: paths,
        bundle: bundle,
      );

      // Assert
      expect(config.pins['api.example.com'], contains(kV1CertPin));
    });

    test('parses an EC certificate as well as RSA', () async {
      // Arrange
      final paths = {
        'api.example.com': [kEcCertPath, kV1CertPath],
      };

      // Act
      final config = await CertificatePinningConfig.fromAssets(
        certificatePaths: paths,
        bundle: bundle,
      );

      // Assert
      expect(config.pins['api.example.com'], contains(kEcCertPin));
    });

    test('every PUBLIC KEY fixture agrees with its own certificate', () async {
      // Arrange — the round-trip property should hold for every key type, not
      // just the RSA leaf.
      final paths = {
        'rsa.example.com': [kV1CertPath, kV1PublicKeyPath, kEcCertPath],
        'ec.example.com': [kEcCertPath, kEcPublicKeyPath, kV1CertPath],
      };

      // Act
      final config = await CertificatePinningConfig.fromAssets(
        certificatePaths: paths,
        bundle: bundle,
      );

      // Assert — cert and extracted key collapse to one distinct pin each
      expect(config.pins['rsa.example.com'], contains(kV1CertPin));
      expect(config.pins['ec.example.com'], contains(kEcCertPin));
    });

    test('keeps pins separate per host', () async {
      // Arrange
      final paths = {
        'a.example.com': [kRealCertPath, kV1CertPath],
        'b.example.com': [kEcCertPath, kV1CertPath],
      };

      // Act
      final config = await CertificatePinningConfig.fromAssets(
        certificatePaths: paths,
        bundle: bundle,
      );

      // Assert
      expect(config.pins['a.example.com'], contains(kRealCertPin));
      expect(config.pins['a.example.com'], isNot(contains(kEcCertPin)));
      expect(config.pins['b.example.com'], contains(kEcCertPin));
    });
  });

  group('fromAssets - rejections', () {
    test('throws naming the path when the asset is missing', () async {
      // Arrange
      final paths = {
        'api.example.com': [kMissingPath, kV1CertPath],
      };

      // Act & Assert
      await expectLater(
        CertificatePinningConfig.fromAssets(
          certificatePaths: paths,
          bundle: bundle,
        ),
        throwsArgumentErrorNaming(kMissingPath),
      );
    });

    test('throws naming the path when the file is not PEM', () async {
      // Arrange
      final paths = {
        'api.example.com': [kNotPemPath, kV1CertPath],
      };

      // Act & Assert
      await expectLater(
        CertificatePinningConfig.fromAssets(
          certificatePaths: paths,
          bundle: bundle,
        ),
        throwsArgumentErrorNaming(kNotPemPath),
      );
    });

    test(
        'throws naming the path when the PEM label is neither CERTIFICATE nor PUBLIC KEY',
        () async {
      // Arrange
      final paths = {
        'api.example.com': [kWrongLabelPath, kV1CertPath],
      };

      // Act & Assert
      await expectLater(
        CertificatePinningConfig.fromAssets(
          certificatePaths: paths,
          bundle: bundle,
        ),
        throwsArgumentErrorNaming(kWrongLabelPath),
      );
    });

    test('rejects a file holding more than one PEM block', () async {
      // Arrange — a chain file. Pinning whichever certificate happens to be
      // first would be a silent, wrong guess, so the whole file is refused.
      final paths = {
        'api.example.com': [kChainPath, kV1CertPath],
      };

      // Act & Assert
      await expectLater(
        CertificatePinningConfig.fromAssets(
          certificatePaths: paths,
          bundle: bundle,
        ),
        throwsArgumentErrorNaming(kChainPath),
      );
    });

    test('throws naming the path when the certificate cannot be parsed',
        () async {
      // Arrange — decodes as base64, but is not an X.509 structure, so
      // spkiPinFromDer returns null.
      final paths = {
        'api.example.com': [kUnparseablePath, kV1CertPath],
      };

      // Act & Assert
      await expectLater(
        CertificatePinningConfig.fromAssets(
          certificatePaths: paths,
          bundle: bundle,
        ),
        throwsArgumentErrorNaming(kUnparseablePath),
      );
    });

    test('throws naming the path when the PEM body is not valid base64',
        () async {
      // Arrange
      final paths = {
        'api.example.com': [kBadBase64Path, kV1CertPath],
      };

      // Act & Assert
      await expectLater(
        CertificatePinningConfig.fromAssets(
          certificatePaths: paths,
          bundle: bundle,
        ),
        throwsArgumentErrorNaming(kBadBase64Path),
      );
    });
  });

  group('fromAssets - delegates to the unnamed constructor', () {
    test('a single certificate for a host is rejected', () async {
      // Arrange — one pin means a lost or rotated key bricks every installed
      // app. The existing kMinimumPinsPerHost check must still apply.
      final paths = {
        'api.example.com': [kRealCertPath],
      };

      // Act & Assert
      await expectLater(
        CertificatePinningConfig.fromAssets(
          certificatePaths: paths,
          bundle: bundle,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('the same certificate listed twice is rejected as one distinct pin',
        () async {
      // Arrange — two entries, but they collapse to a single pin, which is no
      // safer than listing it once.
      final paths = {
        'api.example.com': [kRealCertPath, kRealCertPath],
      };

      // Act & Assert
      await expectLater(
        CertificatePinningConfig.fromAssets(
          certificatePaths: paths,
          bundle: bundle,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('a certificate and its own extracted public key are one distinct pin',
        () async {
      // Arrange — the round-trip property has a sharp edge: pairing a cert
      // with its own public key looks like two backups but pins one key.
      final paths = {
        'api.example.com': [kRealCertPath, kRealPublicKeyPath],
      };

      // Act & Assert
      await expectLater(
        CertificatePinningConfig.fromAssets(
          certificatePaths: paths,
          bundle: bundle,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('an empty map is rejected', () async {
      // Act & Assert
      await expectLater(
        CertificatePinningConfig.fromAssets(
          certificatePaths: const {},
          bundle: bundle,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('a blank host name is rejected', () async {
      // Arrange
      final paths = {
        '  ': [kRealCertPath, kV1CertPath],
      };

      // Act & Assert
      await expectLater(
        CertificatePinningConfig.fromAssets(
          certificatePaths: paths,
          bundle: bundle,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('host names are lower-cased, as with the unnamed constructor',
        () async {
      // Arrange
      final paths = {
        'API.Example.COM': [kRealCertPath, kV1CertPath],
      };

      // Act
      final config = await CertificatePinningConfig.fromAssets(
        certificatePaths: paths,
        bundle: bundle,
      );

      // Assert
      expect(config.pins.keys, contains('api.example.com'));
    });
  });

  group('fromAssets - option passthrough', () {
    test('carries enforce, includeSubdomains and onPinFailure through',
        () async {
      // Arrange
      var reportedHost = '';
      void onFailure(String host, List<String> presented) {
        reportedHost = host;
      }

      // Act
      final config = await CertificatePinningConfig.fromAssets(
        certificatePaths: {
          'api.example.com': [kRealCertPath, kV1CertPath],
        },
        enforce: false,
        includeSubdomains: true,
        onPinFailure: onFailure,
        bundle: bundle,
      );

      // Assert
      expect(config.enforce, isFalse);
      expect(config.includeSubdomains, isTrue);
      expect(config.onPinFailure, isNotNull);
      config.onPinFailure!('seen.example.com', const []);
      expect(reportedHost, 'seen.example.com');
    });

    test('defaults match the unnamed constructor', () async {
      // Act
      final config = await CertificatePinningConfig.fromAssets(
        certificatePaths: {
          'api.example.com': [kRealCertPath, kV1CertPath],
        },
        bundle: bundle,
      );

      // Assert
      expect(config.enforce, isTrue);
      expect(config.includeSubdomains, isFalse);
      expect(config.onPinFailure, isNull);
    });

    test('produces a config a CertificatePinner accepts', () async {
      // Arrange — the end-to-end point of fromAssets: what it returns has to
      // drive the pinner exactly like a hand-written config does.
      final config = await CertificatePinningConfig.fromAssets(
        certificatePaths: {
          'api.example.com': [kRealCertPath, kV1CertPath],
        },
        bundle: bundle,
      );

      // Act
      final pinner = CertificatePinner(config);

      // Assert
      expect(pinner.pinsFor('api.example.com'), contains(kRealCertPin));
      expect(pinner.pinsFor('other.example.com'), isNull);
    });
  });
}
