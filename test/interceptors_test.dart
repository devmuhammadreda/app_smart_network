import 'dart:typed_data';

import 'package:app_smart_network/src/client/http_client.dart';
import 'package:app_smart_network/src/config/network_config.dart';
import 'package:app_smart_network/src/interceptors/unauth_interceptor.dart';
import 'package:dio/dio.dart';
import 'package:dio_smart_retry/dio_smart_retry.dart';
import 'package:flutter_test/flutter_test.dart';

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
      client.dio.httpClientAdapter = _FakeAdapter();

      await _get(client);

      expect(events, ['request']);
      client.dispose();
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
      client.dio.httpClientAdapter = adapter;

      await _get(client);

      expect(adapter.captured.single.headers['X-Trace-Id'], 'abc123');
      client.dispose();
    });

    test('custom onError runs before onUnauthorized fires', () async {
      final events = <String>[];
      final client = HttpClient(NetworkConfig(
        baseUrl: 'https://example.com',
        interceptors: [_RecordingInterceptor(events)],
        onUnauthorized: () => events.add('unauthorized'),
      ));
      client.dio.httpClientAdapter = _FakeAdapter(statusCode: 401);

      await expectLater(_get(client), throwsA(isA<DioException>()));

      expect(events, ['request', 'error', 'unauthorized']);
      client.dispose();
    });

    test('custom interceptors sit between retry and the 401 handler', () {
      final custom = _RecordingInterceptor(<String>[]);
      final client = HttpClient(NetworkConfig(
        baseUrl: 'https://example.com',
        interceptors: [custom],
      ));

      final chain = client.dio.interceptors;
      expect(
        chain.indexWhere((i) => i is RetryInterceptor),
        lessThan(chain.indexOf(custom)),
      );
      expect(
        chain.indexOf(custom),
        lessThan(chain.indexWhere((i) => i is UnAuthInterceptor)),
      );
      client.dispose();
    });

    test('default config registers the built-ins and nothing custom', () {
      final client =
          HttpClient(const NetworkConfig(baseUrl: 'https://example.com'));

      expect(
          client.dio.interceptors.whereType<RetryInterceptor>(), hasLength(1));
      expect(
          client.dio.interceptors.whereType<UnAuthInterceptor>(), hasLength(1));
      expect(
          client.dio.interceptors.whereType<_RecordingInterceptor>(), isEmpty);
      client.dispose();
    });
  });
}
