## 1.3.0

### Features

- **Certificate pinning** — `NetworkConfig` accepts an optional
  `certificatePinning: CertificatePinningConfig(...)`. Pins are the base64
  SHA-256 of a certificate's `SubjectPublicKeyInfo` in the conventional
  `sha256/<base64>` form shared with HPKP and OkHttp's `CertificatePinner`.
  Hashing the SPKI rather than the whole certificate means a pin survives
  certificate renewal whenever the key pair is reused.
- **Per-host configuration** — `pins` maps a host to its accepted pins;
  `includeSubdomains` extends a host's pins to its subdomains; `enforce: false`
  reports mismatches without blocking them, for a staged rollout.
- **`onPinFailure` callback** — reports the host and the pins the server
  actually presented, for telemetry.
- **`CertificatePinningException`** — a pin failure is distinguishable from a
  generic network error. It extends `ApiException`, so existing handlers keep
  working, and carries the offending `host`. Messages are locale-aware in
  English and Arabic; the presented pins are never placed in the message.
- **New public exports** — `CertificatePinningConfig`,
  `CertificatePinningException`, `OnPinFailureCallback`,
  `kMinimumPinsPerHost`.

### Fixes

- **Certificate failures are no longer retried.** `DioExceptionType.badCertificate`
  was previously treated as a retryable transport error, so a rejected TLS
  handshake was replayed up to the configured attempt count. Replaying it
  re-presents the same certificate to the same host for the same verdict, and
  multiplied a security signal that should be raised once. This applies to all
  certificate failures, pinned or not.

### Changes

- Pinning is **off by default**; `certificatePinning` defaults to `null` and the
  package behaves exactly as it did in 1.2.0 when it is not set. `const
  NetworkConfig(...)` call sites continue to compile.
- Only hosts listed in `pins` are pinned. Unlisted hosts — analytics, crash
  reporting, CDNs — fall through to normal TLS validation rather than failing
  closed.
- New dependencies: `asn1lib` (certificate parsing) and `crypto` (SHA-256).

### Notes

- **Every host needs at least two distinct pins.** A single pin means a lost or
  rotated key bricks every installed app with no recovery path, so fewer than
  two throws `ArgumentError` at startup. Keep the second key offline.
- Pin format, pin count, and blank hosts are validated when
  `CertificatePinningConfig` is constructed, so a typo fails at startup rather
  than on the first API call in production.
- `allowBadCertificate: true` combined with `certificatePinning` throws
  `ArgumentError` when the client is built. The check lives there rather than in
  `NetworkConfig`'s `const` constructor because a `const` constructor can only
  `assert`, and asserts are stripped from release builds — exactly where an app
  that looks pinned but is not would do the damage.
- Pinning uses Dio's `validateCertificate`, which evaluates the leaf certificate
  on every connection, rather than `badCertificateCallback`, which fires only
  after chain validation has already failed.
- Malformed or unparseable certificates are rejected, never treated as a pass.

## 1.2.0

### Features

- **Configurable retry** — `NetworkConfig` now accepts a `retry` policy.
  `RetryPolicy` exposes `attempts`, `delays`, `methods` and `statuses`, all of
  which were previously hardcoded. Pass `retry: null` to disable retry app-wide.
- **Per-request retry** — `request()`, `download()` and `uploadFile()` take a
  `retry:` argument that overrides the app-wide policy for a single call. Use
  `RetryPolicy.off` to opt one request out, or a policy with a higher
  `attempts` to opt one in.
- **New public export** — `RetryPolicy`.

### Changes

- Retry defaults are unchanged: three retries on idempotent methods with a
  1 s / 2 s / 3 s backoff. Code that does not mention `retry` behaves exactly
  as it did in 1.1.0.

### Notes

- `RetryPolicy.delays` and `RetryPolicy.methods` are read from the app-wide
  policy only. Backoff is fixed when the client is built and cannot vary per
  request; the method allowlist guards calls that did not supply a policy, so a
  policy attached to a request bypasses it — that is what makes
  `retry: RetryPolicy(attempts: 5)` retry a POST.
- `attempts` is capped at `RetryPolicy.maxAttempts` (10), asserted at
  construction.

---

## 1.1.0

### Features

- **Custom interceptors** — `NetworkConfig` now accepts an `interceptors` list.
  They are registered **before** the built-in retry interceptor, the 401
  handler, and the debug logger. A custom interceptor can therefore handle a
  401 before `onUnauthorized` fires, and its `onError` fires once per genuine
  attempt on a retried request instead of receiving a duplicate replay of the
  same terminal failure (which is what happens to interceptors positioned
  after retry).
- **New public exports** — `Interceptor`, `InterceptorsWrapper`,
  `QueuedInterceptor`, `QueuedInterceptorsWrapper`, `RequestOptions`,
  `RequestInterceptorHandler`, `ResponseInterceptorHandler`,
  `ErrorInterceptorHandler`, `DioException`, `DioExceptionType` and
  `ResponseType` are re-exported, so writing most interceptors no longer
  requires a direct `dio` dependency.

### Changes

- The debug logger interceptor moved to the end of the interceptor chain. Debug
  output now reflects the final request after every interceptor has run.
  Debug builds only — no effect on release builds.

---

## 1.0.5

### Bug fixes

- **`ErrorHandler`** — `DioExceptionType.transformTimeout` now returns a proper
  localized message (`TransformTimeout`) with status `408`, instead of leaking
  the raw `'transformTimeout'` key as the user-facing message.

### Maintenance

- **`equatable` dependency removed** from `pubspec.yaml`. It was left behind
  after the `Failure` classes were deleted in 1.0.3 and is no longer used.
- Removed the unused `ConnectionError` locale key (both `en` and `ar`);
  `connectionError` maps to `NoInternetConnection`, so the key was dead.

---

## 1.0.4

### Bug fixes

- **`ErrorHandler`** now maps `DioExceptionType.connectionError` to the
  `NoInternetConnection` error type, so connection failures surface the correct
  localized "no internet connection" message instead of a generic error.

### Maintenance

- Dependencies upgraded (`dart pub upgrade`).

---

## 1.0.3

### Breaking changes

- **`ServerFailure` and `CacheFailure` removed** — `failures.dart` and its
  public exports have been deleted. The `Failure` abstraction was out of scope
  for a network package; it leaked domain-layer concerns into the library and
  forced an unnecessary `equatable` dependency on consumers.
  - **Migration**: catch `ApiException` directly in your repository layer, or
    define your own `Failure` types and map from `ApiException` there.

    ```dart
    // before
    } on ApiException catch (e) {
      return Left(ServerFailure.fromException(e));
    }

    // after – option A: catch ApiException directly
    } on ApiException catch (e) {
      return Left(MyServerFailure(e.message, e.statusCode));
    }
    ```

- **`equatable` dependency removed** — the package no longer depends on
  `equatable`. Remove it from your own `pubspec.yaml` if you were relying on
  the transitive export.

---

## 1.0.2

### Bug fixes

- **`ErrorHandler.handleError`** now passes an `ApiException` through unchanged
  instead of re-wrapping it as a generic `'UnexpectedError'` (status 0). This
  prevented the real error type, status code, and message from reaching callers
  whenever an `ApiException` entered the catch block (e.g. thrown by a custom
  interceptor).
- **`RequestService.execute`** — `ensureConnected()`, `withMobileTimeouts()`,
  and `resolveUrl()` are now inside the single `try/catch` block, so every
  error type (connectivity, timeout, bad response, certificate, cancel) flows
  through `ErrorHandler` via one consistent code path.

---

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
