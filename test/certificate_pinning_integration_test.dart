import 'dart:io';
import 'dart:typed_data';

import 'package:app_smart_network/app_smart_network.dart';
import 'package:app_smart_network/src/client/http_client.dart';
import 'package:app_smart_network/src/config/retry_policy.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures/test_certificates.dart';

/// Fails every attempt the way Dio does when `validateCertificate` rejects.
class _BadCertificateAdapter implements HttpClientAdapter {
  int attempts = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    attempts++;
    throw DioException.badCertificate(requestOptions: options, error: null);
  }

  @override
  void close({bool force = false}) {}
}

CertificatePinningConfig _pinning({
  bool enforce = true,
  bool includeSubdomains = false,
}) {
  return CertificatePinningConfig(
    pins: {
      'api.example.com': [kPrimaryPin, kBackupPin],
    },
    enforce: enforce,
    includeSubdomains: includeSubdomains,
  );
}

Future<Object?> _errorFrom(HttpClient client, String url) async {
  try {
    await client.dio.request<String>(
      url,
      options: Options(responseType: ResponseType.plain),
    );
    return null;
  } catch (e) {
    return e;
  }
}

void main() {
  tearDown(() => NetworkLocale.setLocale('en'));

  group('NetworkConfig', () {
    test('has no pinning by default', () {
      const config = NetworkConfig(baseUrl: 'https://api.example.com');

      expect(config.certificatePinning, isNull);
    });

    test('still supports const construction without pinning', () {
      // Guards the backward-compatibility promise: adding the field must not
      // force existing `const NetworkConfig(...)` call sites to change.
      const config = NetworkConfig(
        baseUrl: 'https://api.example.com',
        allowBadCertificate: true,
      );

      expect(config.baseUrl, 'https://api.example.com');
    });

    test('carries the pinning configuration when given one', () {
      final config = NetworkConfig(
        baseUrl: 'https://api.example.com',
        certificatePinning: _pinning(),
      );

      expect(config.certificatePinning, isNotNull);
      expect(config.certificatePinning!.enforce, isTrue);
    });
  });

  group('HttpClient wiring', () {
    test('rejects allowBadCertificate combined with pinning', () {
      expect(
        () => HttpClient(NetworkConfig(
          baseUrl: 'https://api.example.com',
          allowBadCertificate: true,
          certificatePinning: _pinning(),
        )),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message.toString(),
            'message',
            allOf(
              contains('allowBadCertificate'),
              contains('certificatePinning'),
            ),
          ),
        ),
      );
    });

    test('installs no certificate validator when pinning is off', () {
      final client = HttpClient(
        const NetworkConfig(baseUrl: 'https://api.example.com'),
      );
      addTearDown(client.dispose);

      final adapter = client.dio.httpClientAdapter as IOHttpClientAdapter;
      expect(adapter.validateCertificate, isNull);
    });

    test('installs a validator that enforces the pins', () {
      final client = HttpClient(NetworkConfig(
        baseUrl: 'https://api.example.com',
        certificatePinning: _pinning(),
      ));
      addTearDown(client.dispose);

      final adapter = client.dio.httpClientAdapter as IOHttpClientAdapter;
      final validate = adapter.validateCertificate;

      expect(validate, isNotNull);
      expect(validate!(_FakeCert(kPrimaryCertDer), 'api.example.com', 443),
          isTrue);
      expect(
          validate(_FakeCert(kRogueCertDer), 'api.example.com', 443), isFalse);
      expect(
          validate(_FakeCert(kRogueCertDer), 'cdn.example.net', 443), isTrue);
    });

    test('still honours allowBadCertificate on its own', () {
      final client = HttpClient(const NetworkConfig(
        baseUrl: 'https://api.example.com',
        allowBadCertificate: true,
      ));
      addTearDown(client.dispose);

      final adapter = client.dio.httpClientAdapter as IOHttpClientAdapter;
      expect(adapter.createHttpClient, isNotNull);
    });
  });

  group('retry', () {
    test('does not re-attempt a certificate failure', () async {
      final adapter = _BadCertificateAdapter();
      final client = HttpClient(NetworkConfig(
        baseUrl: 'https://api.example.com',
        certificatePinning: _pinning(),
        retry: const RetryPolicy(attempts: 3, delays: []),
      ));
      addTearDown(client.dispose);
      client.dio.httpClientAdapter = adapter;

      await _errorFrom(client, '/ping');

      expect(adapter.attempts, 1);
    });

    test('does not re-attempt even when the request opts into retry', () async {
      final adapter = _BadCertificateAdapter();
      final client = HttpClient(NetworkConfig(
        baseUrl: 'https://api.example.com',
        certificatePinning: _pinning(),
      ));
      addTearDown(client.dispose);
      client.dio.httpClientAdapter = adapter;

      try {
        await client.dio.request<String>(
          '/ping',
          options: attachRetryPolicy(
            Options(method: 'POST', responseType: ResponseType.plain),
            const RetryPolicy(attempts: 5, delays: []),
          ),
        );
      } catch (_) {
        // expected
      }

      expect(adapter.attempts, 1);
    });
  });

  group('failure surfacing', () {
    late HttpClient client;

    setUp(() {
      client = HttpClient(NetworkConfig(
        baseUrl: 'https://api.example.com',
        certificatePinning: _pinning(),
      ));
      client.dio.httpClientAdapter = _BadCertificateAdapter();
    });

    tearDown(() => client.dispose());

    test('surfaces a pinned-host failure as CertificatePinningException',
        () async {
      final error = await _errorFrom(client, '/ping');
      final mapped = ErrorHandler.handleError(error);

      expect(mapped, isA<CertificatePinningException>());
      expect((mapped as CertificatePinningException).host, 'api.example.com');
      expect(mapped.errorType, 'CertificatePinningFailed');
    });

    test('is distinguishable from a generic network error', () async {
      final error = await _errorFrom(client, '/ping');
      final mapped = ErrorHandler.handleError(error);

      expect(mapped, isA<ApiException>());
      expect(mapped, isA<CertificatePinningException>());
      expect(ErrorHandler.handleError(SocketException('down')),
          isNot(isA<CertificatePinningException>()));
    });

    test('leaves an unpinned host as a generic certificate error', () async {
      final error = await _errorFrom(client, 'https://cdn.example.net/img');
      final mapped = ErrorHandler.handleError(error) as ApiException;

      expect(mapped, isNot(isA<CertificatePinningException>()));
      expect(mapped.errorType, 'BadCertificate');
    });

    test('never leaks the presented pins into the user-facing message',
        () async {
      final error = await _errorFrom(client, '/ping');
      final mapped = ErrorHandler.handleError(error) as ApiException;

      expect(mapped.message, isNot(contains('sha256/')));
      expect(mapped.message, isNot(contains(kPrimaryPin)));
    });

    test('uses an English message by default', () async {
      final error = await _errorFrom(client, '/ping');
      final mapped = ErrorHandler.handleError(error) as ApiException;

      expect(mapped.message, 'Secure connection could not be verified.');
    });

    test('uses the Arabic message when the locale is ar', () async {
      NetworkLocale.setLocale('ar');
      final error = await _errorFrom(client, '/ping');
      final mapped = ErrorHandler.handleError(error) as ApiException;

      expect(mapped.message, 'تعذر التحقق من الاتصال الآمن.');
      expect(mapped.message, isNot(contains('Secure')));
    });
  });

  group('onPinFailure', () {
    test('fires with the host and presented pin', () {
      String? host;
      List<String>? pins;

      final client = HttpClient(NetworkConfig(
        baseUrl: 'https://api.example.com',
        certificatePinning: CertificatePinningConfig(
          pins: {
            'api.example.com': [kUnrelatedPin, kBackupPin],
          },
          onPinFailure: (h, p) {
            host = h;
            pins = p;
          },
        ),
      ));
      addTearDown(client.dispose);

      final adapter = client.dio.httpClientAdapter as IOHttpClientAdapter;
      adapter.validateCertificate!(
        _FakeCert(kPrimaryCertDer),
        'api.example.com',
        443,
      );

      expect(host, 'api.example.com');
      expect(pins, [kPrimaryPin]);
    });
  });
}

/// Wraps real OpenSSL-generated DER in the [X509Certificate] interface.
class _FakeCert implements X509Certificate {
  _FakeCert(this.der);

  @override
  final Uint8List der;

  @override
  DateTime get endValidity => DateTime(2036);
  @override
  DateTime get startValidity => DateTime(2026);
  @override
  String get issuer => 'CN=test';
  @override
  String get subject => 'CN=test';
  @override
  String get pem => throw UnimplementedError();
  @override
  Uint8List get sha1 => throw UnimplementedError();
}
