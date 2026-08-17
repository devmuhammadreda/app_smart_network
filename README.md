# app_smart_network

A smart Flutter network package built on [Dio](https://pub.dev/packages/dio) with:

- **Configurable retry** – retries idempotent requests (GET, PUT, DELETE) by default; tune or disable it app-wide, or override it on a single call
- **Certificate pinning** – optional SPKI pinning per host, from hashes or from bundled certificates, with backup pins and staged rollout
- **Connectivity guard** – checks internet before every request; throws a clear offline error
- **Mobile timeout** – extends receive-timeout automatically on cellular networks
- **Locale-aware errors** – all error messages respect the active language (built-in **English & Arabic**, extensible)
- **Separate upload / download services** – progress callbacks included
- **Zero context dependency** – no `BuildContext` needed for error messages

---

## Installation

Add to your `pubspec.yaml`:

```yaml
dependencies:
  app_smart_network: ^1.4.0
```

---

## Setup

Call `ApiService.initialize()` **once** in `main()` before `runApp()`:

```dart
void main() {
  ApiService.initialize(
    NetworkConfig(
      baseUrl: 'https://api.example.com',

      // Called when the server returns HTTP 401
      onUnauthorized: () {
        ApiService.instance.removeAuthToken();
        // navigate to login
      },
    ),
  );
  runApp(const MyApp());
}
```

> **Important:** Accessing `ApiService.instance` before calling `initialize()` throws a
> `StateError`. Always call `initialize()` first.

Use `ApiService.isInitialized` to guard conditional access:

```dart
if (ApiService.isInitialized) {
  ApiService.instance.setAuthToken(token);
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
| `onUnauthorized` | `OnUnauthorizedCallback?` | `null` | Invoked on HTTP 401 |
| `interceptors` | `List<Interceptor>` | `const []` | Custom Dio interceptors added to the chain |
| `retry` | `RetryPolicy?` | `RetryPolicy()` | App-wide retry behaviour; `null` disables retry |
| `certificatePinning` | `CertificatePinningConfig?` | `null` | SSL public-key pinning; `null` disables pinning |

---

## Retry

By default every idempotent request (GET, PUT, DELETE, HEAD, OPTIONS) is
retried up to three times with a 1 s / 2 s / 3 s backoff. Change that with a
`RetryPolicy` on `NetworkConfig`:

```dart
ApiService.initialize(NetworkConfig(
  baseUrl: 'https://api.example.com',
  retry: const RetryPolicy(
    attempts: 2,                                    // 2 retries, 3 tries total
    delays: [Duration(seconds: 1), Duration(seconds: 5)],
    statuses: {500, 502, 503, 504},
  ),
));
```

Pass `retry: null` to turn retry off for the whole app.

### RetryPolicy options

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `attempts` | `int` | `3` | Retries **after** the first try; `0` disables retry (max `10`) |
| `delays` | `List<Duration>` | `[1 s, 2 s, 3 s]` | Backoff between attempts; the last entry repeats |
| `methods` | `Set<String>` | `{GET, PUT, DELETE, HEAD, OPTIONS}` | Methods eligible for retry |
| `statuses` | `Set<int>` | `defaultRetryableStatuses` | Response codes treated as retryable |

### Per-request retry

Any single call can override the app-wide policy — `request()`, `download()`
and `uploadFile()` all take a `retry:` argument:

```dart
// Never retry this payment, whatever the app-wide policy says.
await api.request(HttpMethod.post, '/payments', retry: RetryPolicy.off);

// Retry this POST five times — it carries an idempotency key.
await api.request(
  HttpMethod.post,
  '/sync',
  data: payload,
  retry: const RetryPolicy(attempts: 5),
);

// Treat 409 as retryable for this call only.
await api.request(HttpMethod.get, '/lock', retry: const RetryPolicy(statuses: {409}));
```

Omitting `retry:` uses the app-wide policy, so existing code keeps its current
behaviour.

> **Two fields are app-wide only.** `delays` cannot vary per request — the
> backoff schedule is fixed when the client is built. `methods` is the
> allowlist for calls that *didn't* ask for anything: attaching a policy to a
> request is itself your statement that the call is safe to replay, so the
> allowlist is bypassed there. That is why `retry: RetryPolicy(attempts: 5)`
> retries a POST even though POST is not in the default allowlist.

**Retrying non-idempotent requests is your call.** A retried POST can create
duplicate records if the first attempt reached the server but the response was
lost. Only opt one in when the endpoint is idempotent — for example when it
accepts an idempotency key.

---

## Certificate pinning

Pinning is **off by default**. When enabled, the package additionally requires a
host's leaf certificate to carry a known public key, so a forged certificate is
rejected even if some CA in the device's trust store signed it.

```dart
ApiService.initialize(NetworkConfig(
  baseUrl: 'https://api.example.com',
  certificatePinning: CertificatePinningConfig(
    pins: {
      'api.example.com': [
        'sha256/AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=', // current key
        'sha256/BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB=', // backup key
      ],
    },
  ),
));
```

### Generating a pin

A pin is the base64 SHA-256 of the certificate's `SubjectPublicKeyInfo` — the
same `sha256/…` format used by HPKP and OkHttp's `CertificatePinner`, so
existing tooling and runbooks apply:

```bash
openssl s_client -connect api.example.com:443 -servername api.example.com < /dev/null 2>/dev/null \
  | openssl x509 -pubkey -noout \
  | openssl pkey -pubin -outform der \
  | openssl dgst -sha256 -binary \
  | openssl enc -base64
```

The digest covers the **public key**, not the whole certificate. A pin therefore
keeps working across certificate renewal as long as the key pair is reused —
unlike a whole-certificate hash, which breaks on every routine rotation.

### From bundled certificates

Instead of pasting hashes, ship the certificates as assets and let the package
derive the pins. `fromAssets` reads and parses every file up front, so a wrong
path or an unreadable certificate fails during `initialize()` rather than on the
first request in production:

```yaml
# pubspec.yaml
flutter:
  assets:
    - assets/certs/
```

```dart
final pinning = await CertificatePinningConfig.fromAssets(
  certificatePaths: {
    'api.example.com': [
      'assets/certs/api.example.com.pem',  // current certificate
      'assets/certs/backup.pub.pem',       // backup key, no certificate yet
    ],
  },
);

ApiService.initialize(NetworkConfig(
  baseUrl: 'https://api.example.com',
  certificatePinning: pinning,
));
```

Each asset must hold **exactly one** PEM block, in either of two forms:

| PEM label | What it is | How the pin is derived |
|-----------|------------|------------------------|
| `CERTIFICATE` | A full X.509 certificate | The ASN.1 is walked to locate `SubjectPublicKeyInfo`, which is then hashed |
| `PUBLIC KEY` | A bare `SubjectPublicKeyInfo` | Hashed directly — there is no certificate to walk |

Both forms produce identical pins for the same key pair, so a certificate and a
public key extracted from it are interchangeable — and, being the same key, they
count as **one** pin, not two.

`ArgumentError` naming the offending path is thrown when an asset is missing or
unreadable, is not PEM, carries any other label, holds **more than one** PEM
block (a chain file is refused rather than silently pinning whichever
certificate comes first), or cannot be parsed as a certificate.

`enforce`, `includeSubdomains` and `onPinFailure` behave exactly as they do on
the unnamed constructor, and all the same validation applies — including the
two-distinct-pins rule.

#### Generating a backup keypair

The `PUBLIC KEY` form exists so the mandatory backup pin can come from a key
pair that has **no certificate yet** — pinning ships without waiting on a CA to
issue anything:

```bash
# Generate the backup key and keep it OFFLINE. It must never reach the app,
# the repository, or CI.
openssl genrsa -out backup.key 2048

# The public half is what ships, as an asset:
openssl rsa -in backup.key -pubout -out backup.pub.pem

# Its pin, should you want to verify what the package derived:
openssl pkey -in backup.pub.pem -pubin -outform der \
  | openssl dgst -sha256 -binary \
  | openssl enc -base64
```

When the current certificate has to be replaced, issue the new one against
`backup.key`. Installed apps already trust that key, so the rotation is a
server-side change instead of an app release.

### ⚠️ Always ship a backup pin

> **A single pin is an outage waiting to happen.** If that key is lost or has to
> be rotated in a hurry, every installed copy of the app stops reaching your API
> and no server-side change can fix it — only a new app release can, at store
> review speed.
>
> Generate a second key pair, compute its pin, and keep the key **offline**.
> Ship both pins from day one so a rotation is a server-side change.
>
> The package enforces this: fewer than two distinct pins for a host throws
> `ArgumentError` at startup.

### Options

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `pins` | `Map<String, List<String>>` | required | Host → accepted `sha256/…` pins (min. 2 per host) |
| `enforce` | `bool` | `true` | When `false`, mismatches are reported but allowed |
| `includeSubdomains` | `bool` | `false` | Extend a host's pins to its subdomains |
| `onPinFailure` | `OnPinFailureCallback?` | `null` | Called on every mismatch, for telemetry |

### Which hosts are pinned

Only the hosts you list. Everything else — analytics, crash reporting, Firebase,
image CDNs — falls through to normal TLS validation untouched. Pinning does not
fail closed on unknown hosts, because doing so would break every third-party
service the app talks to.

With `includeSubdomains: true`, `example.com` also covers `api.example.com` and
`a.b.example.com`, but never `notexample.com`. An exact host entry always wins
over an inherited one.

### Staged rollout

Set `enforce: false` to measure impact before enforcing. Mismatches are reported
to `onPinFailure` and the connection proceeds:

```dart
CertificatePinningConfig(
  pins: {'api.example.com': [currentPin, backupPin]},
  enforce: false, // report only — never ship this as the final state
  onPinFailure: (host, presentedPins) {
    analytics.log('pin_mismatch', {'host': host, 'pins': presentedPins});
  },
)
```

Watch the failure rate, confirm it is zero for legitimate traffic, then flip
`enforce` back to `true`.

### Handling a pin failure

A pin failure is a **security event**, not a connectivity blip, and it arrives as
a distinct exception type:

```dart
try {
  await ApiService.instance.request(HttpMethod.get, '/me');
} on CertificatePinningException catch (e) {
  security.report('pin_failure', host: e.host); // e.host is the pinned host
  showBlockingSecurityWarning();
} on ApiException catch (e) {
  showSnackBar(e.message);
}
```

`CertificatePinningException` extends `ApiException`, so existing handlers keep
working. Its `message` is deliberately generic and locale-aware; the pins the
server actually presented go to `onPinFailure` for telemetry and are never put
in a user-facing message.

Pin failures are **never retried** — replaying a rejected handshake re-presents
the same certificate for the same verdict.

### Shielded and unshielded builds

To ship one build that pins and one that does not, vary only the config:

```dart
const isShielded = bool.fromEnvironment('SHIELDED', defaultValue: true);

ApiService.initialize(NetworkConfig(
  baseUrl: 'https://api.example.com',
  certificatePinning: isShielded
      ? CertificatePinningConfig(pins: {'api.example.com': [currentPin, backupPin]})
      : null,
));
```

`allowBadCertificate: true` **cannot** be combined with `certificatePinning` —
one disables validation while the other tightens it. The pair throws
`ArgumentError` at startup rather than producing an app that looks pinned but is
not.

### What is validated, and when

Pinning runs through Dio's `validateCertificate` hook, which evaluates the leaf
certificate on **every connection** — not `badCertificateCallback`, which fires
only after chain validation has already failed and so could never add pinning on
top of an otherwise-valid certificate.

Malformed or unparseable certificates are **rejected**, never treated as a pass.

---

## Custom interceptors

Pass your own Dio interceptors to `NetworkConfig`. They are registered
**before** the built-in retry interceptor, the 401 handler, and the debug
logger:

```
your interceptors  →  retry  →  401 handler  →  debug logger
```

That position matters for two reasons:

- Your `onError` sees a 401 before `onUnauthorized` fires (a 401 is not
  retried, so it reaches your interceptor untouched).
- For a request that genuinely gets retried, each retry restarts the whole
  chain, so your `onError` fires once per real attempt — never a duplicate
  replay of the same failure, which is what happens if an interceptor sits
  after retry instead.

Headers you set in `onRequest` still show up in the debug logs, since the
logger stays last.

```dart
class TraceInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.headers['X-Trace-Id'] = 'trace-id'; // your implementation
    handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    // your implementation, e.g. report to a crash-reporting tool
    handler.next(err);
  }
}

