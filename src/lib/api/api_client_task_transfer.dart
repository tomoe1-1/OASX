part of 'api_client.dart';

extension ApiClientTaskTransferX on ApiClient {
  Future<TaskImportResult> importTaskJson({
    required String configName,
    required String taskName,
    String? jsonText,
    String? filePath,
    Uint8List? fileBytes,
    String? fileName,
  }) async {
    final formData = _DioFormData.fromMap({
      'config_name': configName.trim(),
      'task_name': taskName.trim(),
      if (jsonText != null && jsonText.trim().isNotEmpty)
        'json_text': jsonText.trim(),
      if (filePath != null && filePath.trim().isNotEmpty)
        'file': await _DioMultipartFile.fromFile(
          filePath,
          filename: fileName ?? _fileNameFromPath(filePath),
        )
      else if (fileBytes != null)
        'file': _DioMultipartFile.fromBytes(
          fileBytes,
          filename:
              fileName ?? _defaultTaskExportFileName(configName, taskName),
        ),
    });
    final response = await NetOptions.instance.dio.post<dynamic>(
      '/config/task/import',
      data: formData,
      options: Options(validateStatus: (_) => true),
    );
    final statusCode = _responseStatusCode(response.data, response.statusCode);
    final payload = _responsePayload(response.data);
    if (statusCode == 200) {
      return TaskImportResult.fromJson(_asJsonMap(payload));
    }
    throw ConfigTransferException(
      _configTransferErrorMessage(payload, I18n.taskJsonImportFailed.tr),
      statusCode,
    );
  }

  Future<TaskExportResult> exportTaskJson({
    required String configName,
    required String taskName,
  }) async {
    final response = await NetOptions.instance.dio.get<dynamic>(
      '/config/task/export',
      queryParameters: {'config_name': configName, 'task_name': taskName},
      options: _configNoCacheOptions(responseType: ResponseType.bytes),
    );
    final statusCode = _responseStatusCode(response.data, response.statusCode);
    final payload = _responsePayload(response.data);
    if (statusCode == 200) {
      final bytes = _asBytes(payload);
      if (bytes.isEmpty) {
        throw ConfigTransferException(I18n.taskJsonExportFailed.tr, statusCode);
      }
      return TaskExportResult(
        fileName: _defaultTaskExportFileName(configName, taskName),
        bytes: bytes,
      );
    }
    throw ConfigTransferException(
      _configTransferErrorMessage(payload, I18n.taskJsonExportFailed.tr),
      statusCode,
    );
  }

  Future<dynamic> copyTaskJson({
    required String configName,
    required String taskName,
  }) async {
    final response = await NetOptions.instance.dio.get<dynamic>(
      '/config/task/copy-json',
      queryParameters: {'config_name': configName, 'task_name': taskName},
      options: _configNoCacheOptions(),
    );
    final statusCode = _responseStatusCode(response.data, response.statusCode);
    final payload = _responsePayload(response.data);
    if (statusCode == 200) {
      return payload;
    }
    throw ConfigTransferException(
      _configTransferErrorMessage(payload, I18n.taskJsonCopyFailed.tr),
      statusCode,
    );
  }
}

String _defaultTaskExportFileName(String configName, String taskName) {
  final config = configName.trim().isEmpty ? 'config' : configName.trim();
  final task = taskName.trim().isEmpty ? 'task' : taskName.trim();
  return '$config-$task.json';
}
