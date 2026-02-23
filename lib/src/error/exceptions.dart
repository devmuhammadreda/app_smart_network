// ============================================================================
// EXCEPTIONS
// ============================================================================

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

  const ApiException(
    this.message,
    this.statusCode, {
    this.originalError,
    this.errorType,
    this.apiErrorCode,
    this.responseData,
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

/// Thrown when reading from or writing to a local cache fails.
class CacheException implements Exception {
  final String message;
  final int code;
  final String apiErrorCode;

  const CacheException({
    required this.message,
    required this.apiErrorCode,
    required this.code,
  });

  @override
  String toString() => 'CacheException: $message';
}

/// Thrown when a storage operation (e.g. secure storage) fails.
class StorageException implements Exception {
  final String message;

  const StorageException(this.message);

  @override
  String toString() => 'StorageException: $message';
}

/// Thrown when SIM-card related operations fail.
class SimCardException implements Exception {
  final String message;

  const SimCardException(this.message);

  @override
  String toString() => 'SimCardException: $message';
}

/// Thrown when reading device serial information fails.
class DeviceSerialException implements Exception {
  final String message;
  final String? code;

  const DeviceSerialException(this.message, {this.code});

  @override
  String toString() =>
      'DeviceSerialException: $message${code != null ? ' (Code: $code)' : ''}';
}
