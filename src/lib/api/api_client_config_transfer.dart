part of 'api_client.dart';

typedef _DioFormData = FormData;
typedef _DioMultipartFile = MultipartFile;

extension ApiClientConfigTransferX on ApiClient {
  Future<ConfigImportResult> importConfig(String name, String filePath) async {
    final formData = _DioFormData.fromMap({
      'name': name.trim(),
      'file': await _DioMultipartFile.fromFile(
        filePath,
        filename: _fileNameFromPath(filePath),
      ),
    });
    final response = await NetOptions.instance.dio.post<dynamic>(
      '/config/import',
      data: formData,
      options: Options(validateStatus: (_) => true),
    );
    final statusCode = _responseStatusCode(response.data, response.statusCode);
    final payload = _responsePayload(response.data);
    if (statusCode == 200) {
      return ConfigImportResult.fromJson(_asJsonMap(payload));
    }
    throw ConfigTransferException(
      _configTransferErrorMessage(payload, I18n.configImportFailed.tr),
      statusCode,
    );
  }

  Future<ConfigExportResult> exportConfig(String name) async {
    final response = await NetOptions.instance.dio.get<dynamic>(
      '/config/export',
      queryParameters: {'name': name},
      options: _configNoCacheOptions(responseType: ResponseType.bytes),
    );
    final statusCode = _responseStatusCode(response.data, response.statusCode);
    final payload = _responsePayload(response.data);
    if (statusCode == 200) {
      final bytes = _asBytes(payload);
      if (bytes.isEmpty) {
        throw ConfigTransferException(I18n.configExportFailed.tr, statusCode);
      }
      return ConfigExportResult(
        fileName: _defaultConfigExportFileName(name),
        bytes: bytes,
      );
    }
    throw ConfigTransferException(
      _configTransferErrorMessage(payload, I18n.configExportFailed.tr),
      statusCode,
    );
  }
}

Options _configNoCacheOptions({ResponseType? responseType}) {
  final cacheOptions = ApiClient()._cacheOptions.copyWith(
    policy: CachePolicy.noCache,
  );
  return Options(
    extra: cacheOptions.toExtra(),
    headers: const {'Cache-Control': 'no-cache', 'Pragma': 'no-cache'},
    responseType: responseType,
    validateStatus: (_) => true,
  );
}

int? _responseStatusCode(dynamic responseData, int? fallback) {
  if (responseData is Map && responseData['code'] is int) {
    return responseData['code'] as int;
  }
  return fallback;
}

dynamic _responsePayload(dynamic responseData) {
  if (responseData is Map && responseData.containsKey('data')) {
    return responseData['data'];
  }
  return responseData;
}

Map<String, dynamic> _asJsonMap(dynamic value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return value.cast<String, dynamic>();
  }
  return <String, dynamic>{};
}

Uint8List _asBytes(dynamic value) {
  if (value is Uint8List) {
    return value;
  }
  if (value is List<int>) {
    return Uint8List.fromList(value);
  }
  if (value is List) {
    return Uint8List.fromList(value.cast<int>());
  }
  return Uint8List(0);
}

String _configTransferErrorMessage(dynamic payload, String fallback) {
  if (payload is Map) {
    final detail = payload['detail'];
    final message = payload['message'];
    final detailMessage = detail is Map ? detail['message'] : null;
    final fields = detail is Map ? detail['fields'] : null;
    final base = detailMessage ?? message ?? detail;
    final fieldSummary = _fieldErrorSummary(fields);
    if (base != null && base.toString().trim().isNotEmpty) {
      return fieldSummary.isEmpty ? base.toString() : '$base: $fieldSummary';
    }
  }
  if (payload != null && payload.toString().trim().isNotEmpty) {
    return payload.toString();
  }
  return fallback;
}

String _fieldErrorSummary(dynamic fields) {
  if (fields is! List || fields.isEmpty) {
    return '';
  }
  return fields
      .take(3)
      .map((field) {
        if (field is Map) {
          final name = field['field']?.toString() ?? '';
          final message = field['message']?.toString() ?? '';
          return [name, message].where((e) => e.isNotEmpty).join(' ');
        }
        return field.toString();
      })
      .join('; ');
}

String _fileNameFromPath(String path) {
  final segments = path.split(RegExp(r'[\\/]'));
  return segments.isEmpty ? path : segments.last;
}

String _defaultConfigExportFileName(String name) {
  final normalized = name.trim().isEmpty ? 'config' : name.trim();
  return normalized.toLowerCase().endsWith('.json')
      ? normalized
      : '$normalized.json';
}
