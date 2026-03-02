# Data Model: Package Enhancements & Backend-Agnostic Error Handling

**Branch**: `001-package-enhancements` | **Date**: 2026-03-01

---

## New Public Types

### `ValidationError`

**File**: `lib/src/error/exceptions.dart`
**Visibility**: Public (exported)

A typed, immutable value representing a single field-level validation failure
returned by the server (typically in a 422 response).

| Field | Type | Required | Description |
|---|---|---|---|
| `field` | `String` | yes | Name of the form/request field that failed validation |
| `message` | `String` | yes | Human-readable validation error for that field |

**Lifecycle**: Created by `ErrorHandler` (built-in extraction) or by the
consumer-supplied `ErrorBodyParser`. Exposed via `ApiException.validationErrors`.

**Constraints**:
- Immutable (`const` constructor).
- No nested validation errors in this release (richer structures deferred).

---

### `ErrorBodyParserResult`

**File**: `lib/src/config/network_config.dart`
**Visibility**: Public (exported via `NetworkConfig` typedef)

Dart record (named, anonymous record type) returned by a consumer's custom
error parser to supply structured error data.

| Field | Type | Required | Description |
|---|---|---|---|
| `message` | `String?` | no | Extracted human-readable error message |
| `apiErrorCode` | `String?` | no | Server-side error code (e.g. `'UserNotFound'`) |
| `validationErrors` | `List<ValidationError>` | no (default `[]`) | Field-level validation errors |

**Notes**: Returning `null` from the parser (instead of an `ErrorBodyParserResult`)
signals "I don't recognize this format" → package falls back to built-in parsing.
Returning an `ErrorBodyParserResult` with all-null fields overrides with no data
(the package uses locale-translated fallback messages).

---

## New Public Typedefs

### `ErrorBodyParser`

**File**: `lib/src/config/network_config.dart`

```text
FutureOr<ErrorBodyParserResult?> Function(dynamic body, int statusCode)
```

| Parameter | Type | Description |
|---|---|---|
| `body` | `dynamic` | Raw response body as decoded by Dio (Map, List, String, or null) |
| `statusCode` | `int` | HTTP status code of the error response |
| **Returns** | `FutureOr<ErrorBodyParserResult?>` | Structured result, or null to fall back to built-in parsing |

**Invocation conditions**: Called ONLY for server responses with a body (4xx/5xx).
Network-layer errors (offline, timeout, SSL) bypass the parser entirely.

---

### `TokenRefreshCallback`

**File**: `lib/src/config/network_config.dart`

```text
Future<String?> Function()
```

**Returns**: The new Bearer token string on success, or `null` to signal refresh
failure (which triggers `onUnauthorized`).

**Invocation guarantee**: Called at most once per concurrent burst of 401
responses (see R-02 in research.md).

---

### `RefreshEndpointPredicate`

**File**: `lib/src/config/network_config.dart`

```text
bool Function(String url)
```

| Parameter | Type | Description |
|---|---|---|
| `url` | `String` | The resolved URL of the request that received 401 |
| **Returns** | `bool` | `true` if this URL is the refresh endpoint (skip refresh flow) |

**Purpose**: Prevents infinite refresh loops when the refresh endpoint itself
returns 401.

---

### `RequestHook`

**File**: `lib/src/config/network_config.dart`

```text
FutureOr<RequestOptions> Function(RequestOptions options)
```

| Parameter | Type | Description |
|---|---|---|
| `options` | `RequestOptions` | Full Dio request options (headers, path, data, query params) |
| **Returns** | `FutureOr<RequestOptions>` | Optionally modified request options used for the actual request |

**Pipeline**: Multiple hooks are applied in registration order. Each hook
receives the output of the previous hook.

**Skip condition**: Hooks tagged with `extra['_skipHooks'] == true` are skipped
(used internally by `TokenRefreshInterceptor` on the retry request).

---

### `ResponseHook`

**File**: `lib/src/config/network_config.dart`

```text
FutureOr<Response<dynamic>> Function(Response<dynamic> response)
```

