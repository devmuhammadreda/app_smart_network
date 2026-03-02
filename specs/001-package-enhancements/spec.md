# Feature Specification: Package Enhancements & Backend-Agnostic Error Handling

**Feature Branch**: `001-package-enhancements`
**Created**: 2026-03-01
**Status**: Draft
**Input**: User description: "give me a plan for upgrade this package and make enhancements in it and enhance error handler to work with any backend and add new features"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Flexible Error Body Parsing (Priority: P1)

A developer integrating the package with a backend that returns errors in a
non-standard format (e.g., `{"errors": [{"field": "email", "msg": "taken"}]}`
or `{"error": {"code": "USER_LOCKED", "detail": "Account suspended"}}`) needs
the package to correctly extract the error message, error code, and validation
errors from whatever structure their server sends — without having to subclass
or fork the package.

The developer registers a single custom error-body parser function once during
app initialization. From that point on, every `ApiException` the package
produces carries the right `message`, `apiErrorCode`, and `validationErrors`
regardless of the response shape, and all locale-translated fallbacks still
apply when the parser returns nothing.

**Why this priority**: Every production app is blocked by this; hardcoded field
names (`message`, `error_code`) make the package unusable out-of-the-box for
teams whose backends do not match those names. This is the single biggest
friction point for adoption.

**Independent Test**: Can be fully tested by initializing the package with a
custom parser, making a request to a mock server that returns a non-standard
error body, and asserting that `ApiException.message`, `ApiException.apiErrorCode`,
and `ApiException.validationErrors` contain the correctly extracted values.

**Acceptance Scenarios**:

1. **Given** no custom parser is registered, **When** a 4xx/5xx response arrives,
   **Then** the existing built-in parsing logic is used unchanged (full backward
   compatibility).
2. **Given** a custom parser is registered, **When** a 4xx/5xx response arrives
   and the parser returns a populated result, **Then** `ApiException` reflects
   the parser's extracted `message`, `apiErrorCode`, and `validationErrors`.
3. **Given** a custom parser is registered, **When** the parser returns null
   (unrecognized format), **Then** the package falls back to the built-in
   parsing logic.
4. **Given** a custom parser throws an exception internally, **When** an error
   response arrives, **Then** the package swallows the parser exception, logs
   it in debug mode, and falls back to built-in parsing without crashing.

---

### User Story 2 - Automatic Token Refresh on 401 (Priority: P2)

A developer building an authenticated app needs the package to silently attempt
a token refresh when the server returns a 401 (Unauthorized) response, retry
the original request with the refreshed token, and only notify the app of an
auth failure if the refresh itself fails. Currently, every 401 immediately calls
`onUnauthorized`, forcing the developer to build the refresh-and-retry loop
themselves outside the package.

**Why this priority**: Auth token expiry is a universal production concern. A
developer who handles token refresh manually across every datasource adds
significant boilerplate and is prone to race conditions when multiple requests
expire simultaneously.

**Independent Test**: Can be fully tested by providing a mock token-refresh
callback and a mock server that returns 401 on the first call and 200 on the
second. Assert that the callback was invoked once, the original request was
retried, and no `ApiException` was thrown.

**Acceptance Scenarios**:

1. **Given** a token-refresh callback is configured, **When** the server returns
   401, **Then** the package calls the refresh callback, applies the new token,
   and retries the original request exactly once.
2. **Given** the refresh callback succeeds and the retry returns 200, **Then**
   the caller receives a successful response as if the 401 never happened.
3. **Given** the refresh callback fails (throws or returns null), **Then** the
   package calls `onUnauthorized` and surfaces an `ApiException` with status 401.
4. **Given** no refresh callback is configured, **When** the server returns 401,
   **Then** the existing `onUnauthorized` behavior is preserved unchanged.
5. **Given** the 401 originates from the refresh endpoint itself, **Then** no
   recursive refresh attempt is made; the package calls `onUnauthorized`
   immediately to prevent an infinite loop.
6. **Given** multiple concurrent requests all return 401 simultaneously, **Then**
   the refresh callback is invoked exactly once; all waiting requests are retried
   after the single refresh completes.

---

### User Story 3 - Custom Request & Response Interceptor Hooks (Priority: P3)

A developer needs to inject custom logic into the request/response lifecycle —
for example, adding a dynamic signature header derived from the request body,
logging requests to an analytics service, or transforming a paginated response
into a flat list — without managing a separate HTTP client alongside the package.

