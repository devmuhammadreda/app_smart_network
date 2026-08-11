import 'dart:typed_data';

import 'package:app_smart_network/src/client/http_client.dart';
import 'package:app_smart_network/src/config/network_config.dart';
import 'package:app_smart_network/src/config/retry_policy.dart';
import 'package:app_smart_network/src/services/request_service.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// Counts every attempt that reaches the wire and answers with [statusCode].
class _CountingAdapter implements HttpClientAdapter {
  _CountingAdapter({this.statusCode = 503});

  final int statusCode;
  int attempts = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    attempts++;
    return ResponseBody.fromString('boom', statusCode);
  }

  @override
  void close({bool force = false}) {}
}

/// Reports a connected device so `ensureConnected()` passes without touching
/// platform channels.
class _FakeConnectivity implements Connectivity {
  @override
  Future<List<ConnectivityResult>> checkConnectivity() async =>
      [ConnectivityResult.wifi];

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged =>
      Stream.value([ConnectivityResult.wifi]);
}

/// Retry with no backoff, so the suite never sleeps.
const _instant = <Duration>[];

/// Global retry turned off, but still fast for requests that opt back in.
const _offGlobally = RetryPolicy(attempts: 0, delays: _instant);

HttpClient _clientWith(RetryPolicy? policy, _CountingAdapter adapter) {
  final client = HttpClient(NetworkConfig(
    baseUrl: 'https://example.com',
    retry: policy,
  ));
  client.dio.httpClientAdapter = adapter;
  return client;
}

/// Plain response type keeps the request off the background JSON transformer.
Future<void> _send(
  HttpClient client, {
  String method = 'GET',
  RetryPolicy? retry,
}) async {
  final options = attachRetryPolicy(
    Options(method: method, responseType: ResponseType.plain),
    retry,
  );
  await client.dio.request<String>('/ping', options: options);
}

Future<int> _attemptsFor(
  RetryPolicy? globalPolicy, {
  String method = 'GET',
  RetryPolicy? retry,
  int statusCode = 503,
}) async {
  final adapter = _CountingAdapter(statusCode: statusCode);
  final client = _clientWith(globalPolicy, adapter);
  addTearDown(client.dispose);

  await expectLater(
    _send(client, method: method, retry: retry),
    throwsA(isA<DioException>()),
  );

  return adapter.attempts;
}

