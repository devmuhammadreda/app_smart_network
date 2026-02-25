import 'package:equatable/equatable.dart';

import 'exceptions.dart';

// ============================================================================
// FAILURES  (domain-layer wrappers around exceptions)
// ============================================================================

abstract class Failure extends Equatable {
  final String message;
  final int code;
  final String apiErrorCode;

  const Failure({
    required this.message,
    required this.code,
    required this.apiErrorCode,
  });

  @override
  List<Object> get props => [message, code, apiErrorCode];
}

class ServerFailure extends Failure {
  const ServerFailure({
    required super.message,
    required super.code,
    required super.apiErrorCode,
  });

  factory ServerFailure.fromException(ApiException exception) {
    return ServerFailure(
      message: exception.message,
      code: exception.statusCode,
      apiErrorCode: exception.apiErrorCode ?? 'Unknown',
    );
  }
}