The developer registers one or more named interceptor hooks during initialization.
Each hook receives the request or response in progress and returns a (possibly
modified) version of it.

**Why this priority**: Without interceptor hooks, developers are forced to wrap
every `ApiService` call in their own middleware, defeating the purpose of a
centralized network package.

**Independent Test**: Can be fully tested by registering a request hook that
appends a custom header and a response hook that adds a `_received_at` field to
the body, then asserting both modifications appear in the outgoing request and
the returned response respectively.

**Acceptance Scenarios**:

1. **Given** a request hook is registered, **When** any request is sent,
   **Then** the hook receives the request parameters and its return value is
   used as the final request.
2. **Given** a response hook is registered, **When** any successful response
   arrives, **Then** the hook receives the response data and its return value
   is what the caller receives.
3. **Given** multiple hooks are registered, **When** a request/response passes
   through, **Then** hooks are applied in registration order (pipeline).
4. **Given** a hook throws an exception, **When** a request/response passes
   through, **Then** the exception is wrapped as an `ApiException` and
   propagated to the caller; remaining hooks are skipped.
5. **Given** hooks are registered, **When** `BuildContext` is not available,
   **Then** hooks still execute correctly (no context dependency).

---

### User Story 4 - Request Deduplication (Priority: P4)

A developer building a widget-heavy screen (e.g., a social feed where many
cards simultaneously request the same user profile) needs the package to
recognize when an identical request is already in flight and share its result
with all waiting callers rather than sending duplicate network requests.

**Why this priority**: Deduplication is a bandwidth and latency optimization.
It prevents wasted requests and eliminates race conditions where two responses
for the same resource arrive out of order and overwrite each other.

**Independent Test**: Can be fully tested by firing three identical GET requests
concurrently with deduplication enabled, asserting that only one network request
was sent, and that all three callers received the same response data.

**Acceptance Scenarios**:

1. **Given** deduplication is enabled for a request, **When** two identical
   requests (same method, URL, query parameters) are fired before the first
   completes, **Then** only one network request is sent and both callers receive
   the same response.
2. **Given** deduplication is enabled and a *waiting* caller is cancelled,
   **When** the original in-flight request completes, **Then** the remaining
   waiters still receive the response normally.
3. **Given** deduplication is enabled and the *original in-flight* request is
   cancelled, **When** other callers are still waiting, **Then** the package
   promotes a new network request on their behalf and they complete normally.
4. **Given** deduplication is enabled and the in-flight request fails,
   **Then** all waiting callers receive the same `ApiException`.
5. **Given** deduplication is disabled (default), **Then** all requests are sent
   independently, preserving existing behavior.
6. **Given** two requests have the same URL but different headers (e.g.,
   different auth tokens or tenant IDs), **Then** they are treated as distinct
   requests and both are sent independently.

---

### User Story 5 - Enhanced `ApiException` with Typed Validation Errors (Priority: P5)

A developer handling form validation errors from the server needs to access a
typed, structured list of field-level validation errors from `ApiException`
without calling the generic `getResponseField()` and casting manually. The
current `validationErrors` concept exists but requires raw field access.

**Why this priority**: Validation-error handling is common in every form-heavy
app. A typed accessor reduces boilerplate in every repository that deals with
422 responses.

**Independent Test**: Can be fully tested by sending a request to a mock server
that returns a 422 with a list of field errors, then asserting that
`ApiException.validationErrors` is a non-null, correctly typed list without any
manual casting.

**Acceptance Scenarios**:

1. **Given** a 422 response with a list of field errors, **When** `ApiException`
   is caught, **Then** `validationErrors` contains a typed, iterable list of
   field-error pairs (field name → error message).
2. **Given** the custom error parser (User Story 1) populates validation errors,
   **Then** `validationErrors` reflects the parser's output.
3. **Given** a non-validation error (e.g., 500), **Then** `validationErrors`
   is an empty list, not null, avoiding null-check boilerplate.

---

### User Story 6 - Service Name Alignment with Package Identity (Priority: P3)

A developer discovering the package for the first time opens the documentation
and finds that the entry-point class is called `ApiService` — a generic name
that gives no indication it belongs to the "App Smart Network" package. The
mismatch between the package name and the service name creates confusion,
reduces discoverability, and makes code less self-documenting (e.g., search
results and auto-complete suggestions for `ApiService` are ambiguous across
projects that use multiple network packages).

