import 'dart:io';

import 'package:yaml/yaml.dart';

/// Git settings read from the OAS deploy YAML file.
class DeployGitConfig {
  /// Creates a deploy Git config snapshot.
  const DeployGitConfig({
    required this.repository,
    required this.branch,
    required this.gitExecutable,
    required this.gitProxy,
    required this.autoUpdate,
  });

  /// Repository URL used by the installer.
  final String repository;

  /// Branch fetched by the installer.
  final String branch;

  /// Git executable path relative to the OAS root.
  final String gitExecutable;

  /// Optional Git HTTP proxy value.
  final String gitProxy;

  /// Whether auto update is enabled.
  final bool autoUpdate;

  /// Reads deploy Git settings from the OAS root path.
  factory DeployGitConfig.read(String rootPath) {
    final file = File('$rootPath\\config\\deploy.yaml');
    final yaml = loadYaml(file.readAsStringSync());
    final git = _gitSection(yaml);

    return DeployGitConfig(
      repository: _stringValue(
        git['Repository'],
        'https://e.coding.net/onmyojiautoscript/oas/OnmyojiAutoScript.git',
      ),
      branch: _stringValue(git['Branch'], 'master'),
      gitExecutable: _stringValue(
        git['GitExecutable'],
        './toolkit/Git/mingw64/bin/git.exe',
      ),
      gitProxy: _stringValue(git['GitProxy'], ''),
      autoUpdate: _boolValue(git['AutoUpdate'], fallback: true),
    );
  }

  /// Absolute Git executable path for local process execution.
  String getExecutablePath(String rootPath) {
    final normalized = gitExecutable.replaceAll('/', '\\');
    if (normalized.length > 2 && normalized[1] == ':') {
      return normalized;
    }
    final relative = normalized.replaceFirst(RegExp(r'^\.[\\/]'), '');
    return '$rootPath\\$relative';
  }

  static YamlMap _gitSection(dynamic yaml) {
    if (yaml is! YamlMap) {
      return YamlMap.wrap({});
    }
    final deploy = yaml['Deploy'];
    if (deploy is! YamlMap) {
      return YamlMap.wrap({});
    }
    final git = deploy['Git'];
    if (git is! YamlMap) {
      return YamlMap.wrap({});
    }
    return git;
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

  static bool _boolValue(dynamic value, {required bool fallback}) {
    if (value is bool) {
      return value;
    }
    if (value == null) {
      return fallback;
    }
    final stringValue = value.toString().trim().toLowerCase();
    if (stringValue == 'true') {
      return true;
    }
    if (stringValue == 'false') {
      return false;
    }
    return fallback;
  }
}
