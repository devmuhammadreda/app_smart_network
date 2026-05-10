# Remove Connectivity Precheck

**Date:** 2026-05-10
**Version target:** 1.1.0 (breaking)

## Problem

When the iOS simulator's host machine sits idle for a few minutes (Mac sleeps / power-naps), `connectivity_plus`'s `Connectivity().checkConnectivity()` reports `[ConnectivityResult.none]` for a window after activity resumes — even though the network is actually reachable. The same transient state has been reported on real iOS devices when the system network stack is suspended.

`NetworkServiceMixin.ensureConnected()` runs before every API call and throws an `ApiException(NoInternetConnection)` when it sees `none`. A single 600 ms retry isn't enough to clear the transient state, so users see a false "No internet connection" error for requests that would have succeeded if sent.

## Decision

Remove the connectivity precheck entirely. Trust Dio to report real network failures, and rely on the existing `ErrorHandler` to map them to a `NoInternetConnection` `ApiException`. Side benefits: less code, no false negatives, and `connectivity_plus` is no longer a dependency.

## Scope

### Files changed

1. **`lib/src/mixins/network_service_mixin.dart`**
   - Remove `Connectivity get connectivity` requirement
   - Remove `ensureConnected()`
   - Remove `withMobileTimeouts()` (callers will pass `Options.receiveTimeout` themselves if they need a longer timeout)
   - Drop `connectivity_plus` import
   - Keep `handleProgress()` and `resolveUrl()`

2. **`lib/src/services/request_service.dart`**
   - Remove `connectivity_plus` import
   - Remove `final Connectivity connectivity` field and `{Connectivity? connectivity}` constructor parameter
   - Remove `await ensureConnected()` and `withMobileTimeouts(...)` calls inside `execute()`; pass `options` to Dio directly and use `resolveUrl(path, baseUrl)` as before

3. **`lib/src/services/upload_service.dart`** — same shape of changes as `request_service.dart`

4. **`lib/src/services/download_service.dart`** — same shape of changes as `request_service.dart`

5. **`lib/src/error/error_handler.dart`**
   - Change `DioExceptionType.connectionError` mapping from `errorType: 'ConnectionError'` to `errorType: 'NoInternetConnection'` with the `NoInternetConnection` localized message. Rationale: when the gate is gone, this case is the primary "device offline" signal users will see, and we want to preserve the prior user-facing message.
   - `DioExceptionType.unknown` + `SocketException` already maps to `NoInternetConnection` — leave as-is.

6. **`pubspec.yaml`**
   - Remove `connectivity_plus: ^7.0.0` from `dependencies`
   - Bump `version: 1.0.3` → `version: 1.1.0`

7. **`test/`**
   - Delete tests that mock `Connectivity` and assert `ensureConnected()` throws `NoInternetConnection`
   - Delete tests for `withMobileTimeouts()`
   - Add a test that simulates `DioException(type: connectionError)` and asserts `ErrorHandler.handleError` returns `ApiException` with `errorType: 'NoInternetConnection'`
   - Keep / update the existing `unknown + SocketException` → `NoInternetConnection` test

8. **`CHANGELOG.md`**
   - Add `## 1.1.0` section describing the removal as a breaking change, with a migration note (callers no longer pass `Connectivity` to service constructors; `connectivity_plus` is no longer a transitive dependency)

9. **`README.md`** — remove any mention of the connectivity precheck / `Connectivity` injection if present

10. **`example/`** — update if it references the removed parameters

### Files NOT changed

- `lib/src/client/http_client.dart`
- `lib/src/interceptors/unauth_interceptor.dart`
- `lib/src/config/network_config.dart`
- `lib/src/i18n/network_locale.dart` (the `NoInternetConnection` key is still used by `ErrorHandler`)
- `lib/src/error/exceptions.dart`

## Behavior

### Before
1. Caller invokes `requestService.execute(...)`
2. `ensureConnected()` calls `connectivity_plus`; if `none`, retry once after 600 ms
3. If still `none`, throw `ApiException(NoInternetConnection)` — request never sent
4. Otherwise send request via Dio; Dio errors flow through `ErrorHandler`

### After
1. Caller invokes `requestService.execute(...)`
2. Send request via Dio immediately (with `dio_smart_retry` already wired in `HttpClient`)
3. If the device is genuinely offline, Dio throws `DioException(type: connectionError)` (or `unknown` wrapping `SocketException`); `ErrorHandler` maps both to `ApiException(errorType: 'NoInternetConnection')`
4. Caller sees the same `NoInternetConnection` error message as before

## Migration (1.0.x → 1.1.0)

For consumers:
- Remove any `connectivity:` argument passed to `RequestService`, `UploadRequestService`, or `DownloadRequestService` constructors. The constructors now take only the `HttpClient`.
- If you relied on `withMobileTimeouts` extending `receiveTimeout` automatically on mobile networks, set `Options(receiveTimeout: Duration(seconds: 30))` on the call site instead.
- `connectivity_plus` is no longer a transitive dep — add it to your own `pubspec.yaml` if you use it directly.

## Risks

- **False positives moved, not eliminated**: a real offline state still produces a `NoInternetConnection` exception, just from `ErrorHandler` instead of the precheck. Net change for end users on a real offline device: roughly one Dio timeout's worth of latency before the same error message appears. Acceptable.
- **Breaking API**: bumping to `1.1.0` and a CHANGELOG migration note covers it.

## Out of scope

- Adding a reachability probe (was Option B in brainstorming)
- Adding an opt-in `enableConnectivityPrecheck` config (was Option C)
- Re-implementing mobile-aware timeouts in `NetworkConfig`
