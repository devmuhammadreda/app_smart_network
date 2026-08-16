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

/// Thrown when a host's certificate did not match its configured SPKI pins.
///
/// Extends [ApiException] so existing `catch (e) { if (e is ApiException) }`
/// handling keeps working, while `e is CertificatePinningException` separates a
/// security event from an ordinary connectivity blip:
///
/// ```dart
/// try {
///   await ApiService.instance.request(HttpMethod.get, '/me');
/// } on CertificatePinningException catch (e) {
///   security.report('pin_failure', host: e.host);
/// } on ApiException catch (e) {
///   showSnackBar(e.message);
/// }
/// ```
///
/// [message] is deliberately generic. The pins the server actually presented
/// are reported to [CertificatePinningConfig.onPinFailure] for telemetry and
/// never placed here, where they could reach the screen.
class CertificatePinningException extends ApiException {
  /// Host whose certificate failed the pin check.
  final String? host;

  const CertificatePinningException(
    String message, {
    this.host,
    super.originalError,
  }) : super(message, 0, errorType: 'CertificatePinningFailed');

  @override
  String toString() =>
      'CertificatePinningException: $message (Host: ${host ?? "unknown"})';
}
