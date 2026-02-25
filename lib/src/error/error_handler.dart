import 'dart:io';

import 'package:dio/dio.dart';

import '../i18n/network_locale.dart';
import 'exceptions.dart';

// ============================================================================
// ERROR HANDLER
// ============================================================================

class ErrorHandler {
  ErrorHandler._();

  /// Converts any thrown [error] into an [ApiException].
  static Exception handleError(dynamic error) {
    if (error is ApiException) return error;
    if (error is DioException) return _handleDioError(error);
    return ApiException(
      NetworkLocale.getErrorMessage('UnexpectedError'),
      0,
      errorType: 'UnexpectedError',
    );
  }

  static ApiException _handleDioError(DioException error) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
        return ApiException(
          NetworkLocale.getErrorMessage('ConnectionTimeout'),
          408,
          errorType: 'ConnectionTimeout',
          originalError: error,
        );
      case DioExceptionType.sendTimeout:
        return ApiException(
          NetworkLocale.getErrorMessage('SendTimeout'),
          408,
          errorType: 'SendTimeout',
          originalError: error,
        );
      case DioExceptionType.receiveTimeout:
        return ApiException(
          NetworkLocale.getErrorMessage('ReceiveTimeout'),
          408,
          errorType: 'ReceiveTimeout',
          originalError: error,
        );
      case DioExceptionType.badResponse:
        return _handleStatusCodeError(error);
      case DioExceptionType.cancel:
        return ApiException(
          NetworkLocale.getErrorMessage('RequestCancelled'),
          0,
          errorType: 'RequestCancelled',
          originalError: error,
        );
      case DioExceptionType.badCertificate:
        return ApiException(
          NetworkLocale.getErrorMessage('BadCertificate'),
          0,
          errorType: 'BadCertificate',
          originalError: error,
        );
      case DioExceptionType.connectionError:
        return ApiException(
          NetworkLocale.getErrorMessage('ConnectionError'),
          0,
          errorType: 'ConnectionError',
          originalError: error,
        );
      case DioExceptionType.unknown:
        return _handleUnknownError(error);
    }
  }

  static ApiException _handleStatusCodeError(DioException error) {
    final statusCode = error.response?.statusCode ?? 0;
    final responseData = error.response?.data;
    final extracted = _extractErrorData(responseData);
    final message =
        extracted['message'] ?? NetworkLocale.getStatusMessage(statusCode);
    final apiErrorCode = extracted['code'];

    return ApiException(
      message,
      statusCode,
      errorType: 'BadResponse',
      apiErrorCode: apiErrorCode,
      responseData: responseData is Map<String, dynamic> ? responseData : null,
      originalError: error,
    );
  }

  static ApiException _handleUnknownError(DioException error) {
    if (error.error is SocketException) {
      return ApiException(
        NetworkLocale.getErrorMessage('NoInternetConnection'),
        0,
        errorType: 'NoInternetConnection',
        originalError: error,
      );
    }
    if (error.error is HttpException) {
      return ApiException(
        NetworkLocale.getErrorMessage('NetworkError'),
        0,
        errorType: 'NetworkError',
        originalError: error,
      );
    }
    return ApiException(
      error.error?.toString() ??
          NetworkLocale.getErrorMessage('UnexpectedError'),
      0,
      errorType: 'UnknownError',
      originalError: error,
    );
  }

  /// Extracts `message` and API `code` from various response body shapes.
  static Map<String, String?> _extractErrorData(dynamic responseData) {
    final result = <String, String?>{'message': null, 'code': null};
    if (responseData == null) return result;

    if (responseData is Map<String, dynamic>) {
      result['message'] = responseData['message']?.toString() ??
          responseData['error']?.toString() ??
          responseData['detail']?.toString() ??
          responseData['msg']?.toString();

      result['code'] = responseData['code']?.toString() ??
          responseData['errorCode']?.toString() ??
          responseData['error_code']?.toString();
    } else if (responseData is String) {
      result['message'] = responseData;
    }
    return result;
  }
}
