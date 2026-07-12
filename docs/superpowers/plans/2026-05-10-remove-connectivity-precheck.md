# Remove Connectivity Precheck Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove the `connectivity_plus`-based precheck that produces false "No internet connection" errors when the iOS simulator's host machine wakes from idle. Trust Dio's own error reporting and rely on `ErrorHandler` to map `connectionError` to a `NoInternetConnection` `ApiException`.

**Architecture:** Three service classes (`RequestService`, `UploadRequestService`, `DownloadRequestService`) currently call `ensureConnected()` and `withMobileTimeouts()` from `NetworkServiceMixin` before every Dio call. We delete those mixin methods, drop the `Connectivity` field/parameter from each service, remove the `connectivity_plus` dependency, and update `ErrorHandler` so `DioExceptionType.connectionError` reports `NoInternetConnection` (preserving the prior user-visible error message). Bump to `1.1.0` (breaking) and update CHANGELOG / README / library docstrings.

**Tech Stack:** Dart, Flutter, Dio 5, dio_smart_retry, flutter_test.

**Spec:** `docs/superpowers/specs/2026-05-10-remove-connectivity-precheck-design.md`

---

## File Structure

**Modified:**
- `lib/src/mixins/network_service_mixin.dart` — drop `ensureConnected`, `withMobileTimeouts`, `connectivity` getter; keep `handleProgress`, `resolveUrl`
- `lib/src/services/request_service.dart` — drop `Connectivity` field/param and precheck call
- `lib/src/services/upload_service.dart` — same shape
- `lib/src/services/download_service.dart` — same shape
- `lib/src/error/error_handler.dart` — map `DioExceptionType.connectionError` to `NoInternetConnection`
- `lib/app_smart_network.dart` — update library docstring
- `pubspec.yaml` — remove `connectivity_plus`, bump to `1.1.0`
- `test/app_smart_network_test.dart` — add `ErrorHandler` test for `connectionError` → `NoInternetConnection`
- `CHANGELOG.md` — add `1.1.0` section
- `README.md` — remove "Connectivity guard" and "Mobile timeout" feature lines and the `connectivity_plus` dependency row

**Not modified:**
- `lib/src/client/http_client.dart`
- `lib/src/interceptors/unauth_interceptor.dart`
- `lib/src/config/network_config.dart`
- `lib/src/i18n/network_locale.dart`
- `lib/src/error/exceptions.dart`
- `lib/src/api_service.dart` (no docstring lines reference the removed features)
- `example/` source code (no direct `Connectivity` usage there; lockfile regenerates on `flutter pub get`)

---

## Task 1: Update `ErrorHandler` so `connectionError` reports `NoInternetConnection`

**Files:**
- Modify: `lib/src/error/error_handler.dart:65-71`
- Modify: `test/app_smart_network_test.dart` (add new group at end of `main()`)

- [ ] **Step 1: Write the failing test**

Add these imports at the top of `test/app_smart_network_test.dart`, alongside the existing imports:

```dart
import 'dart:io';

import 'package:dio/dio.dart';
```

Add this group at the end of `main()` in `test/app_smart_network_test.dart`, before the closing `}`:

```dart
  // ── ErrorHandler ───────────────────────────────────────────────────────────

  group('ErrorHandler', () {
    setUp(() {
      NetworkLocale.setLocale('en');
      NetworkLocale.clearCustomTranslations();
    });

    test('maps DioExceptionType.connectionError to NoInternetConnection', () {
      final dioError = DioException(
        requestOptions: RequestOptions(path: '/x'),
        type: DioExceptionType.connectionError,
        error: 'connection refused',
      );

      final result = ErrorHandler.handleError(dioError);

      expect(result, isA<ApiException>());
      final api = result as ApiException;
      expect(api.errorType, 'NoInternetConnection');
      expect(api.message, 'No internet connection.');
      expect(api.statusCode, 0);
    });

    test('maps DioExceptionType.unknown + SocketException to NoInternetConnection', () {
      final dioError = DioException(
        requestOptions: RequestOptions(path: '/x'),
        type: DioExceptionType.unknown,
        error: const SocketException('Network is unreachable'),
      );

      final result = ErrorHandler.handleError(dioError);

      expect(result, isA<ApiException>());
      expect((result as ApiException).errorType, 'NoInternetConnection');
    });
  });
```

- [ ] **Step 2: Run test to verify the new `connectionError` test fails**

Run:
```bash
flutter test test/app_smart_network_test.dart --plain-name "maps DioExceptionType.connectionError to NoInternetConnection"
```
Expected: FAIL — `errorType` is currently `'ConnectionError'`, not `'NoInternetConnection'`.

- [ ] **Step 3: Update `ErrorHandler`**

