# app_smart_network

A smart Flutter network package built on [Dio](https://pub.dev/packages/dio) with:

- **Automatic retry** – retries idempotent requests (GET, PUT, DELETE) on failure
- **Connectivity guard** – checks internet before every request; throws a clear offline error
- **Mobile timeout** – extends receive-timeout automatically on cellular networks
- **Locale-aware errors** – all error messages respect the active language (built-in **English & Arabic**, extensible)
- **Flexible error body parsing** – plug in a custom parser for any backend error format *(v1.1.0)*
- **Automatic token refresh** – silent 401 → refresh → retry cycle *(v1.1.0)*
- **Request / response hooks** – ordered middleware pipelines *(v1.1.0)*
- **Request deduplication** – concurrent identical requests share one network call *(v1.1.0)*
- **Typed validation errors** – `ApiException.validationErrors` is always non-null *(v1.1.0)*
- **Separate upload / download services** – progress callbacks included
- **Zero context dependency** – no `BuildContext` needed for error messages

---

## Installation

Add to your `pubspec.yaml`:

```yaml
dependencies:
  app_smart_network: ^1.1.0
```

---

## Migration from v1.0.3

`ApiService` is now a `@deprecated` typedef alias. Replace every occurrence
with `AppSmartNetworkService`:

```dart
// Before (v1.0.3)
ApiService.initialize(config);
final api = ApiService.instance;

// After (v1.1.0)
AppSmartNetworkService.initialize(config);
final api = AppSmartNetworkService.instance;
```

`ApiService` will be **removed** in v2.0.0. All other existing code compiles
unchanged — v1.1.0 is fully backward-compatible.

---

## Setup

Call `AppSmartNetworkService.initialize()` **once** in `main()` before `runApp()`:

```dart
void main() {
  AppSmartNetworkService.initialize(
    NetworkConfig(
      baseUrl: 'https://api.example.com',

      // Called when the server returns HTTP 401
      onUnauthorized: () {
        AppSmartNetworkService.instance.removeAuthToken();
        // navigate to login
      },
    ),
  );
  runApp(const MyApp());
}
```

> **Important:** Accessing `AppSmartNetworkService.instance` before calling `initialize()` throws a
> `StateError`. Always call `initialize()` first.

Use `AppSmartNetworkService.isInitialized` to guard conditional access:

```dart
if (AppSmartNetworkService.isInitialized) {
  AppSmartNetworkService.instance.setAuthToken(token);
}
```

### NetworkConfig options

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `baseUrl` | `String` | required | Base URL for all requests |
| `connectTimeout` | `Duration` | 30 s | Connection timeout |
| `receiveTimeout` | `Duration` | 30 s | Response timeout |
| `defaultHeaders` | `Map<String, String>?` | `null` | Extra headers added to every request |
| `allowBadCertificate` | `bool` | `false` | Bypass SSL validation (**debug only**) |
| `onUnauthorized` | `OnUnauthorizedCallback?` | `null` | Invoked on HTTP 401 when refresh is not configured or fails |
| `errorBodyParser` | `ErrorBodyParser?` | `null` | Custom parser for error response bodies *(v1.1.0)* |
| `tokenRefresher` | `TokenRefreshCallback?` | `null` | Refresh token callback; triggers on 401 *(v1.1.0)* |
| `refreshEndpointPredicate` | `RefreshEndpointPredicate?` | `null` | Identifies the refresh endpoint to prevent loops *(v1.1.0)* |
| `requestHooks` | `List<RequestHook>` | `[]` | Ordered request middleware pipeline *(v1.1.0)* |
| `responseHooks` | `List<ResponseHook>` | `[]` | Ordered response middleware pipeline *(v1.1.0)* |

---

## Making requests

```dart
final api = AppSmartNetworkService.instance;

// GET
final response = await api.request<Map<String, dynamic>>(
  HttpMethod.get,
  '/users/me',
);

// POST with body
final response = await api.request<Map<String, dynamic>>(
  HttpMethod.post,
  '/posts',
  data: {'title': 'Hello', 'body': 'World'},
);

// PUT
final response = await api.request<Map<String, dynamic>>(
  HttpMethod.put,
  '/posts/1',
  data: {'title': 'Updated'},
);

// DELETE
await api.request<void>(HttpMethod.delete, '/posts/1');
```

### Per-request options

```dart
final cancelToken = CancelToken();

final response = await api.request<Map<String, dynamic>>(
  HttpMethod.get,
  '/search',
  queryParameters: {'q': 'flutter'},
  cancelToken: cancelToken,
  options: Options(headers: {'X-Custom': 'value'}),
  onReceiveProgress: (received, total) {
    if (total != -1) print('${(received / total * 100).toStringAsFixed(0)}%');
  },
);

// Cancel any time
cancelToken.cancel();
```

### Override base URL per request

```dart
// Uses https://cdn.example.com/file instead of the global baseUrl
final response = await api.request<dynamic>(
  HttpMethod.get,
  '/file',
  baseUrl: 'https://cdn.example.com',
);
```

### Request deduplication *(v1.1.0)*

```dart
// Safe to call from multiple widgets simultaneously — only one HTTP request is sent
final response = await api.request<Map<String, dynamic>>(
  HttpMethod.get,
  '/users/me',
  deduplicate: true,
);
```

---

## Auth token

```dart
// Set after login
AppSmartNetworkService.instance.setAuthToken(token);

// Remove on logout
AppSmartNetworkService.instance.removeAuthToken();
```

### Automatic token refresh on 401 *(v1.1.0)*

```dart
AppSmartNetworkService.initialize(
  NetworkConfig(
    baseUrl: 'https://api.example.com',
    tokenRefresher: () async {
      // Call your refresh endpoint directly
      try {
        final res = await Dio().post('/auth/refresh',
            data: {'refreshToken': await storage.read('refreshToken')});
        final newToken = res.data['accessToken'] as String;
        await storage.write('accessToken', newToken);
        return newToken; // success
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

---

## Locale-aware error messages

Call `setAppLocale()` whenever the user changes language. It:

1. Sets the `Accept-Language` request header
2. Switches the internal error-message locale

```dart
// Switch to Arabic
AppSmartNetworkService.instance.setAppLocale('ar');

// Back to English
AppSmartNetworkService.instance.setAppLocale('en');
```

From that point on, every `ApiException.message` and connectivity error is
returned in the selected language automatically.

Call `removeAppLocale()` to go back to the default locale that was set in
`NetworkConfig.defaultHeaders['Accept-Language']` at `initialize()` time
(falls back to `'en'` if no locale was set there):

```dart
AppSmartNetworkService.instance.removeAppLocale();
```

### Built-in languages

| Code | Language |
|------|----------|
| `en` | English (default) |
| `ar` | Arabic |

### Add a custom language

```dart
NetworkLocale.addTranslations('fr', {
  'NoInternetConnection': 'Pas de connexion internet.',
  'ConnectionTimeout':    'Délai de connexion dépassé.',
  'status_404':          'Ressource introuvable.',
  // ... add only the keys you need; missing keys fall back to English
});

AppSmartNetworkService.instance.setAppLocale('fr');
```

### Remove custom translations

```dart
// Remove only French overrides
NetworkLocale.clearCustomTranslations('fr');

// Remove all custom translations across every locale
NetworkLocale.clearCustomTranslations();
```

---

## Error handling

All errors are thrown as `ApiException`:

```dart
try {
  final response = await api.request<Map<String, dynamic>>(
    HttpMethod.get,
    '/users/me',
  );
  final user = UserModel.fromJson(response.data!);
} on ApiException catch (e) {
  print(e.message);       // translated to current locale
  print(e.statusCode);    // HTTP status (0 = network/offline)
  print(e.errorCategory); // 'Network Error', 'Authentication Error', …
  print(e.apiErrorCode);  // server-side code e.g. 'UserNotFound'

  // Specific checks
  if (e.isUnauthorized)    { /* 401 */ }
  if (e.isNotFound)        { /* 404 */ }
  if (e.isNetworkError)    { /* offline / no connection */ }
  if (e.isValidationError) { /* 422 */ }

  // Check a custom server error code
  if (e.hasApiErrorCode('UserNotActive')) { /* … */ }

  // Typed validation errors (v1.1.0) — always non-null, no casting needed
  for (final error in e.validationErrors) {
    print('${error.field}: ${error.message}');
  }
}
```

### Custom error body parser *(v1.1.0)*

```dart
AppSmartNetworkService.initialize(
  NetworkConfig(
    baseUrl: 'https://api.example.com',
    errorBodyParser: (body, statusCode) {
      if (body is! Map<String, dynamic>) return null;
      final error = body['error'];
      if (error is Map<String, dynamic>) {
        return (
          message: error['detail']?.toString(),
          apiErrorCode: error['code']?.toString(),
          validationErrors: const [],
        );
      }
      return null; // fall back to built-in extraction
    },
  ),
);
```

### Domain layer – map to your own Failure type

`ServerFailure` / `CacheFailure` were removed in `1.0.3`. Define your own
`Failure` types and map from `ApiException` in the repository layer:

```dart
// In your repository
Future<Either<Failure, UserModel>> getUser() async {
  try {
    final response = await api.request<Map<String, dynamic>>(
      HttpMethod.get,
      '/users/me',
    );
    return Right(UserModel.fromJson(response.data!));
  } on ApiException catch (e) {
    return Left(ServerFailure(e.message, statusCode: e.statusCode));
  }
}
```

---

## Request / response hooks *(v1.1.0)*

```dart
AppSmartNetworkService.initialize(
  NetworkConfig(
    baseUrl: 'https://api.example.com',
    requestHooks: [
      // Add an HMAC signature header
      (options) {
        options.headers['X-Signature'] = HmacSigner.sign(options.path);
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

## File upload

```dart
final response = await api.uploadFile<Map<String, dynamic>>(
  '/upload/avatar',
  File('/path/to/image.jpg'),
  fieldName: 'avatar',
  data: {'userId': '42'},       // optional extra fields
  onSendProgress: (sent, total) {
    print('${(sent / total * 100).toStringAsFixed(0)}%');
  },
);
```

---

## File download

```dart
await api.download(
  '/files/report.pdf',
  '/storage/emulated/0/Download/report.pdf',
  onReceiveProgress: (received, total) {
    if (total != -1) print('${(received / total * 100).toStringAsFixed(0)}%');
  },
);
```

---

## Dynamic configuration

Change settings at runtime without reinitialising:

```dart
AppSmartNetworkService.instance.configure(
  baseUrl: 'https://staging.example.com',
  connectTimeoutMs: 15000,
  receiveTimeoutMs: 15000,
  headers: {'X-App-Version': '2.0.0'},
);
```

---

## Typical datasource pattern

```dart
class UserRemoteDatasource {
  final AppSmartNetworkService _api = AppSmartNetworkService.instance;

  Future<UserModel> getProfile() async {
    // Set locale from cache before request
    final locale = await AppCacheManager().getAppLocale();
    if (locale != null) _api.setAppLocale(locale);

    final response = await _api.request<Map<String, dynamic>>(
      HttpMethod.get,
      ApiEndpoints.profile,
    );
    return UserModel.fromJson(response.data!);
  }

  Future<UserModel> updateProfile(UpdateProfileParams params) async {
    final response = await _api.request<Map<String, dynamic>>(
      HttpMethod.put,
      ApiEndpoints.profile,
      data: params.toMap(),
      cancelToken: params.cancelToken,
    );
    return UserModel.fromJson(response.data!);
  }
}
```

---

## Example app

A full runnable example using [JSONPlaceholder](https://jsonplaceholder.typicode.com) is in the [`example/`](example/) directory.

```bash
cd example
flutter run
```

It demonstrates: initialization, GET / POST requests, error dialogs with
locale-aware messages, EN ↔ AR language toggle, and a 404 error demo.

---

## Dependencies

| Package | Role |
|---------|------|
| [dio](https://pub.dev/packages/dio) | HTTP client |
| [connectivity_plus](https://pub.dev/packages/connectivity_plus) | Network state |
| [dio_smart_retry](https://pub.dev/packages/dio_smart_retry) | Retry interceptor |
| [pretty_dio_logger](https://pub.dev/packages/pretty_dio_logger) | Debug logging |
