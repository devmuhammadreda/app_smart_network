import 'package:dio/dio.dart';
import 'package:dio_smart_retry/dio_smart_retry.dart'
    show defaultRetryableStatuses;

/// Key under which a per-request [RetryPolicy] travels on `Options.extra`.
///
/// `extra` is the only channel Dio carries from the call site down to an
/// interceptor's `onError`, so it is how a single request overrides the
/// policy configured on `NetworkConfig`.
const _kRetryPolicyKey = 'app_smart_network.retry_policy';

/// HTTP methods that are safe to replay automatically.
const kIdempotentMethods = <String>{'GET', 'PUT', 'DELETE', 'HEAD', 'OPTIONS'};

/// Backoff applied between attempts when nothing else is configured.
const kDefaultRetryDelays = <Duration>[
  Duration(seconds: 1),
  Duration(seconds: 2),
  Duration(seconds: 3),
];

/// How a failed request should be retried.
///
/// Set one on `NetworkConfig.retry` to establish the app-wide default, and
/// pass one to an individual call to override it:
///
/// ```dart
/// // App-wide: three retries on idempotent methods (the default).
/// ApiService.initialize(NetworkConfig(
///   baseUrl: 'https://api.example.com',
///   retry: const RetryPolicy(), // `retry: null` turns retry off everywhere
/// ));
///
/// // Per request.
/// await api.request(HttpMethod.post, '/pay', retry: RetryPolicy.off);
/// await api.request(
///   HttpMethod.post,
///   '/sync',
///   retry: const RetryPolicy(attempts: 5),
/// );
/// ```
///
/// **Two fields apply only to the app-wide policy** and are ignored on a
/// policy passed to a single request:
///
/// - [delays] — the backoff schedule is fixed when the client is built and
///   cannot vary per request.
/// - [methods] — the allowlist guards calls that did *not* ask for anything.
///   Attaching a policy to a request is itself the statement that the call is
///   safe to replay, so the allowlist is bypassed there. Without this rule,
///   `retry: RetryPolicy(attempts: 5)` on a POST would silently do nothing.
class RetryPolicy {
  /// Retries attempted *after* the first try. `0` disables retry.
  ///
  /// A value of `3` means up to four requests in total.
  final int attempts;

  /// Backoff between attempts. An empty list retries immediately.
  ///
  /// When [attempts] exceeds the number of entries the last one repeats, so
  /// `attempts: 5` with `[1s, 2s, 3s]` waits 1, 2, 3, 3, 3 seconds.
  ///
  /// App-wide policies only — ignored per request.
  final List<Duration> delays;

  /// Methods eligible for retry when a request does not carry its own policy.
  ///
  /// App-wide policies only — ignored per request.
  final Set<String> methods;

  /// Response status codes treated as retryable.
  ///
  /// Transport failures (timeouts, connection errors) are retried regardless
  /// of this set; cancellations and malformed payloads never are.
  final Set<int> statuses;

  const RetryPolicy({
    this.attempts = 3,
    this.delays = kDefaultRetryDelays,
    this.methods = kIdempotentMethods,
    this.statuses = defaultRetryableStatuses,
  })  : assert(attempts >= 0, 'attempts cannot be negative'),
        assert(
          attempts <= maxAttempts,
          'attempts cannot exceed RetryPolicy.maxAttempts',
        );

  /// Ceiling on [attempts], enforced by the client's retry interceptor.
  static const int maxAttempts = 10;

  /// A policy that never retries. Pass it to a single call to opt out.
  static const RetryPolicy off = RetryPolicy(attempts: 0);

  RetryPolicy copyWith({
    int? attempts,
    List<Duration>? delays,
    Set<String>? methods,
    Set<int>? statuses,
  }) {
    return RetryPolicy(
      attempts: attempts ?? this.attempts,
      delays: delays ?? this.delays,
      methods: methods ?? this.methods,
      statuses: statuses ?? this.statuses,
    );
  }
}

/// Returns [base] carrying [policy], leaving the caller's object untouched.
///
/// Returns [base] itself when [policy] is `null`, so a call that says nothing
/// about retry falls through to the app-wide policy.
Options attachRetryPolicy(Options base, RetryPolicy? policy) {
  if (policy == null) return base;
  return base.copyWith(extra: {...?base.extra, _kRetryPolicyKey: policy});
}

/// Decides whether [error] should be retried on its [attempt].
///
/// [globalPolicy] is the app-wide policy; a policy attached to the request
/// itself takes precedence and, being explicit, also bypasses
/// [RetryPolicy.methods].
bool evaluateRetry(
  DioException error,
  int attempt,
  RetryPolicy? globalPolicy,
) {
  final perRequest = error.requestOptions.extra[_kRetryPolicyKey];
  final policy = perRequest is RetryPolicy ? perRequest : globalPolicy;

  if (policy == null || policy.attempts == 0) return false;
  if (attempt > policy.attempts) return false;

  if (perRequest is! RetryPolicy) {
    final method = error.requestOptions.method.toUpperCase();
    if (!policy.methods.contains(method)) return false;
  }

  if (error.type == DioExceptionType.badResponse) {
    final statusCode = error.response?.statusCode;
    // A bad response with no status code is treated as retryable, matching
    // dio_smart_retry's DefaultRetryEvaluator.
    return statusCode == null || policy.statuses.contains(statusCode);
  }

  // Transport-level failure: retry unless the caller cancelled or the payload
  // was malformed, neither of which a second attempt would fix.
  return error.type != DioExceptionType.cancel &&
      error.error is! FormatException;
}
