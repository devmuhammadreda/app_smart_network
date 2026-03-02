// ============================================================================
// EXCEPTIONS
// ============================================================================

/// A typed, immutable value representing a single field-level validation
/// failure returned by the server (typically in a 422 response).
class ValidationError {
  final String field;
  final String message;

  const ValidationError({required this.field, required this.message});

  @override
  String toString() => 'ValidationError(field: $field, message: $message)';
}

/// Thrown for any network/HTTP error.
class ApiException implements Exception {
  final String message;
  final int statusCode;
  final dynamic originalError;
  final String? errorType;

  /// API-level error code returned by the server (e.g. `'UserExists'`).
  final String? apiErrorCode;

  /// Full response body, stored for debugging.
  final Map<String, dynamic>? responseData;

  /// Typed field-level validation errors (non-null; empty when not applicable).
  final List<ValidationError> validationErrors;

  const ApiException(
    this.message,
    this.statusCode, {
    this.originalError,
    this.errorType,
    this.apiErrorCode,
    this.responseData,
    this.validationErrors = const [],
  });

  @override
  String toString() {
    final codeInfo = apiErrorCode != null ? ' (Code: $apiErrorCode)' : '';
    return 'ApiException: $message$codeInfo (Status: $statusCode)';
  }

  // ── HTTP status helpers ───────────────────────────────────────────────────

  bool get isClientError => statusCode >= 400 && statusCode < 500;
  bool get isServerError => statusCode >= 500 && statusCode < 600;
  bool get isNetworkError => statusCode == 0;
  bool get isUnauthorized => statusCode == 401;
  bool get isForbidden => statusCode == 403;
  bool get isNotFound => statusCode == 404;
  bool get isValidationError => statusCode == 422;
  bool get isRateLimited => statusCode == 429;
  bool get isTimeout => statusCode == 408;

  /// Returns `true` when the server-returned error code matches [code].
  bool hasApiErrorCode(String code) => apiErrorCode == code;

  /// Reads a typed field from [responseData].
  T? getResponseField<T>(String key) => responseData?[key] as T?;

  /// Broad category string useful for logging / analytics.
  String get errorCategory {
    if (isNetworkError) return 'Network Error';
    if (isUnauthorized) return 'Authentication Error';
    if (isForbidden) return 'Access Error';
    if (isNotFound) return 'Resource Error';
    if (isValidationError) return 'Validation Error';
    if (isRateLimited) return 'Rate Limit Error';
    if (isTimeout) return 'Timeout Error';
    if (isClientError) return 'Client Error';
    if (isServerError) return 'Server Error';
    if (apiErrorCode != null) return 'API Error ($apiErrorCode)';
    return 'Unknown Error';
  }
}
