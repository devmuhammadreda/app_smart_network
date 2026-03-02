# Research: Package Enhancements & Backend-Agnostic Error Handling

**Branch**: `001-package-enhancements` | **Date**: 2026-03-01

---

## R-01: Async Error Body Parser Integration

**Question**: How should an `async`-capable consumer parser integrate with the
synchronous `ErrorHandler._handleStatusCodeError()` path?

**Decision**: Change `ErrorHandler.handleError()` to return `Future<Exception>`
and make `_handleStatusCodeError` async. The call site in `RequestService`
already `await`s the result through the interceptor chain, so making the error
handler async has zero observable impact on callers.

**Implementation**:
```dart
// FutureOr<ErrorBodyParserResult?> allows both sync and async parsers
// without forcing an extra Future microtask on sync parsers.
final parserResult = await Future.value(config.errorBodyParser?.call(body, statusCode));
```

**Rationale**: `FutureOr<T>` is the idiomatic Dart pattern for callbacks that
may be sync or async. `Future.value()` promotes a sync result to a resolved
Future with no overhead, while an async parser is awaited normally.

**Alternatives considered**:
- Require parsers to be sync-only → rejected; async parsers are valid (e.g.,
  reading from secure storage to resolve an error code mapping).
- Separate sync and async parser registrations → rejected; unnecessarily
  complex API surface.

---

## R-02: Concurrent-401 Serialization Pattern

**Question**: When multiple in-flight requests all receive 401 simultaneously,
how do we ensure the token-refresh callback is called exactly once?

**Decision**: Use a boolean flag `_isRefreshing` + a `Completer<String?>`
(`_refreshCompleter`) in `TokenRefreshInterceptor`. The first 401 to arrive
sets `_isRefreshing = true` and starts the refresh. Subsequent 401s await
`_refreshCompleter.future`. After refresh (success or failure), the flag is
reset and the Completer is replaced.

**Implementation sketch**:
```dart
bool _isRefreshing = false;
Completer<String?>? _refreshCompleter;

@override
Future<void> onError(DioException err, ErrorInterceptorHandler handler) async {
  if (err.response?.statusCode != 401) { handler.next(err); return; }
  if (_isRefreshEndpoint(err.requestOptions.path)) { handler.next(err); return; }

  if (_isRefreshing) {
    // Wait for the in-progress refresh then retry
    final newToken = await _refreshCompleter!.future;
    if (newToken != null) {
      // retry with newToken
    } else {
      handler.next(err);
    }
    return;
  }

  _isRefreshing = true;
  _refreshCompleter = Completer<String?>();
  try {
    final newToken = await config.tokenRefresher!();
    _refreshCompleter!.complete(newToken);
    // retry original request with newToken
  } catch (_) {
    _refreshCompleter!.complete(null);
    config.onUnauthorized?.call();
    handler.next(err);
  } finally {
    _isRefreshing = false;
    _refreshCompleter = null;
  }
}
```

**Rationale**: This is the standard "refresh-once, queue-the-rest" pattern used
by production libraries (dio_options_refresh_interceptor, chopper). The
Completer acts as a broadcast gate: all waiters receive the same token value
when the refresh completes.

**Alternatives considered**:
- Mutex / Lock package → rejected; no new dependencies permitted; `Completer`
  achieves the same result natively.
- Retry via `dio_smart_retry` 401-include → rejected by clarification (Q1 of
  session 2026-03-01): retry interceptor MUST exclude 401.

---

## R-03: Request Retry Without Re-running Hooks (FR-025)

**Question**: When `TokenRefreshInterceptor` retries the original request, how
do we prevent `HooksInterceptor` from running the request hooks again?

**Decision**: Tag the retry request with a sentinel in `RequestOptions.extra`:
```dart
final retryOptions = requestOptions.copyWith(
  headers: {...requestOptions.headers, 'Authorization': 'Bearer $newToken'},
  extra: {...requestOptions.extra, '_skipHooks': true},
);
```
`HooksInterceptor.onRequest` checks for this flag and passes through immediately
if present.

**Rationale**: `RequestOptions.extra` is the standard Dio mechanism for passing
metadata through the interceptor chain without modifying the public API. The
sentinel key is prefixed with `_` to signal it is an internal implementation
detail.

**Alternatives considered**:
- Separate Dio instance for retries → rejected; complex and unnecessary.
- A static flag on the interceptor → rejected; not thread-safe in a multi-
  isolate context and harder to test.

---

## R-04: Deduplication Key Design

**Question**: How do we compute a stable deduplication key from method, URL,
query parameters, and headers?

