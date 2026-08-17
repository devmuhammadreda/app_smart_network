// Deliberately imports only the public barrel — no `package:dio/dio.dart`.
// This file failing to compile means the barrel is missing an export.
import 'package:app_smart_network/app_smart_network.dart';
import 'package:flutter_test/flutter_test.dart';

class _BarrelInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    // Exercises ResponseType from the barrel export.
    options.responseType = ResponseType.plain;
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) =>
      handler.next(response);

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    // Exercises DioExceptionType from the barrel export.
    if (err.type == DioExceptionType.badResponse) {
      handler.next(err);
      return;
    }
    handler.next(err);
  }
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

  test('certificate pinning types are exported from the public barrel', () {
    // Everything a consumer needs to configure and observe pinning must be
    // reachable without depending on `dio` or on `src/` paths.
    void onFailure(String host, List<String> presentedPins) {}
    final OnPinFailureCallback typedCallback = onFailure;

    final config = NetworkConfig(
      baseUrl: 'https://api.example.com',
      certificatePinning: CertificatePinningConfig(
        pins: {
          'api.example.com': [
            'sha256/U1lYtAEMYq6Unbc802/QoAWjlMzc9sv4z+5DbEInlEI=',
            'sha256/0QUH7apNYrGfDUVuwaNqWhFUhcpXXhpK2VtczeICUIY=',
          ],
        },
        enforce: true,
        includeSubdomains: true,
        onPinFailure: typedCallback,
      ),
    );

    expect(config.certificatePinning, isA<CertificatePinningConfig>());
    expect(kMinimumPinsPerHost, 2);
  });

  test('CertificatePinningException is catchable as an ApiException', () {
    const error = CertificatePinningException(
      'Secure connection could not be verified.',
      host: 'api.example.com',
    );

    expect(error, isA<ApiException>());
    expect(error.host, 'api.example.com');
    expect(error.statusCode, 0);
    expect(error.errorType, 'CertificatePinningFailed');
    expect(error.toString(), contains('api.example.com'));
  });
}
