---

description: "Task list for app_smart_network v1.1.0 package enhancements"
---

# Tasks: Package Enhancements & Backend-Agnostic Error Handling

**Input**: Design documents from `/specs/001-package-enhancements/`
**Prerequisites**: plan.md ✅ spec.md ✅ research.md ✅ data-model.md ✅ contracts/ ✅

**Tests**: Not requested in the feature specification. All 23 existing tests
must continue to pass (verified in Polish phase).

**Organization**: Tasks are grouped by user story to enable independent
implementation and testing of each story.

## Format: `[ID] [P?] [Story?] Description`

- **[P]**: Can run in parallel (different files, no incomplete dependencies)
- **[Story]**: User story this task belongs to (US1–US6)
- Exact file paths are included in every task description

## Path Conventions

Library structure (single package):
```
lib/src/              ← source files
lib/app_smart_network.dart  ← public exports
example/lib/          ← example app
test/                 ← existing tests (do not modify)
```

---

## Phase 1: Setup

**Purpose**: Version bump before any code changes so all subsequent commits
are on the correct version.

- [X] T001 Bump `version` field in `pubspec.yaml` from `1.0.3` to `1.1.0`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Shared types and config changes that EVERY user story depends on.
No user-story work can begin until this phase is complete.

**⚠️ CRITICAL**: T002–T005 are independent and can run in parallel.
T006 depends on T002, T003, and T004 completing first.

- [X] T002 [P] Add `class ValidationError { final String field; final String message; const ValidationError({required this.field, required this.message}); }` and add `final List<ValidationError> validationErrors;` field (default `const []`) to `ApiException` constructor in `lib/src/error/exceptions.dart`
- [X] T003 [P] Add five new optional named parameters (`errorBodyParser`, `tokenRefresher`, `refreshEndpointPredicate`, `requestHooks`, `responseHooks`) with defaults to `NetworkConfig`, and add the six new public typedefs (`ErrorBodyParserResult`, `ErrorBodyParser`, `TokenRefreshCallback`, `RefreshEndpointPredicate`, `RequestHook`, `ResponseHook`) in `lib/src/config/network_config.dart`
- [X] T004 [P] Rename class `ApiService` to `AppSmartNetworkService` throughout `lib/src/api_service.dart`; add `@Deprecated('Use AppSmartNetworkService instead. Will be removed in v2.0.0.') typedef ApiService = AppSmartNetworkService;` at the bottom of the same file; update all internal `ApiService` references within the file to `AppSmartNetworkService`
- [X] T005 [P] Add `NetworkConfig get config => _config;` public getter to `HttpClient` by storing `NetworkConfig` as a field `final NetworkConfig _config;` in `lib/src/client/http_client.dart`
- [X] T006 Update `lib/app_smart_network.dart` to export `AppSmartNetworkService` (and keep `ApiService` re-export via `api_service.dart`), `ValidationError`, `ErrorBodyParserResult`, and the five new typedefs (`ErrorBodyParser`, `TokenRefreshCallback`, `RefreshEndpointPredicate`, `RequestHook`, `ResponseHook`)

**Checkpoint**: Foundation ready — all user-story phases can begin after T006 completes.

---

## Phase 3: User Story 1 — Flexible Error Body Parsing (Priority: P1) 🎯 MVP

**Goal**: Consumers register one `errorBodyParser` callback; every `ApiException`
from a server error carries correctly extracted `message`, `apiErrorCode`, and
`validationErrors` regardless of backend format.

**Independent Test**: Initialize the package with a custom parser that reads
`body['error']['detail']` and `body['error']['code']`; send a request to a
mock server returning `{"error":{"code":"LOCKED","detail":"Account locked"}}`;
assert `ApiException.message == "Account locked"` and
`ApiException.apiErrorCode == "LOCKED"`.

### Implementation for User Story 1

- [X] T007 [US1] In `lib/src/error/error_handler.dart` — add private static method `List<ValidationError> _extractValidationErrors(dynamic responseData)` that looks for `errors` key (List of `{field, message}` maps), `error.details` pattern, and other common shapes; update `_handleStatusCodeError()` to call this method and include the result in the `ApiException` constructor via the `validationErrors:` parameter
- [X] T008 [US1] In `lib/src/error/error_handler.dart` — update `_handleStatusCodeError()` to be `async`, accept `ErrorBodyParser? parser` parameter, call `await Future.value(parser?.call(responseData, statusCode))` when the parser is non-null and a response body exists (bypasses parser for network-layer errors); if parser returns a non-null result use its `message`, `apiErrorCode`, and `validationErrors`; if null fall back to `_extractErrorData()` and `_extractValidationErrors()`; wrap parser call in try/catch and log in debug mode on failure
- [X] T009 [US1] In `lib/src/error/error_handler.dart` — update `handleError()` signature to `static Future<Exception> handleError(dynamic error, {ErrorBodyParser? parser})` and make it `async`; update `_handleStatusCodeError()` call to pass `parser`
- [X] T010 [US1] In `lib/src/services/request_service.dart` — update the catch block in `execute()` to `throw await ErrorHandler.handleError(e, parser: _httpClient.config.errorBodyParser)` (replacing the current synchronous call); ensure the `_httpClient.config` getter added in T005 is used here

