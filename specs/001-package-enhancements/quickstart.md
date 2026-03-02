# Quickstart & Migration Guide: v1.0.3 → v1.1.0

**Package**: `app_smart_network`
**Date**: 2026-03-01

---

## Upgrade

```yaml
# pubspec.yaml
dependencies:
  app_smart_network: ^1.1.0
```

No code changes are required for existing apps — v1.1.0 is fully
backward-compatible with v1.0.3. All new features are opt-in.

---

## Migration: `ApiService` → `AppSmartNetworkService`

`ApiService` now shows a deprecation warning at every call site. Migrate by
replacing the name globally.

```dart
// Before (v1.0.3)
ApiService.initialize(config);
final api = ApiService.instance;
ApiService.isInitialized;

// After (v1.1.0)
AppSmartNetworkService.initialize(config);
final api = AppSmartNetworkService.instance;
AppSmartNetworkService.isInitialized;
```

`ApiService` will be **removed** in v2.0.0.

---

## New Feature: Flexible Error Body Parsing (US1)

Register a custom parser once in `NetworkConfig`. The parser receives the raw
response body and HTTP status code, and returns structured error data. If the
parser returns `null` the built-in extraction runs as a fallback.

```dart
AppSmartNetworkService.initialize(
  NetworkConfig(
    baseUrl: 'https://api.example.com',
    errorBodyParser: (body, statusCode) {
      if (body is! Map<String, dynamic>) return null;

      // Handle {"error": {"code": "USER_LOCKED", "detail": "..."}}
      final error = body['error'];
      if (error is Map<String, dynamic>) {
        return (
          message: error['detail']?.toString(),
          apiErrorCode: error['code']?.toString(),
          validationErrors: const [],
        );
      }

      // Handle {"errors": [{"field": "email", "msg": "taken"}]}
      final errors = body['errors'];
      if (errors is List) {
        return (
          message: null, // use locale-translated status message
          apiErrorCode: null,
          validationErrors: errors
              .whereType<Map<String, dynamic>>()
              .map((e) => ValidationError(
                    field: e['field']?.toString() ?? '',
                    message: e['msg']?.toString() ?? '',
                  ))
              .toList(),
        );
      }

      return null; // unrecognized format → built-in fallback
    },
  ),
);
```

Catch errors as before — no changes to catch-block code:

```dart
try {
  await AppSmartNetworkService.instance.request<Map>(HttpMethod.get, '/me');
} on ApiException catch (e) {
  print(e.message);           // translated to current locale
  print(e.apiErrorCode);      // extracted by your parser
  print(e.validationErrors);  // typed, non-null list
}
```

---

## New Feature: Automatic Token Refresh on 401 (US2)

Provide a `tokenRefresher` callback and a `refreshEndpointPredicate` to
identify the refresh URL (prevents infinite loops).

```dart
AppSmartNetworkService.initialize(
  NetworkConfig(
    baseUrl: 'https://api.example.com',
    tokenRefresher: () async {
      // Call your refresh endpoint directly (bypasses the refresh interceptor)
      final dio = Dio();
      try {
        final res = await dio.post(
          'https://api.example.com/auth/refresh',
          data: {'refreshToken': await SecureStorage.read('refreshToken')},
        );
        final newToken = res.data['accessToken'] as String;
        await SecureStorage.write('accessToken', newToken);
        return newToken;
      } catch (_) {
        return null; // signals failure → onUnauthorized is called
      }
    },
    refreshEndpointPredicate: (url) => url.contains('/auth/refresh'),
    onUnauthorized: () {
      AppSmartNetworkService.instance.removeAuthToken();
      // navigate to login
    },
  ),
);
```

Token refresh is completely transparent to callers:

```dart
// This call may internally hit a 401, refresh, and retry — caller never knows
final response = await AppSmartNetworkService.instance.request<Map>(
  HttpMethod.get,
  '/users/me',
);
```

---

## New Feature: Custom Request / Response Hooks (US3)

Register ordered pipelines for request modification and response transformation.

```dart
AppSmartNetworkService.initialize(
  NetworkConfig(
    baseUrl: 'https://api.example.com',
    requestHooks: [
      // Add HMAC signature header
      (options) {
        final signature = HmacSigner.sign(options.path, options.data);
        options.headers['X-Signature'] = signature;
        return options;
      },
    ],
    responseHooks: [
      // Unwrap {"data": {...}} envelope
      (response) {
        if (response.data is Map && response.data['data'] != null) {
          return response.copyWith(data: response.data['data']);
        }
        return response;
      },
    ],
  ),
);
```

---

## New Feature: Request Deduplication (US4)

Enable per-request by passing `deduplicate: true`. Identical simultaneous
requests share a single network call.

```dart
// Safe to call from 10 concurrent widgets — only 1 HTTP request is sent
Future<UserModel> getProfile() async {
  final response = await AppSmartNetworkService.instance.request<Map>(
    HttpMethod.get,
    '/users/me',
    deduplicate: true,  // NEW
  );
  return UserModel.fromJson(response.data!);
}
```

Deduplication key = `method + url + queryParameters + headers`.
Two requests with different `Authorization` headers are treated as distinct.

---

## New Feature: Typed Validation Errors (US5)

`ApiException.validationErrors` is now a typed, non-null `List<ValidationError>`.

```dart
try {
  await AppSmartNetworkService.instance.request<Map>(
    HttpMethod.post,
    '/users/register',
    data: formData,
  );
} on ApiException catch (e) {
  if (e.isValidationError) {
    // Before v1.1.0 (verbose):
    // final errors = e.getResponseField<List>('errors');
    // final fieldErrors = (errors ?? []).map((e) => ...).toList();

    // v1.1.0 (clean, typed, no cast):
    for (final error in e.validationErrors) {
      print('${error.field}: ${error.message}');
    }
  }
}
```

`validationErrors` is always non-null — use `.isEmpty` instead of null checks.

---

## Validation Checklist

Run these checks after upgrading to confirm everything is working:

- [ ] `flutter analyze` passes with zero errors
- [ ] All existing tests pass (`flutter test`)
- [ ] `ApiService` usages show deprecation warnings (migrate to `AppSmartNetworkService`)
- [ ] Custom error parser: register one and verify `ApiException.message` reflects your backend's format
- [ ] Token refresh: simulate a 401 and verify the app does not show a login screen if a valid refresh token exists
- [ ] Deduplication: fire two identical requests concurrently and verify only one network call is made (check debug logs)
- [ ] `ApiException.validationErrors` on a 422: verify it is a non-empty list without any casting