void main() {
  group('RetryPolicy', () {
    test('off disables retry', () {
      expect(RetryPolicy.off.attempts, 0);
    });

    test('defaults retry idempotent methods three times', () {
      const policy = RetryPolicy();

      expect(policy.attempts, 3);
      expect(policy.methods, contains('GET'));
      expect(policy.methods, isNot(contains('POST')));
    });

    test('copyWith replaces only the named fields', () {
      const policy = RetryPolicy(attempts: 2);

      final updated = policy.copyWith(attempts: 5);

      expect(updated.attempts, 5);
      expect(updated.methods, policy.methods);
      expect(updated.statuses, policy.statuses);
    });

    test('rejects an attempts count above the ceiling', () {
      expect(
        () => RetryPolicy(attempts: RetryPolicy.maxAttempts + 1),
        throwsA(isA<AssertionError>()),
      );
    });

    test('rejects a negative attempts count', () {
      expect(() => RetryPolicy(attempts: -1), throwsA(isA<AssertionError>()));
    });
  });

  group('global retry policy', () {
    test('a retryable GET is attempted once plus the configured retries',
        () async {
      expect(await _attemptsFor(const RetryPolicy(delays: _instant)), 4);
    });

    test('a null policy disables retry entirely', () async {
      expect(await _attemptsFor(null), 1);
    });

    test('attempts: 0 disables retry entirely', () async {
      expect(await _attemptsFor(_offGlobally), 1);
    });

    test('a non-idempotent method is not retried', () async {
      expect(
        await _attemptsFor(const RetryPolicy(delays: _instant), method: 'POST'),
        1,
      );
    });

    test('a non-retryable status is not retried', () async {
      expect(
        await _attemptsFor(
          const RetryPolicy(delays: _instant),
          statusCode: 404,
        ),
        1,
      );
    });

    test('a 401 is not retried, so the session handler fires once', () async {
      var unauthorizedCalls = 0;
      final adapter = _CountingAdapter(statusCode: 401);
      final client = HttpClient(NetworkConfig(
        baseUrl: 'https://example.com',
        retry: const RetryPolicy(delays: _instant),
        onUnauthorized: () => unauthorizedCalls++,
      ));
      addTearDown(client.dispose);
      client.dio.httpClientAdapter = adapter;

      await expectLater(_send(client), throwsA(isA<DioException>()));

      expect(adapter.attempts, 1);
      expect(unauthorizedCalls, 1);
    });

    test('a custom status set is honoured', () async {
      expect(
        await _attemptsFor(
          const RetryPolicy(delays: _instant, statuses: {409}),
          statusCode: 409,
        ),
        4,
      );
    });

    test('a custom method set is honoured', () async {
      expect(
        await _attemptsFor(
          const RetryPolicy(delays: _instant, methods: {'POST'}),
          method: 'POST',
        ),
        4,
      );
    });
  });

  group('per-request retry policy', () {
    test('RetryPolicy.off opts a single request out', () async {
      expect(
        await _attemptsFor(
          const RetryPolicy(delays: _instant),
          retry: RetryPolicy.off,
        ),
        1,
      );
    });

    test('a per-request policy overrides the global attempts count', () async {
      expect(
        await _attemptsFor(
          const RetryPolicy(delays: _instant),
          retry: const RetryPolicy(attempts: 1),
        ),
        2,
      );
    });

    test('a per-request policy opts in when retry is off globally', () async {
      expect(
        await _attemptsFor(_offGlobally, retry: const RetryPolicy(attempts: 2)),
        3,
      );
    });

    test('a per-request policy bypasses the method allowlist', () async {
      expect(
        await _attemptsFor(
          const RetryPolicy(delays: _instant),
          method: 'POST',
          retry: const RetryPolicy(attempts: 5),
        ),
        6,
      );
    });

    test('a per-request attempts count above the global one is not capped',
        () async {
      expect(
        await _attemptsFor(
          const RetryPolicy(attempts: 1, delays: _instant),
          retry: const RetryPolicy(attempts: 8),
        ),
        9,
      );
    });

    test('a per-request status set overrides the global one', () async {
      expect(
        await _attemptsFor(
          const RetryPolicy(delays: _instant),
          retry: const RetryPolicy(attempts: 2, statuses: {409}),
          statusCode: 409,
        ),
        3,
      );
    });

    test('a per-request policy still respects its own status set', () async {
      expect(
        await _attemptsFor(
          const RetryPolicy(delays: _instant),
          retry: const RetryPolicy(attempts: 3, statuses: {409}),
          statusCode: 503,
        ),
        1,
      );
    });
  });

  group('attachRetryPolicy', () {
    test('returns the original options when no policy is given', () {
      final options = Options(headers: {'X-Trace': 'abc'});

      expect(attachRetryPolicy(options, null), same(options));
    });

    test('preserves caller-supplied extra entries', () {
      final options = Options(extra: {'flavour': 'vanilla'});

      final withPolicy = attachRetryPolicy(options, RetryPolicy.off);

      expect(withPolicy.extra!['flavour'], 'vanilla');
    });

    test('does not mutate the caller-supplied options', () {
      final options = Options(extra: {'flavour': 'vanilla'});

      attachRetryPolicy(options, RetryPolicy.off);

      expect(options.extra, {'flavour': 'vanilla'});
    });
  });

  group('RequestService.retry', () {
    test('threads a per-request policy through to the interceptor', () async {
      final adapter = _CountingAdapter();
      final client = _clientWith(const RetryPolicy(delays: _instant), adapter);
      addTearDown(client.dispose);
      final service = RequestService(client, connectivity: _FakeConnectivity());

      await expectLater(
        service.execute<String>(
          HttpMethod.get,
          '/ping',
          options: Options(responseType: ResponseType.plain),
          retry: RetryPolicy.off,
        ),
        throwsA(anything),
      );

      expect(adapter.attempts, 1);
    });

    test('falls back to the global policy when no policy is given', () async {
      final adapter = _CountingAdapter();
      final client = _clientWith(const RetryPolicy(delays: _instant), adapter);
      addTearDown(client.dispose);
      final service = RequestService(client, connectivity: _FakeConnectivity());

      await expectLater(
        service.execute<String>(
          HttpMethod.get,
          '/ping',
          options: Options(responseType: ResponseType.plain),
        ),
        throwsA(anything),
      );

      expect(adapter.attempts, 4);
    });

    test('retries a POST that explicitly opts in', () async {
      final adapter = _CountingAdapter();
      final client = _clientWith(const RetryPolicy(delays: _instant), adapter);
      addTearDown(client.dispose);
      final service = RequestService(client, connectivity: _FakeConnectivity());

      await expectLater(
        service.execute<String>(
          HttpMethod.post,
          '/sync',
          options: Options(responseType: ResponseType.plain),
          retry: const RetryPolicy(attempts: 2),
        ),
        throwsA(anything),
      );

      expect(adapter.attempts, 3);
    });
  });
}
