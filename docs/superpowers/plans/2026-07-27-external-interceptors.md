# External Interceptors Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let consumers of `app_smart_network` register their own Dio interceptors through `NetworkConfig`.

**Architecture:** `NetworkConfig` gains a `List<Interceptor> interceptors` field defaulting to `const []`. `HttpClient._setup()` splices that list into the built-in chain between the retry interceptor and the 401 handler. The public barrel re-exports the Dio types needed to author an interceptor so consumers still need no direct `dio` dependency.

**Tech Stack:** Dart / Flutter, `dio ^5.9.1`, `dio_smart_retry ^7.0.1`, `pretty_dio_logger ^1.4.0`, `flutter_test`.

**Spec:** `docs/superpowers/specs/2026-07-27-external-interceptors-design.md`

## Global Constraints

- Work on branch `feat/external-interceptors` (already checked out).
- No new dependencies. Everything used here is already in `pubspec.yaml`.
- Environment floors stay as-is: `sdk: ^3.0.0`, `flutter: ">=3.0.0"`.
- The existing test suite in `test/app_smart_network_test.dart` must keep passing **unchanged** — do not edit that file.
- `flutter analyze` must report zero issues at the end of every task.
- No test may perform real network I/O. Tests swap in a fake `HttpClientAdapter`.
- Target release version is `1.1.0` (additive feature → minor bump).
- Commit messages follow `<type>: <description>` (feat, fix, docs, test, chore). No attribution footer.
- Out of scope, do not add: runtime `addInterceptor`/`removeInterceptor` on `ApiService`, and flags to disable the built-in retry or logger interceptors.

---

### Task 1: Accept and register custom interceptors

**Files:**
- Modify: `lib/src/config/network_config.dart:1` (add import), `lib/src/config/network_config.dart:25-32` (constructor)
- Modify: `lib/src/client/http_client.dart:59-63` (interceptor chain)
- Create: `test/interceptors_test.dart`

**Interfaces:**
- Consumes: `NetworkConfig` (existing), `HttpClient(NetworkConfig config)` with public `Dio get dio` (existing, `lib/src/client/http_client.dart:100`), `UnAuthInterceptor` (existing, `lib/src/interceptors/unauth_interceptor.dart`).
- Produces: `NetworkConfig.interceptors` — a `final List<Interceptor> interceptors` field, named constructor parameter `interceptors`, default `const []`. Task 2 and Task 3 both depend on this exact name and type.

**Background you need:**

`HttpClient` builds a private `Dio` and registers three interceptors today (`http_client.dart:59-63`): a `RetryInterceptor` from `dio_smart_retry`, a `PrettyDioLogger` (debug builds only), and the package's own `UnAuthInterceptor`. Dio runs `onRequest`, `onResponse` and `onError` handlers in registration order. Custom interceptors go **after** retry and **before** `UnAuthInterceptor`, and the logger moves to the end of the chain — that ordering is the whole point of the feature, so the tests below assert it directly.

Note: Dio 5 seeds `dio.interceptors` with its own `ImplyContentTypeInterceptor` at index 0. Never assert on the exact length of the interceptor list — assert on relative positions and on `whereType<T>()` counts.

- [ ] **Step 1: Write the failing test**

Create `test/interceptors_test.dart` with exactly this content:

