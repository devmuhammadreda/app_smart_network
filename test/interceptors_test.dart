import 'dart:typed_data';

import 'package:app_smart_network/src/client/http_client.dart';
import 'package:app_smart_network/src/config/network_config.dart';
import 'package:app_smart_network/src/config/retry_policy.dart';
import 'package:app_smart_network/src/interceptors/unauth_interceptor.dart';
import 'package:dio/dio.dart';
import 'package:dio_smart_retry/dio_smart_retry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pretty_dio_logger/pretty_dio_logger.dart';

/// Returns a canned response without touching the network and records every
/// [RequestOptions] that reaches the wire.
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter({this.statusCode = 200});

  final int statusCode;
  final List<RequestOptions> captured = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    captured.add(options);
    return ResponseBody.fromString('ok', statusCode);
  }

  @override
  void close({bool force = false}) {}
}

/// Appends a label to [events] for every callback it sees, and optionally adds
/// a header on the way out.
class _RecordingInterceptor extends Interceptor {
  _RecordingInterceptor(this.events, {this.headerToAdd});

  final List<String> events;
  final MapEntry<String, String>? headerToAdd;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    events.add('request');
    final header = headerToAdd;
    if (header != null) options.headers[header.key] = header.value;
    handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    events.add('error');
    handler.next(err);
  }
}

/// Plain response type keeps the request off the background JSON transformer,
/// so no isolate work happens during tests.
Future<void> _get(HttpClient client) => client.dio.get<String>(
      '/ping',
      options: Options(responseType: ResponseType.plain),
    );

void main() {
  group('NetworkConfig.interceptors', () {
    test('a custom interceptor receives outgoing requests', () async {
      final events = <String>[];
      final client = HttpClient(NetworkConfig(
        baseUrl: 'https://example.com',
        interceptors: [_RecordingInterceptor(events)],
      ));
      addTearDown(client.dispose);
      client.dio.httpClientAdapter = _FakeAdapter();

      await _get(client);

      expect(events, ['request']);
    });

    test('headers added by a custom interceptor reach the adapter', () async {
      final adapter = _FakeAdapter();
      final client = HttpClient(NetworkConfig(
        baseUrl: 'https://example.com',
        interceptors: [
          _RecordingInterceptor(
            <String>[],
            headerToAdd: const MapEntry('X-Trace-Id', 'abc123'),
          ),
        ],
      ));
      addTearDown(client.dispose);
      client.dio.httpClientAdapter = adapter;

      await _get(client);

      expect(adapter.captured.single.headers['X-Trace-Id'], 'abc123');
    });

    test('custom onError runs before onUnauthorized fires', () async {
      final events = <String>[];
      final client = HttpClient(NetworkConfig(
        baseUrl: 'https://example.com',
        interceptors: [_RecordingInterceptor(events)],
        onUnauthorized: () => events.add('unauthorized'),
      ));
      addTearDown(client.dispose);
      client.dio.httpClientAdapter = _FakeAdapter(statusCode: 401);

      await expectLater(_get(client), throwsA(isA<DioException>()));

      expect(events, ['request', 'error', 'unauthorized']);
    });

    test(
        'a custom interceptor that resolves a 401 stops onUnauthorized from '
        'firing', () async {
      final events = <String>[];
      final resolvingInterceptor = InterceptorsWrapper(
        onError: (err, handler) {
          handler.resolve(Response(
            requestOptions: err.requestOptions,
            statusCode: 200,
          ));
        },
      );
      final client = HttpClient(NetworkConfig(
        baseUrl: 'https://example.com',
        interceptors: [resolvingInterceptor],
        onUnauthorized: () => events.add('unauthorized'),
      ));
      addTearDown(client.dispose);
      client.dio.httpClientAdapter = _FakeAdapter(statusCode: 401);

      final response = await client.dio.get<String>(
        '/ping',
        options: Options(responseType: ResponseType.plain),
      );

      expect(response.statusCode, 200);
      expect(events, isNot(contains('unauthorized')));
    });

    test(
        'custom interceptors run before retry, the 401 handler, and the '
        'debug logger', () {
      final custom = _RecordingInterceptor(<String>[]);
      final client = HttpClient(NetworkConfig(
        baseUrl: 'https://example.com',
        interceptors: [custom],
      ));
      addTearDown(client.dispose);

      final chain = client.dio.interceptors;
      final customIndex = chain.indexOf(custom);
      final retryIndex = chain.indexWhere((i) => i is RetryInterceptor);
      final unauthIndex = chain.indexWhere((i) => i is UnAuthInterceptor);
      final loggerIndex = chain.indexWhere((i) => i is PrettyDioLogger);

      // kDebugMode is true under `flutter test`, so the logger is registered
      // and its position can be asserted on.
      expect(loggerIndex, greaterThanOrEqualTo(0));

      expect(customIndex, lessThan(retryIndex));
      expect(retryIndex, lessThan(unauthIndex));
      expect(unauthIndex, lessThan(loggerIndex));
    });

    test(
        'a request that opts out of retry reports exactly one onError',
        () async {
      final events = <String>[];
      final client = HttpClient(NetworkConfig(
        baseUrl: 'https://example.com',
        // No backoff: the request opts out, so this is never waited on, but
        // it keeps the test honest if that ever regresses.
        retry: const RetryPolicy(delays: []),
        interceptors: [_RecordingInterceptor(events)],
      ));
      addTearDown(client.dispose);
      client.dio.httpClientAdapter = _FakeAdapter(statusCode: 503);

      await expectLater(
        client.dio.get<String>(
          '/ping',
          options: attachRetryPolicy(
            Options(responseType: ResponseType.plain),
            RetryPolicy.off,
          ),
        ),
        throwsA(isA<DioException>()),
      );

      expect(events.where((e) => e == 'error'), hasLength(1));
    });

    test('default config registers the built-ins and nothing custom', () {
      final client =
          HttpClient(const NetworkConfig(baseUrl: 'https://example.com'));
      addTearDown(client.dispose);

      expect(
          client.dio.interceptors.whereType<RetryInterceptor>(), hasLength(1));
      expect(
          client.dio.interceptors.whereType<UnAuthInterceptor>(), hasLength(1));
      expect(
          client.dio.interceptors.whereType<_RecordingInterceptor>(), isEmpty);
    });
  });
}