void main() {
  ApiService.initialize(
    NetworkConfig(
      baseUrl: 'https://api.example.com',
      interceptors: [TraceInterceptor()],
    ),
  );
  runApp(const MyApp());
}
```

`Interceptor`, `InterceptorsWrapper`, `QueuedInterceptor`,
`QueuedInterceptorsWrapper`, `RequestOptions`, `RequestInterceptorHandler`,
`ResponseInterceptorHandler`, `ErrorInterceptorHandler`, `DioException`,
`DioExceptionType` and `ResponseType` are all exported from
`package:app_smart_network`, so you don't need a direct `dio` dependency to
write most interceptors.

> Interceptors are captured at `initialize()`. To change them, call
> `ApiService.initialize()` again with a new `NetworkConfig` — and pass fresh
> interceptor instances when you do, since the package closes the old Dio
> client but does not dispose your interceptors.

### Token refresh on 401

Since the package's `Dio` instance isn't exposed, replay a request after a
token refresh through `ApiService.instance.request(...)`:

```dart
class TokenRefreshInterceptor extends Interceptor {
  bool _isRefreshing = false;

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    if (err.response?.statusCode != 401 || _isRefreshing) {
      handler.next(err);
      return;
    }

    _isRefreshing = true;
    try {
      final newToken = await _refreshToken(); // your implementation
      ApiService.instance.setAuthToken(newToken);

      final requestOptions = err.requestOptions;
      final response = await ApiService.instance.request<dynamic>(
        HttpMethod.values.byName(requestOptions.method.toLowerCase()),
        requestOptions.path,
        data: requestOptions.data,
        queryParameters: requestOptions.queryParameters,
      );
      handler.resolve(response);
    } catch (_) {
      // Refresh or replay failed — fall through to onUnauthorized.
      handler.next(err);
    } finally {
      _isRefreshing = false;
    }
  }

  Future<String> _refreshToken() async {
    // your implementation: call your refresh endpoint and return the new
    // access token.
    throw UnimplementedError();
  }
}
```

> **Re-entrancy warning:** `ApiService.instance.request(...)` re-enters the
> full interceptor chain, including this interceptor's own `onError` if the
> replayed request also fails with a 401. The `_isRefreshing` guard above
> prevents that from recursing into another refresh attempt, but a repeated
> 401 after a successful refresh will still fall through to `onError` once
> more with `_isRefreshing` false again — make sure your refresh logic can't
> loop indefinitely (e.g. cap retries or bail out if the new token is
> rejected immediately).

### Caveats

- `onRequest` fires once per retry attempt, not just the first. Prefer
  **assignment** (`options.headers['X'] = v`) over **accumulation**
  (`options.path = '$prefix${options.path}'`) — accumulation compounds on
  every retried attempt.
- The connectivity pre-check in `ensureConnected()` throws before the request
  ever reaches Dio, so consumer interceptors never observe offline failures;
  only failures that occur after a request is actually dispatched reach your
  `onError`.

---

## Making requests

```dart
final api = ApiService.instance;

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

---

## Auth token

```dart
// Set after login
ApiService.instance.setAuthToken(token);

// Remove on logout
ApiService.instance.removeAuthToken();
```

---

## Locale-aware error messages

Call `setAppLocale()` whenever the user changes language. It:

1. Sets the `Accept-Language` request header
2. Switches the internal error-message locale

```dart
// Switch to Arabic
ApiService.instance.setAppLocale('ar');

// Back to English
ApiService.instance.setAppLocale('en');
```

From that point on, every `ApiException.message` and connectivity error is
returned in the selected language automatically.

Call `removeAppLocale()` to go back to the default locale that was set in
`NetworkConfig.defaultHeaders['Accept-Language']` at `initialize()` time
(falls back to `'en'` if no locale was set there):

```dart
ApiService.instance.removeAppLocale();
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

ApiService.instance.setAppLocale('fr');
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

  // Read a field from the raw response body
  final errors = e.getResponseField<List>('errors');
}
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
ApiService.instance.configure(
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
  final ApiService _api = ApiService.instance;

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
| [asn1lib](https://pub.dev/packages/asn1lib) | Certificate parsing for pinning |
| [crypto](https://pub.dev/packages/crypto) | SHA-256 for SPKI pins |