The package MUST introduce `AppSmartNetworkService` as the canonical, properly
branded entry-point class. `ApiService` MUST be preserved as a deprecated alias
so that existing consumers' code continues to compile without modification.

**Why this priority**: Branding and naming consistency directly impact developer
trust and long-term adoption. Fixing it now, before the package grows a large
consumer base, minimises the migration surface. Sharing P3 priority with
interceptor hooks because it is a cosmetic-but-important change that does not
block core functionality.

**Independent Test**: Can be fully tested by verifying that
`AppSmartNetworkService` exposes every method currently available on
`ApiService`, that calling any method through `AppSmartNetworkService` produces
identical behaviour, and that existing code using `ApiService` compiles and runs
without errors (possibly with deprecation warnings).

**Acceptance Scenarios**:

1. **Given** a developer initialises the package, **When** they write
   `AppSmartNetworkService.initialize(config)`, **Then** it behaves identically
   to the current `ApiService.initialize(config)`.
2. **Given** a developer uses `AppSmartNetworkService.instance`, **When** they
   call any request method, **Then** the result is identical to using
   `ApiService.instance`.
3. **Given** existing code that references `ApiService`, **When** the upgraded
   package is installed, **Then** the code compiles and runs correctly; a
   deprecation notice informs the developer to migrate to
   `AppSmartNetworkService`.
4. **Given** `AppSmartNetworkService` is used for initialization, **When** code
   also accesses `ApiService.instance`, **Then** both references point to the
   same underlying singleton — there is exactly one shared state.
5. **Given** README and public documentation, **When** a developer reads them,
   **Then** `AppSmartNetworkService` is presented as the primary API and
   `ApiService` is noted as a deprecated alias.

---

### Edge Cases

- What happens when the custom error parser is slow or performs async work?
  The package MUST support both synchronous and asynchronous parsers.
- What happens when a token refresh races with an interceptor hook that also
  modifies the `Authorization` header? The refresh result MUST take precedence.
- What happens when deduplication is used with a POST request that mutates
  server state? Deduplication MUST be opt-in and disabled by default for
  non-idempotent methods.
- What happens when an interceptor hook modifies the URL to a different host?
  The per-request `baseUrl` override MUST still apply correctly after hooks run.
- What happens when locale is changed mid-flight (locale set while a request is
  in the air)? The locale active at the time `ApiException` is constructed MUST
  be used for translation.

## Requirements *(mandatory)*

### Functional Requirements

#### Error Handler — Backend-Agnostic Parsing

- **FR-001**: The package MUST provide a configurable error body parser slot in
  `NetworkConfig` that accepts a function receiving the raw response body (any
  type) and HTTP status code, and returning optional structured error data
  (message, error code, validation-error list). The parser MUST be invoked
  only when an actual HTTP response with a body is received (4xx/5xx server
  responses). Network-layer errors (offline, timeout, SSL, DNS) MUST bypass
  the parser and use built-in locale-aware messages directly.
- **FR-002**: The error body parser MUST support both synchronous and asynchronous
  implementations.
- **FR-003**: When the parser returns null or is not registered, the existing
  built-in parsing logic MUST execute as the default, with zero change in
  observable behavior.
- **FR-004**: Parser exceptions MUST be caught, logged in debug mode, and cause
  a graceful fallback to built-in parsing — never a crash.

#### Token Refresh

- **FR-005**: `NetworkConfig` MUST accept an optional token-refresh callback that
  receives the expired response context and returns a refreshed token (or null
  on failure).
- **FR-006**: On a 401 response, if the refresh callback is registered and the
  request is not the refresh endpoint, the package MUST invoke the callback
  exactly once per concurrent 401 burst, then retry all waiting requests.
- **FR-007**: The consumer MUST be able to provide a predicate function
  `(String url) → bool` in `NetworkConfig` that identifies the token-refresh
  endpoint. When the predicate returns `true` for a request's URL, the token-
  refresh flow MUST be skipped for that request to prevent infinite loops.
- **FR-008**: If refresh succeeds, the original request MUST be retried once
  with the new token. If it returns 401 again, `onUnauthorized` is called.
- **FR-009**: If refresh fails, `onUnauthorized` MUST be called and an
  `ApiException` with status 401 MUST be thrown to all waiting callers.