In `lib/src/error/error_handler.dart`, replace the `case DioExceptionType.connectionError:` block (lines 65–71) with:

```dart
      case DioExceptionType.connectionError:
        return ApiException(
          NetworkLocale.getErrorMessage('NoInternetConnection'),
          0,
          errorType: 'NoInternetConnection',
          originalError: error,
        );
```

- [ ] **Step 4: Run the new ErrorHandler tests**

Run:
```bash
flutter test test/app_smart_network_test.dart --plain-name "ErrorHandler"
```
Expected: PASS for both `connectionError` and `unknown + SocketException` tests.

- [ ] **Step 5: Run full test suite**

Run:
```bash
flutter test
```
Expected: all tests pass.

- [ ] **Step 6: Commit**

```bash
git add lib/src/error/error_handler.dart test/app_smart_network_test.dart
git commit -m "fix: map DioExceptionType.connectionError to NoInternetConnection"
```

---

## Task 2: Strip precheck and mobile-timeout from `NetworkServiceMixin`

**Files:**
- Modify: `lib/src/mixins/network_service_mixin.dart` (replace whole file)

- [ ] **Step 1: Replace the mixin file**

Overwrite `lib/src/mixins/network_service_mixin.dart` with:

```dart
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

// ============================================================================
// NETWORK SERVICE MIXIN
// ============================================================================

mixin NetworkServiceMixin {
  /// Forwards download/upload progress to [callback] and logs it.
  void handleProgress(int current, int total, ProgressCallback? callback) {
    if (callback != null && total != -1) {
      callback(current, total);
      final pct = (current / total * 100).toStringAsFixed(0);
      debugPrint('[$runtimeType] progress: $pct%');
    }
  }

  /// Resolves the full URL. When [baseUrl] is non-null it is prepended to
  /// [path] and used as-is, bypassing Dio's own baseUrl.
  String resolveUrl(String path, String? baseUrl) =>
      baseUrl != null ? '$baseUrl$path' : path;
}
```

(Note: do not run analyzer or commit yet — callers will be broken until Tasks 3–5 land.)

---

## Task 3: Strip `Connectivity` and precheck from `RequestService`

**Files:**
- Modify: `lib/src/services/request_service.dart` (replace whole file)

- [ ] **Step 1: Replace the file**

Overwrite `lib/src/services/request_service.dart` with:

```dart
import 'package:dio/dio.dart';

import '../client/http_client.dart';
import '../error/error_handler.dart';
import '../mixins/network_service_mixin.dart';

/// Available HTTP methods.
enum HttpMethod { get, post, put, patch, delete }

// ============================================================================
// REQUEST SERVICE
// ============================================================================

class RequestService with NetworkServiceMixin {
  final HttpClient _client;

  RequestService(this._client);

  Future<Response<T>> execute<T>(
    HttpMethod method,
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
    String? baseUrl,
  }) async {
    try {
      final url = resolveUrl(path, baseUrl);

      switch (method) {
        case HttpMethod.get:
          return await _client.dio.get<T>(
            url,
            queryParameters: queryParameters,
            options: options,
            cancelToken: cancelToken,
            onReceiveProgress: (r, t) => handleProgress(r, t, onReceiveProgress),
          );
        case HttpMethod.post:
          return await _client.dio.post<T>(
            url,
            data: data,
            queryParameters: queryParameters,
            options: options,
            cancelToken: cancelToken,
            onSendProgress: (s, t) => handleProgress(s, t, onSendProgress),
            onReceiveProgress: (r, t) => handleProgress(r, t, onReceiveProgress),
          );
        case HttpMethod.put:
          return await _client.dio.put<T>(
            url,
            data: data,
            queryParameters: queryParameters,
            options: options,
            cancelToken: cancelToken,
            onSendProgress: (s, t) => handleProgress(s, t, onSendProgress),
            onReceiveProgress: (r, t) => handleProgress(r, t, onReceiveProgress),
          );
        case HttpMethod.patch:
          return await _client.dio.patch<T>(
            url,
            data: data,
            queryParameters: queryParameters,
            options: options,
            cancelToken: cancelToken,
            onSendProgress: (s, t) => handleProgress(s, t, onSendProgress),
            onReceiveProgress: (r, t) => handleProgress(r, t, onReceiveProgress),
          );
        case HttpMethod.delete:
          return await _client.dio.delete<T>(
            url,
            data: data,
            queryParameters: queryParameters,
            options: options,
            cancelToken: cancelToken,
          );
      }
    } catch (e) {
      throw ErrorHandler.handleError(e);
    }
  }
}
```

---

## Task 4: Strip `Connectivity` and precheck from `UploadRequestService`

**Files:**
- Modify: `lib/src/services/upload_service.dart` (replace whole file)

- [ ] **Step 1: Replace the file**

