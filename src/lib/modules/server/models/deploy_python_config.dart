import 'dart:io';

import 'package:yaml/yaml.dart';

/// Python executable settings read from the OAS deploy YAML file.
class DeployPythonConfig {
  /// Creates a deploy Python config snapshot.
  const DeployPythonConfig({required this.pythonExecutable});

  /// Python executable path configured for installer execution.
  final String pythonExecutable;

  /// Reads deploy Python settings from the OAS root path.
  factory DeployPythonConfig.read(String rootPath) {
    final file = File('$rootPath\\config\\deploy.yaml');
    final yaml = loadYaml(file.readAsStringSync());
    final python = _pythonSection(yaml);

    return DeployPythonConfig(
      pythonExecutable: _stringValue(
        python['PythonExecutable'],
        '.\\toolkit\\python.exe',
      ),
    );
  }

  /// Absolute python.exe path used to run the installer.
  String getPythonPath(String rootPath) {
    return _resolveExecutable(rootPath, pythonExecutable, 'python.exe');
  }

  /// Absolute pythonw.exe path beside the configured Python executable.
  String getPythonwPath(String rootPath) {
    final pythonPath = getPythonPath(rootPath);
    final directory = File(pythonPath).parent.path;
    return '$directory\\pythonw.exe';
  }

  static String _resolveExecutable(
    String rootPath,
    String configuredPath,
    String executableName,
  ) {
    final normalized = configuredPath.replaceAll('/', '\\');
    final absolute = _isAbsolutePath(normalized)
        ? normalized
        : '$rootPath\\${normalized.replaceFirst(RegExp(r'^\.[\\/]'), '')}';
    if (absolute.toLowerCase().endsWith('.exe')) {
      return absolute;
    }
    return '$absolute\\$executableName';
  }

  static bool _isAbsolutePath(String path) {
    if (path.length > 2 && path[1] == ':') {
      return true;
    }
    return path.startsWith(r'\\');
  }

  static YamlMap _pythonSection(dynamic yaml) {
    if (yaml is! YamlMap) {
      return YamlMap.wrap({});
    }
    final deploy = yaml['Deploy'];
    if (deploy is! YamlMap) {
      return YamlMap.wrap({});
    }
    final python = deploy['Python'];
    if (python is! YamlMap) {
      return YamlMap.wrap({});
    }
    return python;
  }

  static String _stringValue(dynamic value, String fallback) {
    if (value == null) {
      return fallback;
    }
    final stringValue = value.toString().trim();
    if (stringValue.isEmpty || stringValue.toLowerCase() == 'null') {
      return fallback;
    }
    return stringValue;
  }
}