- **FR-024**: The retry interceptor MUST be configured to exclude HTTP 401
  from its retry conditions. Token refresh (FR-005 – FR-009) is the sole
  recovery path for 401 responses; no automatic retry of 401 by the retry
  interceptor is permitted.

#### Custom Interceptor Hooks

- **FR-010**: `NetworkConfig` MUST accept an ordered list of request interceptor
  hooks, each capable of inspecting and modifying request parameters (URL,
  headers, body, query parameters) before the request is sent.
- **FR-011**: `NetworkConfig` MUST accept an ordered list of response interceptor
  hooks, each capable of inspecting and transforming response data before it
  is returned to the caller. Response hooks MUST run exclusively on successful
  (2xx) responses. Error responses (4xx/5xx) MUST bypass the response hook
  pipeline and flow directly to `ErrorHandler` and the custom error parser
  (FR-001).
- **FR-012**: Hooks MUST NOT require a `BuildContext` or any Flutter widget-tree
  reference.
- **FR-013**: An exception thrown by a hook MUST propagate to the caller as an
  `ApiException` and stop the remaining hook pipeline.
- **FR-025**: Request hooks MUST NOT execute on internal retry requests
  triggered by the token-refresh flow. Only the auth token is substituted on
  the retry; all other request parameters remain as originally produced by the
  hook pipeline on the first call.

#### Request Deduplication

- **FR-014**: The package MUST provide an opt-in `deduplicate` flag per request
  that prevents multiple identical in-flight requests from generating multiple
  network calls.
- **FR-015**: Two requests MUST be considered identical when they share the same
  HTTP method, resolved URL, query parameters, and request headers. Requests
  with differing headers (e.g., different `Authorization` or `X-Tenant-ID`
  values) MUST be treated as distinct and both sent independently.
- **FR-016**: Deduplication MUST default to `false`. It MUST NOT be applied
  automatically to requests not explicitly opted in.
- **FR-017**: If the deduplicated in-flight request succeeds, all waiters MUST
  receive the same response data. If it fails, all waiters MUST receive the
  same `ApiException`.
- **FR-030**: If the original in-flight deduplicated request is cancelled by
  its caller and other waiters remain, the package MUST immediately promote a
  new network request on behalf of the waiting callers. The waiting callers
  MUST complete normally as if they had been the original request.

#### Enhanced Validation Error Access

- **FR-018**: `ApiException` MUST expose a `validationErrors` property returning
  a typed, non-null list of field-error pairs when validation errors are present.
- **FR-019**: `validationErrors` MUST be empty (not null) when no validation
  errors are present, eliminating the need for null checks.
- **FR-020**: Validation errors populated by the custom error body parser
  (FR-001) MUST be reflected in `validationErrors`.

#### Service Name Alignment

- **FR-026**: The package MUST introduce `AppSmartNetworkService` as the new
  canonical entry-point class, exposing every public method and property
  currently available on `ApiService` with identical signatures and behaviour.
- **FR-027**: `ApiService` MUST be retained as a deprecated alias that forwards
  all calls to `AppSmartNetworkService`. Existing consumer code MUST continue
  to compile and run without modification; only a deprecation notice is
  permitted as a visible difference.
- **FR-028**: `AppSmartNetworkService` and `ApiService` MUST share a single
  underlying singleton. Initialising via one name and accessing via the other
  MUST yield the same instance and state.
- **FR-029**: All public documentation (README, example app, API reference)
  MUST be updated to use `AppSmartNetworkService` as the primary name, with a
  migration note explaining that `ApiService` is deprecated.

#### General Upgrade Requirements

- **FR-021**: All existing public APIs MUST remain backward-compatible. New
  parameters MUST be optional with sensible defaults. The `ApiService` name is
  preserved as a deprecated alias (see FR-027); it is NOT removed.
- **FR-022**: All new configuration options MUST be expressible in
  `NetworkConfig` at initialization time and, where applicable, overridable
  at runtime via `AppSmartNetworkService.configure()` (formerly
  `ApiService.configure()`).
- **FR-023**: The `CHANGELOG.md` MUST be updated with a full account of new
  APIs and migration guidance before any release.

### Key Entities

- **ErrorBodyParser**: A consumer-provided function that receives a raw response
  body and HTTP status code, and returns optional structured error data
  (message string, error-code string, list of field-level validation errors).
  Falls back to built-in parsing when absent or returning null.
- **TokenRefresher**: A consumer-provided callback that receives the 401
  response context and asynchronously returns a refreshed token string (or
  null to signal failure). Tied to `NetworkConfig`.
