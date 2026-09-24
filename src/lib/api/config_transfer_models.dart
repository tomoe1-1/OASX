import 'dart:typed_data';

class ConfigImportResult {
  const ConfigImportResult({required this.name, required this.file});

  final String name;
  final String file;

  factory ConfigImportResult.fromJson(Map<String, dynamic> json) {
    return ConfigImportResult(
      name: json['name']?.toString() ?? '',
      file: json['file']?.toString() ?? '',
    );
  }
}

class ConfigExportResult {
  const ConfigExportResult({required this.fileName, required this.bytes});

  final String fileName;
  final Uint8List bytes;
}

class TaskImportResult {
  const TaskImportResult({
    required this.configName,
    required this.taskName,
    required this.file,
    required this.updated,
  });

  final String configName;
  final String taskName;
  final String file;
  final bool updated;

  factory TaskImportResult.fromJson(Map<String, dynamic> json) {
    return TaskImportResult(
      configName: json['config_name']?.toString() ?? '',
      taskName: json['task_name']?.toString() ?? '',
      file: json['file']?.toString() ?? '',
      updated: json['updated'] == true,
    );
  }
}

class TaskExportResult {
  const TaskExportResult({required this.fileName, required this.bytes});

  final String fileName;
  final Uint8List bytes;
}

class ConfigTransferException implements Exception {
  const ConfigTransferException(this.message, [this.code]);

  final String message;
  final int? code;

  @override
  String toString() => message;
}
