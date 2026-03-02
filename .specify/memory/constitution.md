<!--
=============================================================================
SYNC IMPACT REPORT
=============================================================================
Version change:   (template) → 1.0.0
Bump rationale:   Initial ratification — all placeholders replaced with
                  concrete project values for the first time.

Modified principles:
  [PRINCIPLE_1_NAME] → I. Package Boundary
  [PRINCIPLE_2_NAME] → II. Zero Context Dependency
  [PRINCIPLE_3_NAME] → III. Unified Error Surface
  [PRINCIPLE_4_NAME] → IV. Semantic Versioning & Breaking-Change Discipline
  [PRINCIPLE_5_NAME] → V. Simplicity & Scope Control

Added sections:
  - Security & SSL Standards
  - Development Quality Gates

Removed sections:
  - None (all template sections retained and filled)

Templates requiring updates:
  ✅ .specify/templates/plan-template.md
     Constitution Check gates now reference the five principles above.
     No structural changes needed — existing "Constitution Check" section
     already provides the correct hook; gate content is populated at
     /speckit.plan run time.
  ✅ .specify/templates/spec-template.md
     No structural changes required; scope/requirements guidance aligns
     with Package Boundary and Unified Error Surface principles.
  ✅ .specify/templates/tasks-template.md
     No structural changes required; task categories (setup, foundational,
     user stories, polish) align with the five principles. Observability
     tasks are not a separate phase for this library — logging is a
     cross-cutting concern handled by PrettyDioLogger in the client layer.

Deferred TODOs:
  - None. All placeholders resolved.
=============================================================================
-->

# app_smart_network Constitution

## Core Principles

### I. Package Boundary (NON-NEGOTIABLE)

`app_smart_network` is a **network-layer Flutter package** and MUST remain
exclusively that. The following are prohibited:

- Domain-layer abstractions (e.g., `Failure` types, repository interfaces,
  use-case classes).
- App-specific concerns: routing helpers, cache managers, feature flags,
  or environment-detection beyond `kDebugMode`.
- Hard dependencies on any Flutter widget framework feature beyond what Dio
  and connectivity_plus already require.

Every new feature MUST be self-contained, independently testable, and carry
a clear network-layer purpose. If a proposed addition belongs to the domain
or presentation layer, it MUST be rejected and the consumer directed to
implement it in their own app.

**Rationale**: Scope creep was the root cause of the `ServerFailure` /
`CacheFailure` removal in v1.0.3. Maintaining a strict boundary prevents
forcing unwanted dependencies (e.g., `equatable`) on consumers and keeps
the package composable with any architecture.

### II. Zero Context Dependency

No public API in this package SHALL require a Flutter `BuildContext` (or
any widget-tree reference) at any point in its lifecycle — not for
initialization, not for error messages, not for locale handling.

- Locale management MUST use `NetworkLocale` (map-based, zero-Flutter
  dependency).
- Error messages MUST be produced by `ErrorHandler` using the active locale
  from `NetworkLocale`, not from `AppLocalizations` or any gen-l10n output.
- `ApiService.initialize()` MUST be callable before `runApp()`.

**Rationale**: Context coupling makes the package impossible to use in
background isolates, CLI tools, or integration tests that run outside the
widget tree. It also creates lifecycle ordering problems in `main()`.

### III. Unified Error Surface

All errors thrown by this package MUST be surfaced exclusively as
`ApiException`. No transport-layer exception (`DioException`,
`SocketException`, `HandshakeException`, etc.) SHALL ever propagate to a
consumer's `catch` block.

- `ErrorHandler.handleError()` is the **single choke point**; every code
  path that can fail MUST route through it.
- `ApiException` MUST carry: `statusCode`, `message` (locale-translated),
  `errorCategory`, and optionally `apiErrorCode`.
- Convenience accessors (`isUnauthorized`, `isNotFound`, `isNetworkError`,
  `isValidationError`, `hasApiErrorCode()`, `getResponseField()`) MUST
  remain stable across MINOR versions.