**Decision**: Concatenate sorted string representations and take `hashCode`:
```dart
String _buildKey(String method, String url,
    Map<String, dynamic>? query, Map<String, dynamic>? headers) {
  final q = (query?.entries.toList()..sort((a, b) => a.key.compareTo(b.key)))
      ?.map((e) => '${e.key}=${e.value}')
      .join('&') ?? '';
  final h = (headers?.entries.toList()..sort((a, b) => a.key.compareTo(b.key)))
      ?.map((e) => '${e.key}:${e.value}')
      .join(',') ?? '';
  return '$method|$url|$q|$h';
}
```
The key is a plain `String` used as the `Map` lookup key — no hashing needed
since Dart `Map<String, …>` uses `==` on keys.

**Rationale**: Sorting ensures `{a: 1, b: 2}` and `{b: 2, a: 1}` produce the
same key. The pipe `|` separator avoids accidental collisions between adjacent
segments. String equality is O(n) on key length; for typical request keys
(<500 chars) this is negligible.

**Alternatives considered**:
- `MD5` / `SHA-1` hash → rejected; introduces crypto dependency or `dart:crypto`
  which is unavailable on all Flutter targets. String key is simpler and correct.
- Exclude headers from key → rejected by clarification (Q3 of session
  2026-03-01).

---

## R-05: Original-Request Cancellation with Waiting Callers (FR-030)

**Question**: When the in-flight deduplicated request is cancelled but waiters
remain, how do we "promote" a new request?

**Decision**: Introduce a `_DeduplicationEntry` internal class that tracks:
- `Completer<Response<dynamic>>` — shared result gate
- `int waiterCount` — number of callers awaiting this key (including original)

When the original's `CancelToken` fires a cancellation:
1. Catch `ApiException` with `errorType == 'RequestCancelled'`.
2. If `entry.waiterCount > 0`: create a new `CancelToken` and re-issue the
   request via `_doRequest()`. Complete `entry.completer` with the new result.
3. If `entry.waiterCount == 0`: complete with the cancellation error.

**Rationale**: This gives waiters transparent promotion without requiring them
to handle cancellation themselves, satisfying FR-030 and US4 Scenario 3.

---

## R-06: `AppSmartNetworkService` — Deprecated Typedef Alias

**Question**: What is the cleanest way to introduce `AppSmartNetworkService`
while preserving `ApiService` as a deprecated alias with no code duplication?

**Decision**: Rename the class inside `api_service.dart` to
`AppSmartNetworkService`, then add:
```dart
@Deprecated(
  'Use AppSmartNetworkService instead. '
  'ApiService will be removed in v2.0.0.',
)
typedef ApiService = AppSmartNetworkService;
```
Both names are exported from `app_smart_network.dart`.

**Rationale**: A Dart `typedef` for a class alias produces zero runtime
overhead. The deprecation annotation surfaces at every call site in consuming
code (IDE warning + `dart analyze` warning). The single-source-of-truth class
is `AppSmartNetworkService`; `ApiService` is 100% derived from it.

**Alternatives considered**:
- Subclass or `extends` → rejected; two classes, two singletons, state
  divergence risk, violates FR-028.
- Keep `ApiService` as primary, add `AppSmartNetworkService` subclass → same
  problem.
- Two separate files → unnecessary; typedef handles it in one file.

---

## R-07: Interceptor Ordering

**Question**: In what order should the new interceptors be registered with Dio
to satisfy FR-024 (retry excludes 401) and FR-025 (hooks don't re-run on
token-refresh retry)?

**Decision** (Dio interceptor call order: onRequest FIFO, onError LIFO):

| Position | Interceptor | Role |
|---|---|---|
| 1st added | `HooksInterceptor` | Request hooks run first; response hooks run first on 2xx |
| 2nd added | `RetryInterceptor` | Retries non-401 errors; 401 excluded from retryable set |
| 3rd added | `PrettyDioLogger` | Debug logging (debug builds only) |
| 4th added | `TokenRefreshInterceptor` | onError called FIRST (LIFO) — intercepts 401 before retry sees it |

Because `onError` is LIFO, `TokenRefreshInterceptor` (added last) handles 401
before `RetryInterceptor` (added earlier) can see it. This naturally implements
FR-024 without any special configuration of `dio_smart_retry`.

**Rationale**: The LIFO error ordering of Dio interceptors is the standard
mechanism used by all Dio-based auth libraries. This approach requires no
modification to `RetryInterceptor`'s retry conditions — 401 simply never
reaches it.
