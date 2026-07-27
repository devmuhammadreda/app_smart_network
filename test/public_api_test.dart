// Deliberately imports only the public barrel — no `package:dio/dio.dart`.
// This file failing to compile means the barrel is missing an export.
import 'package:app_smart_network/app_smart_network.dart';
import 'package:flutter_test/flutter_test.dart';

class _BarrelInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) =>
      handler.next(options);

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) =>
      handler.next(response);

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) =>
      handler.next(err);
}

class _BarrelQueuedInterceptor extends QueuedInterceptor {}

void main() {
  test('interceptor authoring types are exported from the public barrel', () {
    final config = NetworkConfig(
      baseUrl: 'https://example.com',
      interceptors: [
        _BarrelInterceptor(),
        _BarrelQueuedInterceptor(),
        InterceptorsWrapper(),
        QueuedInterceptorsWrapper(),
      ],
    );

    expect(config.interceptors, hasLength(4));
    expect(config.interceptors.first, isA<Interceptor>());
  });
}
