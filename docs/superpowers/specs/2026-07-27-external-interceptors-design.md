# External Interceptors

**Date:** 2026-07-27
**Status:** Approved
**Target release:** 1.1.0

## Problem

`HttpClient._setup()` builds a fixed interceptor chain — retry, debug logger,
`UnAuthInterceptor` — and the `Dio` instance is private to the package. Consumers
cannot inject their own interceptors for token refresh, tracing, analytics, or
request signing without forking the package.

## Goal

Let consumers supply their own `Interceptor` instances at initialization.

## Scope

**In scope**

- A `List<Interceptor> interceptors` field on `NetworkConfig`.
- Splicing those interceptors into the built-in chain at a defined position.
- Exporting the Dio types needed to author an interceptor.
- Tests, README section, CHANGELOG entry, version bump.

**Out of scope**

- Runtime `addInterceptor` / `removeInterceptor` on `ApiService`. Interceptors are
  fixed at `initialize()` time. Revisit only if a real need appears.
- Flags to disable the built-in retry or logger interceptors. Built-ins stay
  always-on.

## Design

### 1. `NetworkConfig.interceptors`

`lib/src/config/network_config.dart` gains a Dio import and one field:

```dart
import 'package:dio/dio.dart';

class NetworkConfig {
  /// Custom interceptors spliced into the built-in chain.
  ///
  /// They run before the retry interceptor, the 401 handler, and the debug
  /// logger, so they can observe a 401 before [onUnauthorized] fires and any
  /// headers they add appear in debug logs.
  final List<Interceptor> interceptors;

  const NetworkConfig({
    required this.baseUrl,
    // ...existing parameters unchanged...
    this.interceptors = const [],
  });
}
```

The empty-list default keeps the constructor `const`-usable and leaves existing
consumers unaffected.

### 2. Chain assembly

`lib/src/client/http_client.dart`, in `_setup()`:

```dart
_dio.interceptors.addAll([
  ...config.interceptors,
  _buildRetryInterceptor(),
  UnAuthInterceptor(onUnauthorized: config.onUnauthorized),
  if (kDebugMode) _buildLoggerInterceptor(),
]);
```

**Revision note:** an earlier draft of this spec placed consumer interceptors
*after* retry, reasoning that "retry re-dispatches through the full chain, so
consumer interceptors see every attempt, not just the first." That's true but
irrelevant to ordering: `dio.fetch()` restarts the whole chain from index 0 on
every attempt regardless of where consumers sit, so `onRequest` is seen on
every attempt either way. The rationale that actually depends on position is
about `onError` under a genuinely retried-and-still-failing request:
`dio_smart_retry` retries by awaiting a nested `dio.fetch()` call and, when
that nested call rejects, re-forwards the *same* terminal `DioException`
object via `handler.next` at each unwind level. An interceptor positioned
*after* retry therefore sees that identical exception replayed once per retry
level (N+1 calls for N retries, all reporting the one final failure) — a
misleading duplicate signal. Positioned *before* retry, each `onError` call
instead corresponds to a genuine, distinct attempt (its own `DioException`
instance). For a non-retryable failure such as a 401 there is only one real
attempt regardless of position, so `onError` fires exactly once either way —
this is the case the "before `UnAuthInterceptor`" rationale below cares about.

Rationale for the position:

- **Before retry** — avoids the duplicate-replay problem described above:
  positioned after retry, a consumer's `onError` would be re-invoked with the
  same terminal exception once per retry level (4 calls for the default 3
  retries) instead of once per genuine attempt.
- **Before `UnAuthInterceptor`** — Dio runs `onError` handlers in registration
  order, so a consumer's token-refresh interceptor can resolve a 401 before
  `onUnauthorized` tears down the session. A 401 is not in
  `defaultRetryableStatuses`, so retry passes it through untouched — the
  consumer sees it before retry has any chance to act on it.
- **Before the logger** — the logger stays last so debug output shows the
  final request after all mutations, regardless of where consumers sit.

The logger positioning is unchanged from the previous draft; only the
consumer/retry order moved. This is noted in the CHANGELOG.

### 3. Barrel exports

`lib/app_smart_network.dart` currently exports only the Dio types needed to make
requests, which is not enough to write an `Interceptor`. Extend the existing
`show` clause:

```dart
export 'package:dio/dio.dart'
    show
        Response,
        Options,
        CancelToken,
        Headers,
        ProgressCallback,
        FormData,
        MultipartFile,
        Interceptor,
        InterceptorsWrapper,
        QueuedInterceptor,
        QueuedInterceptorsWrapper,
        RequestOptions,
        RequestInterceptorHandler,
        ResponseInterceptorHandler,
        ErrorInterceptorHandler,
        DioException;
```

This preserves the package's "no direct `dio` dependency needed" property.

## Testing

Tests construct `HttpClient(NetworkConfig(...))` through a package-internal
import and replace `httpClientAdapter` with a fake that returns canned
responses, so no test touches the network.

| Test | Assertion |
|------|-----------|
| Custom interceptor receives requests | A recording interceptor's `onRequest` fires once per request |
| Header mutation reaches the wire | A header added in `onRequest` is present in the `RequestOptions` seen by the fake adapter |
| Ordering on 401 | The custom interceptor's `onError` runs before `onUnauthorized` is invoked |
| Default is inert | `NetworkConfig` without `interceptors` produces the same chain length and types as before |

Existing tests in `test/app_smart_network_test.dart` must continue to pass
unchanged.

## Errors and edge cases

- An empty `interceptors` list is the default and requires no special handling.
- Duplicate or misbehaving consumer interceptors are the consumer's
  responsibility; the package adds no validation or de-duplication.
- Because interceptors are captured at `initialize()`, calling `initialize()`
  again disposes the old client and rebuilds the chain from the new config —
  the existing behavior, unchanged.

## Documentation and release

- **README** — new "Custom interceptors" section after the `NetworkConfig`
  options table: the `interceptors` parameter row, an ordering note, and a
  worked token-refresh example.
- **CHANGELOG** — 1.1.0 entry covering the new field, the new exports, and the
  logger reordering.
- **pubspec.yaml** — version `1.0.5` → `1.1.0` (additive feature, minor bump).
