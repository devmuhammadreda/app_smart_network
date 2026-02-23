## 1.0.1

### Bug fixes

- **`ApiService.instance`** now throws a `StateError` instead of silently
  creating a broken client when `initialize()` has not been called yet.
- **`ApiService.isInitialized`** getter added — use it to safely check
  whether `initialize()` has been called before accessing `instance`.
- **`withMobileTimeouts`** no longer discards user-supplied `Options` fields.
  It now mutates the existing object in-place, only setting `receiveTimeout`
  when the caller has not already provided one.
- **`removeAppLocale()`** now restores the locale that was active at
  `initialize()` time (from `NetworkConfig.defaultHeaders['Accept-Language']`)
  instead of always falling back to `'en'`.
- **`NetworkLocale.clearCustomTranslations([locale])`** added — removes custom
  translations for a specific locale, or for all locales when called without
  an argument.

---

## 1.0.0

Initial stable release.

### Features

- `ApiService` singleton with `initialize(NetworkConfig)` entry point
- `NetworkConfig` — configure base URL, timeouts, default headers, SSL, and unauthorized callback
- `HttpMethod` enum — `get`, `post`, `put`, `patch`, `delete`
- `RequestService` — unified HTTP request execution with connectivity guard and mobile timeout extension
- `DownloadRequestService` — file download with progress callback
- `UploadRequestService` — multipart file upload with extra fields and progress callback
- `NetworkLocale` — locale-aware error messages; built-in **English** and **Arabic** translations covering all standard HTTP status codes and network error types; extensible via `addTranslations()`
- `setAppLocale(locale)` — sets `Accept-Language` header and switches error-message locale in one call
- `ErrorHandler` — converts `DioException` to `ApiException` with translated messages
- `ApiException` — rich exception with `statusCode`, `apiErrorCode`, `errorCategory`, `hasApiErrorCode()`, and `getResponseField()`
- `ServerFailure` / `CacheFailure` — domain-layer `Failure` wrappers (Equatable)
- Automatic retry on idempotent methods (GET, PUT, DELETE) with exponential back-off (3 retries: 1 s, 2 s, 3 s)
- Connectivity check before every request with a single 600 ms retry for transient states
- Background JSON decoding via `compute` isolate
- Debug request/response logging via `PrettyDioLogger` (debug builds only)
- Per-request `baseUrl` override, cancel token, query parameters, and send/receive progress callbacks
- `example/` app demonstrating all features against JSONPlaceholder API
