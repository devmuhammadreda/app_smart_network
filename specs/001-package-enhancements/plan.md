# Implementation Plan: Package Enhancements & Backend-Agnostic Error Handling

**Branch**: `001-package-enhancements` | **Date**: 2026-03-01 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/001-package-enhancements/spec.md`

## Summary

Upgrade `app_smart_network` from v1.0.3 to v1.1.0 (MINOR — all changes are
additive). Six enhancements are delivered in priority order:

1. **Flexible Error Body Parsing** — consumer-supplied async parser replaces
   hardcoded field-name extraction in `ErrorHandler`, making the package work
   with any backend error format out of the box.
2. **Automatic Token Refresh on 401** — a new `TokenRefreshInterceptor` queues
   concurrent 401s, calls the consumer's refresh callback exactly once, then
   retries all waiting requests with the new token.
3. **Custom Request / Response Interceptor Hooks** — a `HooksInterceptor` runs
   ordered consumer-provided pipelines before sending and after receiving
   (success only).
4. **Request Deduplication** — opt-in per-request flag; `RequestService` tracks
   in-flight requests by a composite key and shares a single `Completer` with
   all duplicate callers.
5. **Typed Validation Errors** — `ApiException.validationErrors` exposes a
   non-null `List<ValidationError>` without any manual casting.
6. **Service Name Alignment** — `AppSmartNetworkService` introduced as the
   canonical entry-point class; `ApiService` preserved as a `@deprecated`
   typedef alias sharing the same singleton.

**Version bump**: `1.0.3` → `1.1.0` (MINOR — new public API, no removals).

## Technical Context

**Language/Version**: Dart ^3.0.0 (records, pattern matching, FutureOr)
**Flutter**: ≥ 3.0.0
**Primary Dependencies**: dio ^5.9.1, connectivity_plus ^7.0.0,
  dio_smart_retry ^7.0.1, pretty_dio_logger ^1.4.0 (no new deps added)
**Storage**: N/A — in-memory `Map` for deduplication only; cleared on completion
**Testing**: flutter_test (built-in SDK), existing test/app_smart_network_test.dart
**Target Platform**: Flutter — iOS, Android, Web, Desktop
**Project Type**: Flutter library package (pub.dev)
**Performance Goals**: Zero overhead on 2xx happy path; deduplication key
  computation sub-millisecond (string concatenation + hashCode, no crypto)
**Constraints**: No new third-party dependencies; all new `NetworkConfig`
  parameters optional; no `BuildContext`; backward-compatible public API
**Scale/Scope**: 11 source files → 13 after changes (~2 new interceptor files)

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

### Pre-Phase-0 Evaluation

| Principle | Check | Result |
|---|---|---|
| I. Package Boundary | All new symbols are network-layer only. `ValidationError` is a data class for error info (no domain logic). No routing, cache manager, or Failure type added. | ✅ PASS |
| II. Zero Context Dependency | All callbacks (`ErrorBodyParser`, `TokenRefreshCallback`, hooks) receive raw Dart types. No `BuildContext` parameter anywhere. | ✅ PASS |
| III. Unified Error Surface | Hook exceptions → `ErrorHandler.handleError()`. Token refresh failure → `ApiException(401)`. Parser exceptions → caught, fallback to built-in. | ✅ PASS |
| IV. Semver | Only new optional params and new classes added. `ApiService` deprecated (not removed). Version bumped 1.0.3 → 1.1.0. CHANGELOG required. | ✅ PASS |
| V. Simplicity | All features solve demonstrated consumer needs. No new dependencies. Deduplication uses in-memory Map — simplest correct implementation. Two new files justified in Complexity Tracking. | ✅ PASS |
| Security/SSL | Auth token NOT passed to parser. `PrettyDioLogger` header-redaction is an existing responsibility — no regression. | ✅ PASS |

**Gate result: ALL PASS — research may proceed.**

### Post-Phase-1 Re-evaluation

No violations introduced during design. Interceptor ordering preserves the
unified error surface (all errors funnel through `ErrorHandler`).

## Project Structure

### Documentation (this feature)

```text
specs/001-package-enhancements/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/
│   └── public-api.md    # Phase 1 output – new public API surface
└── tasks.md             # Phase 2 output (/speckit.tasks command)
```

### Source Code Changes (repository root)

```text
lib/
├── app_smart_network.dart          # Updated: new exports
└── src/
    ├── api_service.dart            # Updated: class renamed to AppSmartNetworkService
    │                               # + @deprecated typedef ApiService = AppSmartNetworkService
    ├── config/
    │   └── network_config.dart     # Updated: 5 new optional fields + 4 new typedefs
    ├── error/
    │   ├── exceptions.dart         # Updated: ValidationError class + validationErrors on ApiException
    │   └── error_handler.dart      # Updated: async parser support + validationErrors extraction
    ├── interceptors/
    │   ├── unauth_interceptor.dart # Replaced: now re-exports TokenRefreshInterceptor (deprecated wrapper)
    │   └── token_refresh_interceptor.dart  # NEW: 401 handling + concurrent-refresh serialization
    ├── client/
    │   └── http_client.dart        # Updated: new interceptors added, interceptor ordering revised
    └── services/
        ├── request_service.dart    # Updated: deduplicate param + DeduplicationManager
        └── hooks_interceptor.dart  # NEW (in interceptors/): request + response hook pipeline
```

Note: `hooks_interceptor.dart` is placed under `src/interceptors/` to remain
consistent with the existing interceptor organisation pattern.

**Structure Decision**: Single-package Flutter library. All changes are
additive modifications to existing files plus two justified new interceptor
files. No new top-level directories required.

## Complexity Tracking

> Filled because two new source files are created (deviation from "prefer
> editing existing files").

| Deviation | Why Needed | Simpler Alternative Rejected Because |
|---|---|---|
| `token_refresh_interceptor.dart` (new file) | Token refresh logic involves concurrent-request serialisation with a `Completer`, retry-with-new-token, and loop-prevention — far too large for `unauth_interceptor.dart` or `http_client.dart` without making them untestable | Inlining in `http_client.dart` would make that file >300 lines and mix infrastructure setup with auth flow logic; inlining in `unauth_interceptor.dart` would break its single-responsibility |
| `hooks_interceptor.dart` (new file) | `HooksInterceptor` is a Dio `Interceptor` subclass that owns the hook pipeline state; it cannot be inlined as a lambda | Inline anonymous interceptors cannot hold typed hook lists or be unit-tested in isolation |