**Checkpoint**: US1 fully functional and independently testable. Custom error
parsers extract structured data from any backend format.

---

## Phase 4: User Story 2 — Automatic Token Refresh on 401 (Priority: P2)

**Goal**: A 401 response silently triggers the consumer's refresh callback
(exactly once for concurrent 401s), then retries the original request with
the new token. `onUnauthorized` is only called when refresh fails.

**Independent Test**: Configure a mock `tokenRefresher` that returns `"newToken"`;
mock server returns 401 on first call, 200 on second; assert the callback was
invoked once, the original caller receives the 200 response, and no
`ApiException` was thrown.

### Implementation for User Story 2

- [X] T011 [US2] Create `lib/src/interceptors/token_refresh_interceptor.dart` with class `TokenRefreshInterceptor extends Interceptor` that holds `bool _isRefreshing = false` and `Completer<String?>? _refreshCompleter`; in `onError`: skip if not 401 or if `refreshEndpointPredicate?.call(path) == true`; if `_isRefreshing`, await `_refreshCompleter!.future` then retry with new token or call `handler.next(err)` on null; otherwise set `_isRefreshing = true`, create Completer, call `tokenRefresher()`, complete Completer with result, retry original request with new token via `dio.fetch(requestOptions.copyWith(headers: {..., 'Authorization': 'Bearer $newToken'}, extra: {..., '_skipHooks': true}))`, catch failures by completing Completer with null, calling `onUnauthorized?.call()`, and calling `handler.next(err)`; always reset `_isRefreshing = false` in finally
- [X] T012 [US2] In `lib/src/client/http_client.dart` — add `TokenRefreshInterceptor` as the LAST interceptor in `_dio.interceptors.addAll([...])` (after `UnAuthInterceptor`) passing `tokenRefresher: config.tokenRefresher`, `refreshEndpointPredicate: config.refreshEndpointPredicate`, `onUnauthorized: config.onUnauthorized`, and a reference to `_dio`; remove the `UnAuthInterceptor` from the list since `TokenRefreshInterceptor` subsumes its responsibility; import `token_refresh_interceptor.dart`
- [X] T013 [US2] In `lib/src/interceptors/unauth_interceptor.dart` — replace the existing `UnAuthInterceptor` implementation with a deprecated stub that logs a deprecation message in debug mode and calls `handler.next(err)`, preserving the class name for any internal references; add a comment pointing to `TokenRefreshInterceptor`

**Checkpoint**: US2 fully functional. Token expiry is transparent to callers;
concurrent 401s trigger exactly one refresh call.

---

## Phase 5: User Story 3 — Custom Request & Response Hooks (Priority: P3)

**Goal**: Consumers register ordered hook pipelines; every outgoing request
passes through request hooks before being sent; every successful (2xx) response
passes through response hooks before being returned to the caller.

**Independent Test**: Register a request hook that appends header
`X-Custom: test` and a response hook that adds `_ts` key to body; send any
GET request; assert the sent request contained the header and the returned
response data contains the `_ts` key.

### Implementation for User Story 3

- [X] T014 [US3] Create `lib/src/interceptors/hooks_interceptor.dart` with class `HooksInterceptor extends Interceptor` that holds `final List<RequestHook> requestHooks` and `final List<ResponseHook> responseHooks`; in `onRequest`: if `options.extra['_skipHooks'] == true` call `handler.next(options)` immediately, else run each hook sequentially via `options = await Future.value(hook(options))` and catch exceptions by calling `handler.reject(DioException(requestOptions: options, error: e))`; in `onResponse`: if status is NOT 2xx call `handler.next(response)`, else run each response hook sequentially via `response = await Future.value(hook(response))` and catch exceptions by calling `handler.reject(DioException(requestOptions: response.requestOptions, error: e))`
- [X] T015 [US3] In `lib/src/client/http_client.dart` — add `HooksInterceptor` as the FIRST entry in `_dio.interceptors.addAll([...])` (before `RetryInterceptor`), passing `requestHooks: config.requestHooks` and `responseHooks: config.responseHooks`; import `hooks_interceptor.dart`

**Checkpoint**: US3 fully functional. Request hooks modify outgoing requests;
response hooks transform 2xx responses; neither re-runs on token-refresh retries.

