import 'dart:io';

import 'package:app_smart_network/app_smart_network.dart';
import 'package:app_smart_network/src/client/http_client.dart';
import 'package:app_smart_network/src/config/retry_policy.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:dio_smart_retry/dio_smart_retry.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_certificate_pinning/http_certificate_pinning.dart';

import 'certificate_pinning_config_test.dart'
    show kBackupBare, kBackupFingerprint, kPrimaryBare, kPrimaryFingerprint;

/// The channel `http_certificate_pinning` runs its native check over.
const _channel = MethodChannel('http_certificate_pinning');

/// Records every `check` call and replies with a scripted outcome.
///
/// The real check is a native TLS handshake, so the only way to exercise the
/// Dart side is to stand in for the platform. Every branch the interceptor
/// distinguishes is reachable from here.
class _FakeNativePinning {
  final List<Map<Object?, Object?>> calls = [];

  /// Reply for the next call: a result string, or a thrown [PlatformException].
  String result = 'CONNECTION_SECURE';
  Object? error;

  void install() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
      calls.add(Map<Object?, Object?>.from(call.arguments as Map));
      final failure = error;
      if (failure != null) throw failure;
      return result;
    });
  }

  /// Removes the handler so `check` throws [MissingPluginException], which is
  /// exactly what a platform without the plugin does.
  void uninstall() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  }

  List<String> get fingerprintsSent =>
      (calls.single['fingerprints'] as List).cast<String>();
}

/// Answers 200 to anything that gets past the pinning check.
class _OkAdapter implements HttpClientAdapter {
  int attempts = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    attempts++;
    return ResponseBody.fromString('ok', 200);
  }

  @override
  void close({bool force = false}) {}
}

