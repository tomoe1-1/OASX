part of 'api_client.dart';

extension ApiClientLogsX on ApiClient {
  /// Loads latest or older script log window.
  Future<ScriptLogWindow> getScriptLogWindow(
    String scriptName, {
    String? cursor,
    int limitLines = 500,
    int limitBytes = 262144,
  }) async {
    final query = <String, dynamic>{
      'limit_lines': limitLines,
      'limit_bytes': limitBytes,
    };
    final normalizedCursor = cursor?.trim();
    if (normalizedCursor != null && normalizedCursor.isNotEmpty) {
      query['cursor'] = normalizedCursor;
    }
    final res = await request(
      () => get(
        '/logs/${Uri.encodeComponent(scriptName)}',
        queryParameters: query,
        options: _noCacheOptions(),
      ),
    );
    return ScriptLogWindow.fromJson(_jsonMap(res.data));
  }

  /// Builds script log SSE URI for live tailing.
  Uri buildScriptLogStreamUri(
    String scriptName, {
    String? cursor,
    int limitLines = 200,
    int limitBytes = 131072,
  }) {
    final base = _baseUri();
    final query = <String, String>{
      'limit_lines': limitLines.toString(),
      'limit_bytes': limitBytes.toString(),
    };
    final normalizedCursor = cursor?.trim();
    if (normalizedCursor != null && normalizedCursor.isNotEmpty) {
      query['cursor'] = normalizedCursor;
    }
    return base.replace(
      pathSegments: [
        ...base.pathSegments.where((segment) => segment.isNotEmpty),
        'logs',
        scriptName,
        'stream',
      ],
      queryParameters: query,
    );
  }

  /// Loads one page of error logs.
  Future<ScriptErrorLogList> getScriptErrorLogs({
    String? date,
    String? scriptName,
    int limit = 100,
    String? cursor,
  }) async {
    final query = <String, dynamic>{'limit': limit};
    final normalizedDate = date?.trim();
    if (normalizedDate != null && normalizedDate.isNotEmpty) {
      query['date'] = normalizedDate;
    }
    final normalizedScript = scriptName?.trim();
    if (normalizedScript != null && normalizedScript.isNotEmpty) {
      query['script_name'] = normalizedScript;
    }
    final normalizedCursor = cursor?.trim();
    if (normalizedCursor != null && normalizedCursor.isNotEmpty) {
      query['cursor'] = normalizedCursor;
    }
    final res = await request(
      () => get(
        '/logs/errors',
        queryParameters: query,
        options: _noCacheOptions(),
      ),
    );
    return ScriptErrorLogList.fromJson(_jsonMap(res.data));
  }

  /// Loads one error log detail by id.
  Future<ScriptErrorLogDetail> getScriptErrorLogDetail(
    String errorId, {
    int logLimitBytes = 262144,
  }) async {
    final res = await request(
      () => get(
        '/logs/errors/${Uri.encodeComponent(errorId)}',
        queryParameters: {'log_limit_bytes': logLimitBytes},
        options: _noCacheOptions(),
      ),
    );
    return ScriptErrorLogDetail.fromJson(_jsonMap(res.data));
  }

  /// Downloads one error image as bytes.
  Future<ScriptErrorImageBytes> getScriptErrorImage(
    String errorId,
    String imageName,
  ) async {
    final response = await NetOptions.instance.dio.get<dynamic>(
      '/logs/errors/${Uri.encodeComponent(errorId)}/images/${Uri.encodeComponent(imageName)}',
      options: _noCacheOptions(responseType: ResponseType.bytes),
    );
    final payload = response.data;
    final rawBytes = payload is Map ? payload['data'] : payload;
    final data = rawBytes is List ? rawBytes.cast<int>() : const <int>[];
    return ScriptErrorImageBytes(
      fileName: imageName,
      bytes: Uint8List.fromList(data),
    );
  }

  /// Resolves the absolute image URI for display widgets.
  String buildScriptErrorImageUrl(String errorId, String imageName) {
    final base = _baseUri();
    return base
        .replace(
          pathSegments: [
            ...base.pathSegments.where((segment) => segment.isNotEmpty),
            'logs',
            'errors',
            errorId,
            'images',
            imageName,
          ],
        )
        .toString();
  }

  Options _noCacheOptions({ResponseType? responseType}) {
    final cacheOptions = _cacheOptions.copyWith(policy: CachePolicy.noCache);
    return Options(
      extra: cacheOptions.toExtra(),
      headers: const {'Cache-Control': 'no-cache', 'Pragma': 'no-cache'},
      responseType: responseType,
    );
  }

  Uri _baseUri() {
    final normalized = address.trim().isEmpty
        ? ApiClient._defaultAddress
        : address.trim();
    return Uri.parse(normalized);
  }

  Map<String, dynamic> _jsonMap(dynamic value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return value.cast<String, dynamic>();
    }
    return <String, dynamic>{};
  }
}