---

## Phase 6: User Story 6 — Service Name Alignment (Priority: P3)

**Goal**: `AppSmartNetworkService` is the canonical, documented entry point;
`ApiService` shows a deprecation warning at every call site; documentation and
example app reflect the new name.

**Note**: The core implementation (class rename + typedef) was completed in
Phase 2, T004. This phase covers documentation and example updates only.

**Independent Test**: Open the example app; compile with zero errors; verify
IDE shows a deprecation warning on every `ApiService` usage; verify
`AppSmartNetworkService.instance` is accessible and functional.

### Implementation for User Story 6

- [X] T016 [P] [US6] Update `lib/src/api_service.dart` — revise the class-level doc comment to present `AppSmartNetworkService` as the primary name with a code sample using `AppSmartNetworkService.initialize()`; add a `@Deprecated` annotation doc note explaining the `ApiService` typedef alias
- [X] T017 [P] [US6] Update `README.md` — replace all `ApiService` occurrences with `AppSmartNetworkService` in code examples; add a "Migration from v1.0.3" section after the Setup section noting `ApiService` is deprecated and showing the one-line rename
- [X] T018 [P] [US6] Update `example/lib/main.dart` and `example/lib/src/datasources/posts_datasource.dart` — replace every `ApiService` reference with `AppSmartNetworkService`

**Checkpoint**: US6 fully documented. New and existing developers encounter
`AppSmartNetworkService` as the primary name in all materials.

---

## Phase 7: User Story 4 — Request Deduplication (Priority: P4)

**Goal**: Requests with `deduplicate: true` sharing the same method, URL,
query parameters, and headers share a single in-flight network call; waiting
callers receive the same result; if the original is cancelled and waiters
remain, a new request is promoted automatically.

**Independent Test**: Fire three identical `deduplicate: true` GET requests
concurrently; assert only one network call was made (via `PrettyDioLogger`
output or mock-server hit count); all three callers receive identical response
data.

### Implementation for User Story 4

- [X] T019 [US4] In `lib/src/services/request_service.dart` — add private class `_DeduplicationEntry { final Completer<Response<dynamic>> completer; int waiterCount; CancelToken cancelToken; _DeduplicationEntry({required this.completer, required this.cancelToken}) : waiterCount = 0; }` and field `final Map<String, _DeduplicationEntry> _pendingRequests = {};`
- [X] T020 [US4] In `lib/src/services/request_service.dart` — add private method `String _buildDeduplicationKey(String method, String url, Map<String,dynamic>? query, Map<String,dynamic>? headers)` that sorts entries and returns `'$method|$url|$sortedQuery|$sortedHeaders'`; update `execute()` to accept `bool deduplicate = false` parameter; when `deduplicate` is true: compute key, if key exists in `_pendingRequests` increment `waiterCount` and `await entry.completer.future` then return result or rethrow; otherwise create entry, add to map, call `_doRequest()` in try/catch/finally; on success complete completer; on `RequestCancelledException` if `entry.waiterCount > 0` re-issue the request with a fresh `CancelToken` and complete from the new result; on other errors complete with error; always remove from map in finally
- [X] T021 [US4] In `lib/src/api_service.dart` — add `bool deduplicate = false` named parameter to `AppSmartNetworkService.request()` and pass it through to `_requestService.execute(... deduplicate: deduplicate)`

**Checkpoint**: US4 fully functional. Concurrent identical requests share one
network call; cancelling the original promotes a new request for waiters.

---

## Phase 8: User Story 5 — Typed Validation Errors (Priority: P5)

**Goal**: `ApiException.validationErrors` is a non-null typed list of
`ValidationError` objects for 422 responses, extractable without casting.

**Note**: `ValidationError` was added in T002 (Foundational) and
`ApiException.validationErrors` field was added in T002. Extraction logic was
added in T007 (US1). This phase verifies the full integration.

**Independent Test**: Send a POST to a mock server returning HTTP 422 with
body `{"errors":[{"field":"email","message":"already taken"}]}`; catch the
`ApiException`; assert `e.validationErrors.length == 1`,
`e.validationErrors.first.field == "email"`, and
`e.validationErrors.first.message == "already taken"` — with zero manual
casting.

### Implementation for User Story 5

- [X] T022 [US5] In `lib/src/error/error_handler.dart` — confirm the `ApiException(...)` constructor call in `_handleStatusCodeError()` passes `validationErrors: validationErrors` (where `validationErrors` is the result of `_extractValidationErrors(responseData)` merged with any parser-provided list); ensure parser-supplied `validationErrors` take precedence over built-in extraction when both are non-empty; if neither produces results the field defaults to `const []`

**Checkpoint**: US5 fully functional. `ApiException.validationErrors` is always
non-null, typed, and requires no casting.

