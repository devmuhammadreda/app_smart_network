import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';

import '../client/http_client.dart';
import '../error/error_handler.dart';
import '../mixins/network_service_mixin.dart';

// ============================================================================
// UPLOAD SERVICE
// ============================================================================

class UploadRequestService with NetworkServiceMixin {
  final HttpClient _client;

  @override
  final Connectivity connectivity;

  UploadRequestService(this._client, {Connectivity? connectivity})
      : connectivity = connectivity ?? Connectivity();

  Future<Response<T>> execute<T>(
    String path,
    File file, {
    String fieldName = 'file',
    String? fileName,
    Map<String, dynamic>? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    ProgressCallback? onSendProgress,
    String? baseUrl,
  }) async {
    final conn = await ensureConnected();
    final opts = withMobileTimeouts(options, conn);
    final url = resolveUrl(path, baseUrl);

    try {
      final formData = FormData();

      formData.files.add(
        MapEntry(
          fieldName,
          await MultipartFile.fromFile(
            file.path,
            filename: fileName ?? file.path.split('/').last,
          ),
        ),
      );

      data?.forEach(
        (key, value) => formData.fields.add(MapEntry(key, value.toString())),
      );

      return await _client.dio.post<T>(
        url,
        data: formData,
        queryParameters: queryParameters,
        options: opts,
        cancelToken: cancelToken,
        onSendProgress: (s, t) => handleProgress(s, t, onSendProgress),
      );
    } catch (e) {
      throw ErrorHandler.handleError(e);
    }
  }
}