```dart
import 'dart:typed_data';

import 'package:app_smart_network/src/client/http_client.dart';
import 'package:app_smart_network/src/config/network_config.dart';
import 'package:app_smart_network/src/interceptors/unauth_interceptor.dart';
import 'package:dio/dio.dart';
import 'package:dio_smart_retry/dio_smart_retry.dart';
import 'package:flutter_test/flutter_test.dart';

/// Returns a canned response without touching the network and records every
/// [RequestOptions] that reaches the wire.
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter({this.statusCode = 200});

  final int statusCode;
  final List<RequestOptions> captured = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    captured.add(options);
    return ResponseBody.fromString('ok', statusCode);
  }

  @override
  void close({bool force = false}) {}
}

/// Appends a label to [events] for every callback it sees, and optionally adds
/// a header on the way out.
class _RecordingInterceptor extends Interceptor {
  _RecordingInterceptor(this.events, {this.headerToAdd});

  final List<String> events;
  final MapEntry<String, String>? headerToAdd;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    events.add('request');
    final header = headerToAdd;
    if (header != null) options.headers[header.key] = header.value;
    handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    events.add('error');
    handler.next(err);
  }
}

/// Plain response type keeps the request off the background JSON transformer,
/// so no isolate work happens during tests.
Future<void> _get(HttpClient client) => client.dio.get<String>(
      '/ping',
      options: Options(responseType: ResponseType.plain),
    );

void main() {
  group('NetworkConfig.interceptors', () {
    test('a custom interceptor receives outgoing requests', () async {
      final events = <String>[];
      final client = HttpClient(NetworkConfig(
        baseUrl: 'https://example.com',
        interceptors: [_RecordingInterceptor(events)],
      ));
      client.dio.httpClientAdapter = _FakeAdapter();

      await _get(client);

      expect(events, ['request']);
      client.dispose();
    });

    test('headers added by a custom interceptor reach the adapter', () async {
      final adapter = _FakeAdapter();
      final client = HttpClient(NetworkConfig(
        baseUrl: 'https://example.com',
        interceptors: [
          _RecordingInterceptor(
            <String>[],
            headerToAdd: const MapEntry('X-Trace-Id', 'abc123'),
          ),
        ],
      ));
      client.dio.httpClientAdapter = adapter;

      await _get(client);

      expect(adapter.captured.single.headers['X-Trace-Id'], 'abc123');
      client.dispose();
    });

    test('custom onError runs before onUnauthorized fires', () async {
      final events = <String>[];
      final client = HttpClient(NetworkConfig(
        baseUrl: 'https://example.com',
        interceptors: [_RecordingInterceptor(events)],
        onUnauthorized: () => events.add('unauthorized'),
      ));
      client.dio.httpClientAdapter = _FakeAdapter(statusCode: 401);

      await expectLater(_get(client), throwsA(isA<DioException>()));

      expect(events, ['request', 'error', 'unauthorized']);
      client.dispose();
    });

    test('custom interceptors sit between retry and the 401 handler', () {
      final custom = _RecordingInterceptor(<String>[]);
      final client = HttpClient(NetworkConfig(
        baseUrl: 'https://example.com',
        interceptors: [custom],
      ));

      final chain = client.dio.interceptors;
      expect(
        chain.indexWhere((i) => i is RetryInterceptor),
        lessThan(chain.indexOf(custom)),
      );
      expect(
        chain.indexOf(custom),
        lessThan(chain.indexWhere((i) => i is UnAuthInterceptor)),
      );
      client.dispose();
    });

    test('default config registers the built-ins and nothing custom', () {
      final client =
          HttpClient(const NetworkConfig(baseUrl: 'https://example.com'));

      expect(client.dio.interceptors.whereType<RetryInterceptor>(),
          hasLength(1));
      expect(client.dio.interceptors.whereType<UnAuthInterceptor>(),
          hasLength(1));
      expect(client.dio.interceptors.whereType<_RecordingInterceptor>(),
          isEmpty);
      client.dispose();
    });
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/interceptors_test.dart`

Expected: compile failure — `No named parameter with the name 'interceptors'` on `NetworkConfig`.

- [ ] **Step 3: Add the field to `NetworkConfig`**

In `lib/src/config/network_config.dart`, add the Dio import at the very top of the file, above the existing `typedef`:

```dart
import 'package:dio/dio.dart';
```

Add this field inside the class, after the `onUnauthorized` field (`network_config.dart:23`):

```dart
  /// Custom interceptors spliced into the built-in chain.
  ///
  /// They run after the retry interceptor and before the 401 handler and the
  /// debug logger, so they can observe a 401 before [onUnauthorized] fires and
  /// any headers they add appear in debug logs.
  ///
  /// Interceptors are fixed at initialization; call `ApiService.initialize()`
  /// again with a new config to change them.
  final List<Interceptor> interceptors;
```