**Rationale**: A uniform exception type lets consumers write a single
`on ApiException catch` block with full diagnostic information, regardless
of whether the failure originated from a timeout, an SSL error, a 4xx
response, or a connectivity drop.

### IV. Semantic Versioning & Breaking-Change Discipline

The package MUST follow [semver](https://semver.org) strictly:

| Change type | Version bump |
| --- | --- |
| Removal or rename of any public symbol | MAJOR |
| New public API or optional parameter added | MINOR |
| Bug fix, clarification, doc update | PATCH |

Every release MUST include a CHANGELOG entry. Breaking changes MUST include
a concrete **migration example** showing before/after code. A release that
removes a public symbol without a MAJOR bump is a constitution violation.

**Rationale**: Consumers pin to `^X.Y.Z`. Unexpected breaks destroy trust
and create support burden. The `ServerFailure` removal in v1.0.3 — a
MAJOR-worthy change shipped as a PATCH — demonstrated the cost of skipping
this discipline.

### V. Simplicity & Scope Control

Features MUST solve a demonstrated consumer need before being added. The
following practices are MANDATORY:

- YAGNI: do not add extensibility hooks, configuration knobs, or helper
  utilities for hypothetical future requirements.
- Do not duplicate functionality already provided by Dio, connectivity_plus,
  or dio_smart_retry without a clear, documented reason.
- Prefer editing existing files over creating new ones.
- Three similar lines of code is preferable to a premature abstraction.

**Rationale**: The package MUST remain lightweight. Every added dependency
and every public symbol is a maintenance obligation for all consumers.

## Security & SSL Standards

- `NetworkConfig.allowBadCertificate` MUST default to `false`.
- Code paths that set `allowBadCertificate: true` MUST be guarded by
  `assert(!kReleaseMode)` or equivalent, and MUST be documented as
  **debug-only**.
- Auth tokens MUST NOT be logged, even in debug builds. `PrettyDioLogger`
  configuration MUST redact the `Authorization` header.
- No SSL pinning implementation is in scope for this package; consumers
  requiring pinning MUST provide a custom `HttpClientAdapter` via
  `NetworkConfig`.

## Development Quality Gates

All pull requests MUST satisfy the following gates before merge:

1. **Principle I (Boundary)**: No new domain-layer or app-specific symbol
   introduced.
2. **Principle II (No Context)**: No `BuildContext` or `State` parameter
   added to any public or internal API.
3. **Principle III (Error Surface)**: Every new code path that can throw
   routes through `ErrorHandler.handleError()`.
4. **Principle IV (Versioning)**: `pubspec.yaml` version and `CHANGELOG.md`
   entry are consistent with the semver rule table above.
5. **Principle V (Simplicity)**: Complexity Tracking table in `plan.md`
   documents any deviation from the simplest possible approach.
6. `flutter analyze` MUST pass with zero errors and zero warnings.
7. All existing tests MUST pass (`flutter test`).
8. Public API additions MUST be reflected in `README.md` with a usage
   example before the PR is merged.

## Governance

This constitution supersedes all other practices and conventions for the
`app_smart_network` package. In the event of a conflict between this
document and any other guideline, this document prevails.

**Amendment procedure**:

1. Open a PR with the proposed constitution change.
2. The PR description MUST state: the principle(s) affected, the version
   bump type (MAJOR/MINOR/PATCH), and the migration impact on consumers.
3. The amendment MUST be approved before any implementing code is merged.
4. After approval, update `LAST_AMENDED_DATE` and `CONSTITUTION_VERSION`
   in this file, and add a note to `CHANGELOG.md`.

**Versioning policy**: Constitution version follows the same semver rules
defined in Principle IV. Adding a new principle or section is a MINOR bump.
Removing or redefining a principle is a MAJOR bump. Wording clarifications
are PATCH bumps.

**Compliance review**: Every `/speckit.plan` run MUST include a
"Constitution Check" gate that verifies the planned feature against all
five principles before Phase 0 research begins. Violations MUST be
documented in the Complexity Tracking table or the feature MUST be
redesigned.

**Version**: 1.0.0 | **Ratified**: 2026-03-01 | **Last Amended**: 2026-03-01