- **RequestHook**: A consumer-provided function in an ordered list that receives
  outgoing request parameters and returns (possibly modified) parameters.
  Applied as a pipeline before the request is sent.
- **ResponseHook**: A consumer-provided function in an ordered list that
  receives incoming response data and returns (possibly transformed) data.
  Applied as a pipeline before the response reaches the caller.
- **ValidationError**: A typed pair of `field` (String) and `message` (String)
  representing a single server-side field validation failure. Accessible as a
  list from `ApiException.validationErrors`.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A developer integrating with a new backend whose error format
  differs from the built-in defaults can produce correctly typed `ApiException`
  objects with zero changes to existing catch-block code — only a single parser
  function registered at startup.
- **SC-002**: When auth tokens expire during normal usage, end users MUST NOT
  see an unauthorized error screen if a valid refresh token is available; the
  refresh and retry happen transparently within the same request call.
- **SC-003**: A screen that fires 10 identical simultaneous GET requests with
  deduplication enabled results in exactly 1 network call, measurable via
  network profiling or mock-server invocation count.
- **SC-004**: 100% of existing tests pass after the upgrade with no changes to
  test code (full backward compatibility).
- **SC-005**: `ApiException.validationErrors` is accessible without a cast or
  null check in every scenario where a 422 is returned, reducing validation-
  handling boilerplate to a single `.validationErrors.forEach(...)` call.
- **SC-006**: All new `NetworkConfig` parameters are optional; an app already
  using the package with the current `NetworkConfig` compiles and runs without
  any code changes after the upgrade.
- **SC-007**: Any developer searching for the package entry point by package
  name (`AppSmartNetwork`) finds `AppSmartNetworkService` immediately in
  auto-complete and documentation — no more ambiguous `ApiService` name that
  could belong to any package.

## Assumptions

- The refresh endpoint is identified via a consumer-provided predicate function
  `(String url) → bool`; the package does not attempt to auto-detect it.
- Custom interceptor hooks are registered at initialization time; dynamic
  addition/removal of hooks at runtime is out of scope for this release.
- Deduplication uses an in-memory store; no persistence across app restarts is
  required.
- The package continues to depend only on `dio`, `connectivity_plus`,
  `dio_smart_retry`, and `pretty_dio_logger`; no new third-party dependencies
  will be introduced.
- The `ValidationError` entity is a simple value type (field + message); richer
  structures (nested errors, error codes per field) are out of scope.

## Out of Scope

- Request-level caching (in-memory or disk) — separate feature.
- Pagination helpers or cursor management — separate feature.
- Certificate pinning implementation — consumers supply a custom adapter.
- WebSocket or Server-Sent Events support — out of scope for this package.
- Response body encryption/decryption hooks — out of scope.
- Hard removal of `ApiService` — it is deprecated in this release but not
  deleted; full removal is deferred to a future major version.

## Clarifications

### Session 2026-03-01

- Q: When a 401 is returned, how should the token-refresh callback interact with the existing retry interceptor? → A: Token refresh exclusively owns 401 handling; the retry interceptor MUST NOT retry 401 responses.
- Q: Should request hooks fire again on the token-refresh retry request? → A: No — hooks do NOT re-run on the retry; only the auth token is replaced.
- Q: Should request headers be included in the deduplication identity key? → A: Yes — key = method + URL + query parameters + request headers.
- Q: Should the custom error body parser be invoked for network-layer errors with no HTTP response body? → A: No — parser runs on server responses only (4xx/5xx with a body); network-layer errors bypass the parser.
- Q: How should the consumer identify the token-refresh endpoint in NetworkConfig? → A: Predicate function — consumer provides a `(String url) → bool` function; package skips refresh when the predicate returns true.
- Amendment: Added User Story 6 (Service Name Alignment) — `AppSmartNetworkService` introduced as the canonical entry point; `ApiService` retained as a deprecated alias sharing the same singleton.

### Session 2026-03-01 (round 2)

- Q: Should response hooks also receive error (4xx/5xx) responses before they are converted to ApiException? → A: No — response hooks run on 2xx responses only; error responses go directly to ErrorHandler and the custom parser (FR-001).
- Q: When the original in-flight deduplicated request is cancelled, what happens to waiting callers? → A: Promote a new request — the package sends a new network request on behalf of the remaining waiters, who complete normally.
