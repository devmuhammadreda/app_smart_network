/// A smart Flutter network package built on [Dio] with:
/// - Automatic retry (idempotent methods only)
/// - Connectivity check before every request
/// - Extended receive-timeout on mobile networks
/// - Built-in locale-aware error messages (English & Arabic)
/// - Custom error body parsing (v1.1.0)
/// - Automatic token refresh on 401 (v1.1.0)
/// - Request / response hooks (v1.1.0)
/// - Request deduplication (v1.1.0)
/// - Typed validation errors (v1.1.0)
/// - Isolated upload / download services
library;

// Core service
export 'src/api_service.dart';
export 'src/api_service.dart' show HttpMethod;

// Configuration
export 'src/config/network_config.dart';

// Locale / i18n
export 'src/i18n/network_locale.dart';

// Errors
export 'src/error/error_handler.dart';
export 'src/error/exceptions.dart';

// Re-export frequently used Dio types so consumers don't need a direct
// dependency on `dio` for common operations.
export 'package:dio/dio.dart'
    show
        Response,
        Options,
        CancelToken,
        Headers,
        ProgressCallback,
        FormData,
        MultipartFile,
        RequestOptions;
