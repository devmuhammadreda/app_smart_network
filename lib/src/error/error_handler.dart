import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';

import '../config/network_config.dart';
import '../i18n/network_locale.dart';
import 'exceptions.dart';

// ============================================================================
// ERROR HANDLER
// ============================================================================

class ErrorHandler {
  ErrorHandler._();

  /// Converts any thrown [error] into an [ApiException].
  ///
  /// [parser] is an optional consumer-supplied callback that extracts
  /// structured error data from the server response body. If [parser] is
  /// `null` or returns `null`, the built-in extraction logic is used.
  static Future<Exception> handleError(
    dynamic error, {
    ErrorBodyParser? parser,
  }) async {
    if (error is ApiException) return error;
    if (error is DioException) return _handleDioError(error, parser: parser);
    return ApiException(
      NetworkLocale.getErrorMessage('UnexpectedError'),
      0,
      errorType: 'UnexpectedError',
    );
  }

  static Future<ApiException> _handleDioError(
    DioException error, {
    ErrorBodyParser? parser,
  }) async {
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
        return _handleStatusCodeError(error, parser: parser);
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

  static Future<ApiException> _handleStatusCodeError(
    DioException error, {
    ErrorBodyParser? parser,
  }) async {
    final statusCode = error.response?.statusCode ?? 0;
    final responseData = error.response?.data;

    // Try consumer-supplied parser first.
    if (parser != null && responseData != null) {
      final parserResult =
          await Future.value(parser(responseData, statusCode));
      if (parserResult != null) {
        return ApiException(
          parserResult.message ??
              NetworkLocale.getStatusMessage(statusCode),
          statusCode,
          errorType: 'BadResponse',
          apiErrorCode: parserResult.apiErrorCode,
          validationErrors: parserResult.validationErrors,
          responseData:
              responseData is Map<String, dynamic> ? responseData : null,
          originalError: error,
        );
      }
    }

    // Built-in extraction fallback.
    final extracted = _extractErrorData(responseData);
    final message =
        extracted['message'] ?? NetworkLocale.getStatusMessage(statusCode);
    final apiErrorCode = extracted['code'];
    final validationErrors = _extractValidationErrors(responseData);

    return ApiException(
      message,
      statusCode,
      errorType: 'BadResponse',
      apiErrorCode: apiErrorCode,
      validationErrors: validationErrors,
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

  /// Extracts typed [ValidationError] list from common response body shapes:
  /// - `{"errors": [{"field": "...", "message": "..."}]}`
  /// - `{"error": {"details": [...]}}`
  /// - `{"data": {"errors": [...]}}`
  static List<ValidationError> _extractValidationErrors(dynamic responseData) {
    if (responseData is! Map<String, dynamic>) return const [];

    List<dynamic>? rawList;

    // Pattern 1: top-level "errors" array
    final errors = responseData['errors'];
    if (errors is List) {
      rawList = errors;
    }

    // Pattern 2: "error.details" nested array
    if (rawList == null) {
      final error = responseData['error'];
      if (error is Map<String, dynamic>) {
        final details = error['details'];
        if (details is List) rawList = details;
      }
    }

    // Pattern 3: "data.errors" nested array
    if (rawList == null) {
      final data = responseData['data'];
      if (data is Map<String, dynamic>) {
        final dataErrors = data['errors'];
        if (dataErrors is List) rawList = dataErrors;
      }
    }

    if (rawList == null) return const [];

    return rawList
        .whereType<Map<String, dynamic>>()
        .map((e) => ValidationError(
              field: e['field']?.toString() ?? '',
              message: e['message']?.toString() ??
                  e['msg']?.toString() ??
                  e['detail']?.toString() ??
                  '',
            ))
        .toList();
  }
}