Add the parameter to the constructor, as the last entry before the closing `});`:

```dart
    this.interceptors = const [],
```

The constructor stays `const`. Do not change any existing parameter.

- [ ] **Step 4: Splice the interceptors into the chain**

In `lib/src/client/http_client.dart`, replace the `_dio.interceptors.addAll([...])` block at lines 59-63 with:

```dart
    // Order matters: consumer interceptors run after retry (so they see every
    // attempt) and before UnAuthInterceptor (so they can handle a 401 before
    // onUnauthorized tears down the session). The logger runs last so it prints
    // the final request after all mutations.
    _dio.interceptors.addAll([
      _buildRetryInterceptor(),
      ...config.interceptors,
      UnAuthInterceptor(onUnauthorized: config.onUnauthorized),
      if (kDebugMode) _buildLoggerInterceptor(),
    ]);
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `flutter test`

Expected: PASS — the 5 new tests plus all pre-existing tests in `test/app_smart_network_test.dart`.

- [ ] **Step 6: Run the analyzer**

Run: `flutter analyze`

Expected: `No issues found!`

- [ ] **Step 7: Commit**

```bash
git add lib/src/config/network_config.dart lib/src/client/http_client.dart test/interceptors_test.dart
git commit -m "feat: allow custom interceptors via NetworkConfig.interceptors"
```

---

### Task 2: Export the interceptor authoring types

**Files:**
- Modify: `lib/app_smart_network.dart:25-33` (the `export 'package:dio/dio.dart' show ...` clause)
- Create: `test/public_api_test.dart`

**Interfaces:**
- Consumes: `NetworkConfig.interceptors` from Task 1 — `final List<Interceptor> interceptors`, named parameter `interceptors`.
- Produces: nine additional symbols on the public barrel — `Interceptor`, `InterceptorsWrapper`, `QueuedInterceptor`, `QueuedInterceptorsWrapper`, `RequestOptions`, `RequestInterceptorHandler`, `ResponseInterceptorHandler`, `ErrorInterceptorHandler`, `DioException`.

**Background you need:**

`lib/app_smart_network.dart` re-exports a hand-picked subset of Dio so consumers don't need a direct `dio` dependency. That subset covers making requests but not writing an interceptor. The test below is a compile-time proof: it imports **only** `package:app_smart_network/app_smart_network.dart` and would fail to compile if any authoring type were missing. Do not add a `dio` import to that test file — that would defeat its purpose.

- [ ] **Step 1: Write the failing test**

Create `test/public_api_test.dart` with exactly this content:

```dart
// Deliberately imports only the public barrel — no `package:dio/dio.dart`.
// This file failing to compile means the barrel is missing an export.
import 'package:app_smart_network/app_smart_network.dart';
import 'package:flutter_test/flutter_test.dart';

class _BarrelInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) =>
      handler.next(options);

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) =>
      handler.next(response);

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) =>
      handler.next(err);
}

class _BarrelQueuedInterceptor extends QueuedInterceptor {}

