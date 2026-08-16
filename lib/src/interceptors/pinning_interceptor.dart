import 'package:dio/dio.dart';

import '../error/exceptions.dart';
import '../security/certificate_pinner.dart';

/// Re-types a certificate rejection on a pinned host as a security event.
///
/// Dio reports a rejected `validateCertificate` as a plain
/// [DioExceptionType.badCertificate], which is indistinguishable from any
/// other TLS complaint. This interceptor attaches a
/// [CertificatePinningException] whenever such a failure happens on a host the
/// app actually pinned, so `ErrorHandler` can surface it as a security event
/// and the consuming app can report it as one.
///
/// It is installed at the head of the chain — ahead of consumer interceptors,
/// retry, and the 401 handler — so every downstream handler sees the typed
/// error. It only ever replaces the exception's payload, so the relative order
/// of the interceptors around it is unchanged.
class PinningInterceptor extends Interceptor {
  PinningInterceptor(this._pinner, this._message);

  final CertificatePinner _pinner;

  /// Resolved lazily so the message follows the locale active at failure time.
  final String Function() _message;

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (err.type != DioExceptionType.badCertificate) {
      handler.next(err);
      return;
    }

    final host = err.requestOptions.uri.host;
    if (_pinner.pinsFor(host) == null) {
      handler.next(err);
      return;
    }

    handler.next(
      err.copyWith(
        error: CertificatePinningException(
          _message(),
          host: host,
          originalError: err.error,
        ),
      ),
    );
  }
}