CertificatePinningConfig _pinning({int timeout = 60}) {
  return CertificatePinningConfig(
    allowedSHAFingerprints: [kPrimaryFingerprint, kBackupFingerprint],
    timeout: timeout,
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
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeNativePinning native;

  setUp(() {
    native = _FakeNativePinning()..install();
  });

  tearDown(() {
    native.uninstall();
    NetworkLocale.setLocale('en');
  });

  group('NetworkConfig', () {
    test('has no pinning by default', () {
      const config = NetworkConfig(baseUrl: 'https://api.example.com');

      expect(config.certificatePinning, isNull);
    });

    test('still supports const construction without pinning', () {
      // Guards the backward-compatibility promise: the field must not force
      // existing `const NetworkConfig(...)` call sites to change.
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
      expect(config.certificatePinning!.allowedSHAFingerprints, hasLength(2));
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

    test('installs no pinning interceptor when pinning is off', () {
      final client = HttpClient(
        const NetworkConfig(baseUrl: 'https://api.example.com'),
      );
      addTearDown(client.dispose);

      expect(
        client.dio.interceptors.whereType<CertificatePinningInterceptor>(),
        isEmpty,
      );
    });

    test('installs the pinning interceptor ahead of every package one', () {
      // It must precede consumer interceptors, retry and the 401 handler, so
      // nothing downstream can observe or replay an unpinned request. Dio
      // prepends its own ImplyContentTypeInterceptor, so this is an ordering
      // assertion rather than an index-zero one.
      final consumer = InterceptorsWrapper();
      final client = HttpClient(NetworkConfig(
        baseUrl: 'https://api.example.com',
        certificatePinning: _pinning(),
        interceptors: [consumer],
      ));
      addTearDown(client.dispose);

      final chain = client.dio.interceptors;
      final pinningAt = chain.indexWhere(
        (i) => i is CertificatePinningInterceptor,
      );

      expect(pinningAt, isNonNegative);
      expect(pinningAt, lessThan(chain.indexOf(consumer)));
      expect(
        pinningAt,
        lessThan(chain.indexWhere((i) => i is RetryInterceptor)),
      );
    });

    test('leaves the certificate adapter untouched when pinning', () {
      // Verification is the plugin's job now; the adapter must keep normal
      // chain validation rather than being loosened in any way.
      final client = HttpClient(NetworkConfig(
        baseUrl: 'https://api.example.com',
        certificatePinning: _pinning(),
      ));
      addTearDown(client.dispose);

      final adapter = client.dio.httpClientAdapter as IOHttpClientAdapter;
      expect(adapter.createHttpClient, isNull);
      expect(adapter.validateCertificate, isNull);
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

  group('native check arguments', () {
    late HttpClient client;

    setUp(() {
      client = HttpClient(NetworkConfig(
        baseUrl: 'https://api.example.com',
        certificatePinning: _pinning(timeout: 15),
      ));
      client.dio.httpClientAdapter = _OkAdapter();
    });

    tearDown(() => client.dispose());

    test('forwards fingerprints as bare uppercase hex', () async {
      await client.dio.request<String>(
        '/ping',
        options: Options(responseType: ResponseType.plain),
      );

      expect(native.fingerprintsSent, [kPrimaryBare, kBackupBare]);
    });

    test('asks for SHA-256, never SHA-1', () async {
      await client.dio.request<String>(
        '/ping',
        options: Options(responseType: ResponseType.plain),
      );

      expect(native.calls.single['type'], 'SHA256');
    });

    test('forwards the configured timeout', () async {
      await client.dio.request<String>(
        '/ping',
        options: Options(responseType: ResponseType.plain),
      );

      expect(native.calls.single['timeout'], 15);
    });

    test('checks the base URL of the request', () async {
      await client.dio.request<String>(
        '/ping',
        options: Options(responseType: ResponseType.plain),
      );

      expect(native.calls.single['url'], 'https://api.example.com');
    });
  });

  group('a secure connection', () {
    test('lets the request through to the adapter', () async {
      final adapter = _OkAdapter();
      final client = HttpClient(NetworkConfig(
        baseUrl: 'https://api.example.com',
        certificatePinning: _pinning(),
      ));
      addTearDown(client.dispose);
      client.dio.httpClientAdapter = adapter;

      final response = await client.dio.request<String>(
        '/ping',
        options: Options(responseType: ResponseType.plain),
      );

      expect(response.statusCode, 200);
      expect(adapter.attempts, 1);
    });
  });

  group('failure surfacing', () {
    late HttpClient client;
    late _OkAdapter adapter;

    setUp(() {
      adapter = _OkAdapter();
      client = HttpClient(NetworkConfig(
        baseUrl: 'https://api.example.com',
        certificatePinning: _pinning(),
      ));
      client.dio.httpClientAdapter = adapter;
      native.result = 'CONNECTION_NOT_SECURE';
    });

    tearDown(() => client.dispose());

    test('surfaces a mismatch as CertificatePinningException', () async {
      final error = await _errorFrom(client, '/ping');
      final mapped = ErrorHandler.handleError(error);

      expect(mapped, isA<CertificatePinningException>());
      expect((mapped as CertificatePinningException).host, 'api.example.com');
      expect(mapped.errorType, 'CertificatePinningFailed');
    });

    test('never sends the request when the check fails', () async {
      await _errorFrom(client, '/ping');

      expect(adapter.attempts, 0);
    });

    test('is catchable as an ApiException', () async {
      final error = await _errorFrom(client, '/ping');
      final mapped = ErrorHandler.handleError(error);

      expect(mapped, isA<ApiException>());
    });

    test('is distinguishable from a generic network error', () async {
      final error = await _errorFrom(client, '/ping');

      expect(
        ErrorHandler.handleError(error),
        isA<CertificatePinningException>(),
      );
      expect(
        ErrorHandler.handleError(SocketException('down')),
        isNot(isA<CertificatePinningException>()),
      );
    });

    test('maps a CONNECTION_NOT_SECURE platform error too', () async {
      native
        ..result = ''
        ..error = PlatformException(code: 'CONNECTION_NOT_SECURE');

      final mapped = ErrorHandler.handleError(await _errorFrom(client, '/p'));

      expect(mapped, isA<CertificatePinningException>());
    });

    test('reports an unverifiable check as a pinning failure', () async {
      // A platform with no plugin, or an unreachable host: the certificate was
      // never shown to match, so "could not check" must not read as a pass.
      native.uninstall();

      final mapped = ErrorHandler.handleError(await _errorFrom(client, '/p'));

      expect(mapped, isA<CertificatePinningException>());
    });

    test('leaves NO_INTERNET as a connectivity error, not a security one',
        () async {
      native
        ..result = ''
        ..error = PlatformException(code: 'NO_INTERNET');

      final mapped =
          ErrorHandler.handleError(await _errorFrom(client, '/p')) as ApiException;

      expect(mapped, isNot(isA<CertificatePinningException>()));
      expect(mapped.errorType, 'NoInternetConnection');
    });

    test('never leaks a fingerprint into the user-facing message', () async {
      final mapped =
          ErrorHandler.handleError(await _errorFrom(client, '/p')) as ApiException;

      expect(mapped.message, isNot(contains(kPrimaryBare)));
      expect(mapped.message, isNot(contains(kBackupBare)));
    });

    test('uses an English message by default', () async {
      final mapped =
          ErrorHandler.handleError(await _errorFrom(client, '/p')) as ApiException;

      expect(mapped.message, 'Secure connection could not be verified.');
    });

    test('uses the Arabic message when the locale is ar', () async {
      NetworkLocale.setLocale('ar');

      final mapped =
          ErrorHandler.handleError(await _errorFrom(client, '/p')) as ApiException;

      expect(mapped.message, 'تعذر التحقق من الاتصال الآمن.');
      expect(mapped.message, isNot(contains('Secure')));
    });
  });

  group('retry', () {
    setUp(() => native.result = 'CONNECTION_NOT_SECURE');

    test('does not re-attempt a pin failure', () async {
      final client = HttpClient(NetworkConfig(
        baseUrl: 'https://api.example.com',
        certificatePinning: _pinning(),
        retry: const RetryPolicy(attempts: 3, delays: []),
      ));
      addTearDown(client.dispose);
      client.dio.httpClientAdapter = _OkAdapter();

      await _errorFrom(client, '/ping');

      expect(native.calls, hasLength(1));
    });

    test('does not re-attempt even when the request opts into retry', () async {
      final client = HttpClient(NetworkConfig(
        baseUrl: 'https://api.example.com',
        certificatePinning: _pinning(),
      ));
      addTearDown(client.dispose);
      client.dio.httpClientAdapter = _OkAdapter();

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

      expect(native.calls, hasLength(1));
    });

    test('evaluateRetry refuses a pin failure outright', () {
      // Defence in depth: even if the rejection reached the retry evaluator,
      // replaying the handshake would only repeat the same verdict.
      final error = DioException(
        requestOptions: RequestOptions(path: '/ping'),
        error: const CertificateNotVerifiedException(),
      );

      expect(
        evaluateRetry(error, 1, const RetryPolicy(attempts: 3, delays: [])),
        isFalse,
      );
    });

    test('evaluateRetry refuses an unverifiable check too', () {
      final error = DioException(
        requestOptions: RequestOptions(path: '/ping'),
        error: const CertificateCouldNotBeVerifiedException(),
      );

      expect(
        evaluateRetry(error, 1, const RetryPolicy(attempts: 3, delays: [])),
        isFalse,
      );
    });
  });
}