---

## Phase N: Polish & Cross-Cutting Concerns

**Purpose**: Documentation, analysis verification, and final quality gates.

- [X] T023 [P] Add `v1.1.0` entry to `CHANGELOG.md` documenting: all new public symbols (`AppSmartNetworkService`, `ValidationError`, `ErrorBodyParser`, `ErrorBodyParserResult`, `TokenRefreshCallback`, `RefreshEndpointPredicate`, `RequestHook`, `ResponseHook`, `ApiException.validationErrors`, `request(deduplicate:)`), the deprecation of `ApiService`, and a migration example for each new feature
- [X] T024 [P] Run `flutter analyze` from the repository root and resolve any errors or warnings introduced by the changes in this feature branch (zero warnings target)
- [X] T025 Run `flutter test` from the repository root and confirm all 23 existing tests pass without modification

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — start immediately
- **Foundational (Phase 2)**: Depends on Phase 1 — BLOCKS all user stories
- **US1 (Phase 3)**: Depends on Phase 2 — no dependency on other user stories
- **US2 (Phase 4)**: Depends on Phase 2 — no dependency on US1 or US3
- **US3 (Phase 5)**: Depends on Phase 4 (shares `http_client.dart` edits — must apply sequentially)
- **US6 (Phase 6)**: Depends on Phase 2 (T004 done) — can run parallel with US3/US4
- **US4 (Phase 7)**: Depends on Phase 2 and Phase 3 (T010 uses async ErrorHandler)
- **US5 (Phase 8)**: Depends on Phase 3 (T007/T008 provide extraction logic)
- **Polish (Phase N)**: Depends on all user stories completing

### User Story Dependencies

- **US1 (P1)**: Starts after Foundational — no story dependencies
- **US2 (P2)**: Starts after Foundational — no story dependencies
- **US3 (P3)**: Starts after US2 completes (both modify `http_client.dart`)
- **US6 (P3)**: Starts after Foundational (T004) — no other story dependencies
- **US4 (P4)**: Starts after US1 completes (depends on async ErrorHandler from T009)
- **US5 (P5)**: Starts after US1 completes (depends on extraction logic from T007)

### Within Each User Story

- Models/types before services
- Services before integration
- Complete each story before verifying independently

### Parallel Opportunities

```bash
# Phase 2 — run all four foundational tasks in parallel:
Task T002: "Add ValidationError and update ApiException in exceptions.dart"
Task T003: "Add typedefs and fields to NetworkConfig in network_config.dart"
Task T004: "Rename ApiService → AppSmartNetworkService in api_service.dart"
Task T005: "Add config getter to HttpClient in http_client.dart"
# Then T006 after all four complete.

# Phase 6 (US6) — all three tasks target different files:
Task T016: "Update api_service.dart docstring"
Task T017: "Update README.md"
Task T018: "Update example/ app files"

# Phase N — analysis and test can run together after T023:
Task T024: "flutter analyze"
Task T025: "flutter test"
```

---

## Implementation Strategy

### MVP First (US1 Only)

1. Complete Phase 1: Setup (T001)
2. Complete Phase 2: Foundational (T002–T006) — **CRITICAL, blocks all stories**
3. Complete Phase 3: US1 — Flexible Error Body Parsing (T007–T010)
4. **STOP and VALIDATE**: Use the US1 independent test to confirm custom parsers work
5. Package is immediately more useful for teams with non-standard backend formats

### Incremental Delivery

1. Setup + Foundational → base ready
2. Add US1 → validate independently → most impactful enhancement shipped
3. Add US2 → validate independently → token refresh works transparently
4. Add US3 → validate independently → hook pipelines functional
5. Add US6 → validate independently → `AppSmartNetworkService` is live
6. Add US4 → validate independently → deduplication verified
7. Add US5 → validate independently → typed validation errors confirmed
8. Polish → CHANGELOG, analyze, test → ship v1.1.0

### Solo Developer Strategy

Work sequentially in priority order:

```
Phase 1 → Phase 2 → Phase 3 (US1 MVP) → Phase 4 (US2) →
Phase 5 (US3) → Phase 6 (US6) → Phase 7 (US4) →
Phase 8 (US5) → Polish
```

---

## Notes

- `[P]` tasks in Phase 2 target different files — safe to run in parallel
- US3 (Phase 5) must follow US2 (Phase 4) because both modify `http_client.dart`
- US5 has no unique implementation tasks — fully served by Foundational + US1
- US6 core rename (T004) is Foundational; Phases 6 is documentation only
- `flutter analyze` MUST pass before merging (zero errors, zero warnings)
- Commit after each Phase checkpoint so rollback is easy if needed
- No existing test files should be modified — all 23 tests must pass as-is
