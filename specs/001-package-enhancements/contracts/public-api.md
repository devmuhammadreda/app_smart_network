# Public API Contract: v1.1.0

**Package**: `app_smart_network`
**Version**: 1.1.0 (MINOR — all additions, no removals)
**Date**: 2026-03-01

This document lists every new or changed public symbol in v1.1.0.
Existing symbols not mentioned here are **unchanged**.

---

## New Public Classes

### `ValidationError`

```dart
class ValidationError {
  final String field;
  final String message;
  const ValidationError({required this.field, required this.message});
}
```

Exported from: `package:app_smart_network/app_smart_network.dart`

---

### `AppSmartNetworkService`

Canonical entry-point class. Replaces `ApiService` as the primary name.
Identical public API to `ApiService` v1.0.3 plus the methods below.

```dart
class AppSmartNetworkService {
  // ── Singleton ──────────────────────────────────────────────────────────
  static AppSmartNetworkService get instance { ... }
  static bool get isInitialized { ... }
  static void initialize(NetworkConfig config) { ... }

  // ── Dynamic configuration ──────────────────────────────────────────────
  void configure({
    String? baseUrl,
    int? connectTimeoutMs,
    int? receiveTimeoutMs,
    Map<String, dynamic>? headers,
  }) { ... }

  // ── Auth ───────────────────────────────────────────────────────────────
  void setAuthToken(String token) { ... }
  void removeAuthToken() { ... }

  // ── Locale ─────────────────────────────────────────────────────────────
  void setAppLocale(String locale) { ... }
  void removeAppLocale() { ... }

  // ── Request ────────────────────────────────────────────────────────────
  Future<Response<T>> request<T>(
    HttpMethod method,
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
    String? baseUrl,
    bool deduplicate = false,          // NEW in v1.1.0
  }) { ... }

  // ── Download ───────────────────────────────────────────────────────────
  Future<Response> download(
    String urlPath,
    String savePath, {
    ProgressCallback? onReceiveProgress,
    Map<String, dynamic>? queryParameters,
    CancelToken? cancelToken,
    bool deleteOnError = true,
    String lengthHeader,
    Options? options,
    String? baseUrl,
  }) { ... }

  // ── Upload ─────────────────────────────────────────────────────────────
  Future<Response<T>> uploadFile<T>(
    String path,
    File file, {
    String fieldName = 'file',
    String? fileName,
    Map<String, dynamic>? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    ProgressCallback? onSendProgress,
    String? baseUrl,
  }) { ... }

  // ── Lifecycle ──────────────────────────────────────────────────────────
  void dispose() { ... }
}
```

Exported from: `package:app_smart_network/app_smart_network.dart`

---

## Deprecated Symbols

### `ApiService` (deprecated typedef)

```dart
@Deprecated('Use AppSmartNetworkService instead. Will be removed in v2.0.0.')
typedef ApiService = AppSmartNetworkService;
```

**Migration**: Replace every `ApiService` reference with `AppSmartNetworkService`.
All static methods, getters, and instance methods are identical.

---

## Updated Public Classes

### `NetworkConfig` (updated)

```dart
class NetworkConfig {
  // ── Existing fields (unchanged) ─────────────────────────────────────────
  final String baseUrl;
  final Duration connectTimeout;
  final Duration receiveTimeout;
  final Map<String, String>? defaultHeaders;
  final bool allowBadCertificate;
  final OnUnauthorizedCallback? onUnauthorized;

  // ── NEW in v1.1.0 ────────────────────────────────────────────────────────
  final ErrorBodyParser? errorBodyParser;
  final TokenRefreshCallback? tokenRefresher;
  final RefreshEndpointPredicate? refreshEndpointPredicate;
  final List<RequestHook> requestHooks;
  final List<ResponseHook> responseHooks;

  const NetworkConfig({
    required this.baseUrl,
    this.connectTimeout = const Duration(milliseconds: 30000),
    this.receiveTimeout = const Duration(milliseconds: 30000),
    this.defaultHeaders,
    this.allowBadCertificate = false,
    this.onUnauthorized,
    // New optional fields:
    this.errorBodyParser,
    this.tokenRefresher,
    this.refreshEndpointPredicate,
    this.requestHooks = const [],
    this.responseHooks = const [],
  });
}
```

### `ApiException` (updated)

```dart
class ApiException implements Exception {
  // ── Existing fields (unchanged) ─────────────────────────────────────────
  final String message;
  final int statusCode;
  final dynamic originalError;
  final String? errorType;
  final String? apiErrorCode;
  final Map<String, dynamic>? responseData;

  // ── NEW in v1.1.0 ────────────────────────────────────────────────────────
  final List<ValidationError> validationErrors;   // non-null, defaults to []

  const ApiException(
    this.message,
    this.statusCode, {
    this.originalError,
    this.errorType,
    this.apiErrorCode,
    this.responseData,
    this.validationErrors = const [],             // NEW — backward compatible
  });

  // All existing getters and methods unchanged:
  bool get isClientError { ... }
  bool get isServerError { ... }
  bool get isNetworkError { ... }
  bool get isUnauthorized { ... }
  bool get isForbidden { ... }
  bool get isNotFound { ... }
  bool get isValidationError { ... }
  bool get isRateLimited { ... }
  bool get isTimeout { ... }
  bool hasApiErrorCode(String code) { ... }
  T? getResponseField<T>(String key) { ... }
  String get errorCategory { ... }
}
```

---

## New Public Typedefs

```dart
// US1: Custom error body parser
typedef ErrorBodyParserResult = ({
  String? message,
  String? apiErrorCode,
  List<ValidationError> validationErrors,
});

typedef ErrorBodyParser =
    FutureOr<ErrorBodyParserResult?> Function(dynamic body, int statusCode);

// US2: Token refresh
typedef TokenRefreshCallback = Future<String?> Function();
typedef RefreshEndpointPredicate = bool Function(String url);

// US3: Interceptor hooks
typedef RequestHook = FutureOr<RequestOptions> Function(RequestOptions);
typedef ResponseHook = FutureOr<Response<dynamic>> Function(Response<dynamic>);
```

All exported from: `package:app_smart_network/app_smart_network.dart`

---

## Backward Compatibility Matrix

| Symbol | v1.0.3 | v1.1.0 | Notes |
|---|---|---|---|
| `ApiService` | Class | `@deprecated` typedef | Functionally identical; deprecation warning only |
| `AppSmartNetworkService` | — | New class | Canonical entry point |
| `NetworkConfig` | Class | Updated | 5 new optional fields; existing constructor unchanged |
| `ApiException` | Class | Updated | 1 new field `validationErrors`; default `const []` |
| `ValidationError` | — | New class | — |
| `ErrorBodyParser` | — | New typedef | — |
| `TokenRefreshCallback` | — | New typedef | — |
| `RefreshEndpointPredicate` | — | New typedef | — |
| `RequestHook` | — | New typedef | — |
| `ResponseHook` | — | New typedef | — |
| `request()` | Method | Updated | New `deduplicate` param; default `false` |
| All other symbols | Unchanged | Unchanged | — |