Overwrite `lib/src/services/upload_service.dart` with:

```dart
import 'dart:io';

import 'package:dio/dio.dart';

import '../client/http_client.dart';
import '../error/error_handler.dart';
import '../mixins/network_service_mixin.dart';

// ============================================================================
// UPLOAD SERVICE
// ============================================================================

class UploadRequestService with NetworkServiceMixin {
  final HttpClient _client;

  UploadRequestService(this._client);

  Future<Response<T>> execute<T>(
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
  }) async {
    final url = resolveUrl(path, baseUrl);

    try {
      final formData = FormData();

      formData.files.add(
        MapEntry(
          fieldName,
          await MultipartFile.fromFile(
            file.path,
            filename: fileName ?? file.path.split('/').last,
          ),
        ),
      );

      data?.forEach(
        (key, value) => formData.fields.add(MapEntry(key, value.toString())),
      );

      return await _client.dio.post<T>(
        url,
        data: formData,
        queryParameters: queryParameters,
        options: options,
        cancelToken: cancelToken,
        onSendProgress: (s, t) => handleProgress(s, t, onSendProgress),
      );
    } catch (e) {
      throw ErrorHandler.handleError(e);
    }
  }
}
```

---

## Task 5: Strip `Connectivity` and precheck from `DownloadRequestService`

**Files:**
- Modify: `lib/src/services/download_service.dart` (replace whole file)

- [ ] **Step 1: Replace the file**

Overwrite `lib/src/services/download_service.dart` with:

```dart
import 'package:dio/dio.dart';

import '../client/http_client.dart';
import '../error/error_handler.dart';
import '../mixins/network_service_mixin.dart';

// ============================================================================
// DOWNLOAD SERVICE
// ============================================================================

class DownloadRequestService with NetworkServiceMixin {
  final HttpClient _client;

  DownloadRequestService(this._client);

  Future<Response> execute(
    String urlPath,
    String savePath, {
    ProgressCallback? onReceiveProgress,
    Map<String, dynamic>? queryParameters,
    CancelToken? cancelToken,
    bool deleteOnError = true,
    String lengthHeader = Headers.contentLengthHeader,
    Options? options,
    String? baseUrl,
  }) async {
    final url = resolveUrl(urlPath, baseUrl);

    try {
      return await _client.dio.download(
        url,
        savePath,
        onReceiveProgress: (r, t) => handleProgress(r, t, onReceiveProgress),
        queryParameters: queryParameters,
        cancelToken: cancelToken,
        deleteOnError: deleteOnError,
        lengthHeader: lengthHeader,
        options: options,
      );
    } catch (e) {
      throw ErrorHandler.handleError(e);
    }
  }
}
```

---

## Task 6: Drop `connectivity_plus` and bump version

**Files:**
- Modify: `pubspec.yaml`

- [ ] **Step 1: Edit `pubspec.yaml`**

Remove the line `  connectivity_plus: ^7.0.0` from `dependencies:`.

Change `version: 1.0.3` to `version: 1.1.0`.

The `dependencies:` block should now read:

```yaml
dependencies:
  flutter:
    sdk: flutter
  dio: ^5.9.1
  equatable: ^2.0.8
  pretty_dio_logger: ^1.4.0
  dio_smart_retry: ^7.0.1
```

(Note: `equatable` is currently listed; leave it as-is — its removal is unrelated to this plan.)

- [ ] **Step 2: Refresh package resolution**

Run:
```bash
flutter pub get
```
Expected: success.

- [ ] **Step 3: Run analyzer for the whole package**

Run:
```bash
flutter analyze
```
Expected: 0 issues. If any remain in `lib/`, fix the residual `connectivity_plus` import or `Connectivity` reference before continuing.

- [ ] **Step 4: Run full test suite**

Run:
```bash
flutter test
```
Expected: all tests pass.

- [ ] **Step 5: Commit Tasks 2–6 together**

```bash
git add lib/src/mixins/network_service_mixin.dart \
        lib/src/services/request_service.dart \
        lib/src/services/upload_service.dart \
        lib/src/services/download_service.dart \
        pubspec.yaml pubspec.lock
git commit -m "feat!: remove connectivity precheck and connectivity_plus dependency

BREAKING CHANGE: RequestService, UploadRequestService, and DownloadRequestService
no longer accept a Connectivity argument; ensureConnected() and withMobileTimeouts()
have been removed from NetworkServiceMixin. connectivity_plus is no longer a
dependency. Real offline state is now reported by Dio and mapped to
NoInternetConnection by ErrorHandler."
```

---

## Task 7: Update library docstring

**Files:**
- Modify: `lib/app_smart_network.dart:1-7`

- [ ] **Step 1: Update the library docstring**

In `lib/app_smart_network.dart`, replace lines 1–7:

```dart
/// A smart Flutter network package built on [Dio] with:
/// - Automatic retry (idempotent methods only)
/// - Connectivity check before every request
/// - Extended receive-timeout on mobile networks
/// - Built-in locale-aware error messages (English & Arabic)
/// - Isolated upload / download services
library;
```

with:

```dart
/// A smart Flutter network package built on [Dio] with:
/// - Automatic retry (idempotent methods only)
/// - Built-in locale-aware error messages (English & Arabic)
/// - Isolated upload / download services
library;
```

- [ ] **Step 2: Verify analyzer is clean**

Run:
```bash
flutter analyze lib/app_smart_network.dart
```
Expected: 0 issues.

- [ ] **Step 3: Commit**

```bash
git add lib/app_smart_network.dart
git commit -m "docs: drop connectivity-precheck and mobile-timeout from library docstring"
```

---

## Task 8: Update README

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Remove the "Connectivity guard" feature bullet**

Find and delete this line from the features list near the top:

```
- **Connectivity guard** – checks internet before every request; throws a clear offline error
```

- [ ] **Step 2: Remove the "Mobile timeout" feature bullet**

Find and delete:

```
- **Mobile timeout** – extends receive-timeout automatically on cellular networks
```

- [ ] **Step 3: Remove `connectivity_plus` from the dependencies table**

Find and delete the row:

```
| [connectivity_plus](https://pub.dev/packages/connectivity_plus) | Network state |
```

- [ ] **Step 4: Soften the "connectivity error" phrasing in the localisation section**

Find the sentence (currently around line 159):

```
From that point on, every `ApiException.message` and connectivity error is
```

Change it to:

```
From that point on, every `ApiException.message` and network error is
```

- [ ] **Step 5: Verify no other connectivity references remain**

Run:
```bash
grep -n -i "connectivity\|mobile timeout\|connectivity guard" README.md
```
Expected: no output.

- [ ] **Step 6: Commit**

```bash
git add README.md
git commit -m "docs: update README for removed connectivity precheck (1.1.0)"
```

---

## Task 9: Update CHANGELOG

**Files:**
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Add `1.1.0` entry**

Prepend a new section at the top of `CHANGELOG.md` (above the existing `1.0.3` entry):

```markdown
## 1.1.0

### Breaking changes

- **Removed `connectivity_plus` dependency.** The pre-request connectivity
  check produced false "No internet connection" errors when the OS reported
  a stale network state (notably on iOS after the device or simulator host
  woke from idle). We now trust Dio's own error reporting.
- **`RequestService`, `UploadRequestService`, and `DownloadRequestService`
  no longer accept a `Connectivity` argument.** The constructors now take
  only the `HttpClient`.
- **`NetworkServiceMixin.ensureConnected()` and `withMobileTimeouts()` removed.**
  Callers that need a longer `receiveTimeout` should pass
  `Options(receiveTimeout: Duration(seconds: 30))` themselves.

### Fixed

- `DioExceptionType.connectionError` is now mapped to
  `ApiException(errorType: 'NoInternetConnection')`, preserving the prior
  user-facing offline error message after removing the precheck.

### Migration

If you were constructing services directly:

```dart
// Before
RequestService(httpClient, connectivity: myConnectivity);

// After
RequestService(httpClient);
```

If you depended on `connectivity_plus` transitively, add it to your own
`pubspec.yaml`.
```

- [ ] **Step 2: Commit**

```bash
git add CHANGELOG.md
git commit -m "docs: changelog for 1.1.0"
```

---

## Task 10: Final verification

- [ ] **Step 1: Clean and re-resolve**

Run:
```bash
flutter clean
flutter pub get
```
Expected: success.

- [ ] **Step 2: Run analyzer on the whole package**

Run:
```bash
flutter analyze
```
Expected: 0 issues.

- [ ] **Step 3: Run the full test suite**

Run:
```bash
flutter test
```
Expected: all tests pass.

- [ ] **Step 4: Confirm `connectivity_plus` is gone from sources**

Run:
```bash
grep -rn "connectivity_plus\|package:connectivity_plus" lib/ test/ pubspec.yaml
```
Expected: no output.

- [ ] **Step 5: Confirm version bump**

Run:
```bash
grep "^version:" pubspec.yaml
```
Expected: `version: 1.1.0`

- [ ] **Step 6: Confirm git history**

Run:
```bash
git log --oneline -10
```
Expected to see (most recent first):
- `docs: changelog for 1.1.0`
- `docs: update README for removed connectivity precheck (1.1.0)`
- `docs: drop connectivity-precheck and mobile-timeout from library docstring`
- `feat!: remove connectivity precheck and connectivity_plus dependency`
- `fix: map DioExceptionType.connectionError to NoInternetConnection`
- (earlier commits...)