void main() {
  test('interceptor authoring types are exported from the public barrel', () {
    final config = NetworkConfig(
      baseUrl: 'https://example.com',
      interceptors: [
        _BarrelInterceptor(),
        _BarrelQueuedInterceptor(),
        InterceptorsWrapper(),
        QueuedInterceptorsWrapper(),
      ],
    );

    expect(config.interceptors, hasLength(4));
    expect(config.interceptors.first, isA<Interceptor>());
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/public_api_test.dart`

Expected: compile failure — `Undefined class 'Interceptor'` (and the same for the other unexported types).

- [ ] **Step 3: Extend the export clause**

In `lib/app_smart_network.dart`, replace the existing export at lines 25-33 with:

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
        // Types needed to author a custom interceptor.
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

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test`

Expected: PASS — every test file, including `test/interceptors_test.dart` from Task 1 and the pre-existing suite.

- [ ] **Step 5: Run the analyzer**

Run: `flutter analyze`

Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add lib/app_smart_network.dart test/public_api_test.dart
git commit -m "feat: export Dio interceptor authoring types from the barrel"
```

---

### Task 3: Document and release 1.1.0

**Files:**
- Modify: `README.md:20` (install version), `README.md:66` (config table), `README.md:69` (new section before `## Making requests`)
- Modify: `CHANGELOG.md:1` (new entry at the top)
- Modify: `pubspec.yaml:3` (version)

**Interfaces:**
- Consumes: `NetworkConfig.interceptors` from Task 1 and the barrel exports from Task 2. Every symbol used in the README example must already exist — do not introduce new API here.
- Produces: nothing consumed by later tasks. This is the final task.

- [ ] **Step 1: Bump the install snippet in the README**

In `README.md`, change line 20 from:

```
  app_smart_network: ^1.0.4
```

to:

```
  app_smart_network: ^1.1.0
```

- [ ] **Step 2: Add the config table row**

In `README.md`, add this row to the `### NetworkConfig options` table, directly after the `onUnauthorized` row at line 66:

```
| `interceptors` | `List<Interceptor>` | `const []` | Custom Dio interceptors added to the chain |
```

- [ ] **Step 3: Add the "Custom interceptors" section**

In `README.md`, insert this section between the `---` on line 68 and the `## Making requests` heading on line 70:

````markdown
## Custom interceptors

Pass your own Dio interceptors to `NetworkConfig`. They are registered **after**
the built-in retry interceptor and **before** the 401 handler and the debug
logger:

```
retry  →  your interceptors  →  401 handler  →  debug logger
```

That position matters: your `onError` sees a 401 before `onUnauthorized` fires,
and headers you set in `onRequest` show up in the debug logs.

```dart
class TraceInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.headers['X-Trace-Id'] = generateTraceId();
    handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    reportToCrashTool(err);
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
`ResponseInterceptorHandler`, `ErrorInterceptorHandler` and `DioException` are
all exported from `package:app_smart_network`, so you don't need a direct `dio`
dependency to write one.

> Interceptors are captured at `initialize()`. To change them, call
> `ApiService.initialize()` again with a new `NetworkConfig`.

---
````

- [ ] **Step 4: Add the CHANGELOG entry**

In `CHANGELOG.md`, insert this at the very top of the file, above the existing `## 1.0.5` heading on line 1:

```markdown
## 1.1.0

### Features

- **Custom interceptors** — `NetworkConfig` now accepts an `interceptors` list.
  They are registered after the built-in retry interceptor and before the 401
  handler and the debug logger, so a custom interceptor can handle a 401 before
  `onUnauthorized` fires.
- **New public exports** — `Interceptor`, `InterceptorsWrapper`,
  `QueuedInterceptor`, `QueuedInterceptorsWrapper`, `RequestOptions`,
  `RequestInterceptorHandler`, `ResponseInterceptorHandler`,
  `ErrorInterceptorHandler` and `DioException` are re-exported, so writing an
  interceptor no longer requires a direct `dio` dependency.

### Changes

- The debug logger interceptor moved to the end of the interceptor chain. Debug
  output now reflects the final request after every interceptor has run.
  Debug builds only — no effect on release builds.

---
```

- [ ] **Step 5: Bump the package version**

In `pubspec.yaml`, change line 3 from `version: 1.0.5` to:

```yaml
version: 1.1.0
```

- [ ] **Step 6: Verify the whole package**

Run each command and confirm the expected output before moving on:

```bash
flutter pub get      # Expected: exits 0, no dependency changes
flutter analyze      # Expected: "No issues found!"
flutter test         # Expected: all tests pass, zero failures
```

- [ ] **Step 7: Commit**

```bash
git add README.md CHANGELOG.md pubspec.yaml
git commit -m "docs: document custom interceptors and release 1.1.0"
```

---

## Done criteria

- `NetworkConfig(baseUrl: ..., interceptors: [MyInterceptor()])` compiles for a consumer importing only `package:app_smart_network/app_smart_network.dart`.
- `flutter analyze` reports no issues.
- `flutter test` passes, including the pre-existing suite untouched.
- `pubspec.yaml`, `CHANGELOG.md` and the README install snippet all say `1.1.0`.