| Parameter | Type | Description |
|---|---|---|
| `response` | `Response<dynamic>` | Successful (2xx) Dio response |
| **Returns** | `FutureOr<Response<dynamic>>` | Optionally transformed response data |

**Invocation conditions**: Called ONLY on 2xx responses. Error responses
(4xx/5xx) go directly to `ErrorHandler` and the `ErrorBodyParser`.

---

## Updated Public Types

### `NetworkConfig` (updated)

**File**: `lib/src/config/network_config.dart`

Five new optional fields added. All existing fields unchanged.

| New Field | Type | Default | Description |
|---|---|---|---|
| `errorBodyParser` | `ErrorBodyParser?` | `null` | Custom error-body parser (US1) |
| `tokenRefresher` | `TokenRefreshCallback?` | `null` | Token refresh callback (US2) |
| `refreshEndpointPredicate` | `RefreshEndpointPredicate?` | `null` | Identifies the refresh endpoint (US2) |
| `requestHooks` | `List<RequestHook>` | `const []` | Ordered request interceptor hooks (US3) |
| `responseHooks` | `List<ResponseHook>` | `const []` | Ordered response interceptor hooks (US3) |

**Backward compatibility**: `const NetworkConfig(baseUrl: '...')` continues to
compile and behave identically to v1.0.3 — all new fields have defaults.

---

### `ApiException` (updated)

**File**: `lib/src/error/exceptions.dart`

One new field added. All existing fields, methods, and getters unchanged.

| New Field | Type | Default | Description |
|---|---|---|---|
| `validationErrors` | `List<ValidationError>` | `const []` | Typed field-error list for 422 responses |

**Extraction**: Populated by `ErrorHandler` from the built-in parser (looks for
`errors`, `error.details`, `data.errors` key patterns) or from the consumer's
`ErrorBodyParser` result.

**Null safety**: The field is non-nullable and defaults to an empty list.
Consumers can use `.isEmpty` without null checks.

---

### `AppSmartNetworkService` (renamed from `ApiService`)

**File**: `lib/src/api_service.dart`

The class formerly named `ApiService` is renamed to `AppSmartNetworkService`.
Every method, getter, and static member is identical in signature and behaviour.

`ApiService` is retained as a deprecated typedef:
```dart
@Deprecated('Use AppSmartNetworkService instead. Will be removed in v2.0.0.')
typedef ApiService = AppSmartNetworkService;
```

**Singleton guarantee**: `AppSmartNetworkService._instance` is the single
backing store. `ApiService.instance` and `AppSmartNetworkService.instance`
return the same object.

---

## New Internal Types

### `_DeduplicationEntry` (internal)

**File**: `lib/src/services/request_service.dart`
**Visibility**: Private

Tracks the state of a single in-flight deduplicated request.

| Field | Type | Description |
|---|---|---|
| `completer` | `Completer<Response<dynamic>>` | Gate shared by all callers for this key |
| `waiterCount` | `int` | Number of non-original callers awaiting completion |
| `cancelToken` | `CancelToken` | Token used for the active network request |

**Lifecycle**:
1. Created when the first `deduplicate: true` request for a key is received.
2. `waiterCount` incremented for each subsequent duplicate caller.
3. On success/failure: `completer` is completed; entry removed from map.
4. On original cancellation with `waiterCount > 0`: a new request is issued,
   `completer` is completed with the new result.

---

## Entity Relationships

```text
NetworkConfig
  ├── ErrorBodyParser?           → called by ErrorHandler on 4xx/5xx body
  ├── TokenRefreshCallback?      → called by TokenRefreshInterceptor on 401
  ├── RefreshEndpointPredicate?  → consulted by TokenRefreshInterceptor
  ├── List<RequestHook>          → run by HooksInterceptor (onRequest)
  └── List<ResponseHook>         → run by HooksInterceptor (onResponse, 2xx only)

ErrorHandler
  ├── calls ErrorBodyParser → produces ErrorBodyParserResult
  └── produces ApiException
       └── contains List<ValidationError>

RequestService
  └── Map<String, _DeduplicationEntry>   (in-memory, cleared on completion)

AppSmartNetworkService (canonical)
  └── ApiService (deprecated typedef alias → same class)
```
