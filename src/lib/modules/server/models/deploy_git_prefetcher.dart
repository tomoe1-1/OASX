import 'package:process_run/shell.dart';

import 'package:oasx/modules/server/models/deploy_git_config.dart';

/// Runs a visible Git prefetch before the Python installer starts.
class DeployGitPrefetcher {
  /// Creates one prefetcher using the controller shell runner.
  const DeployGitPrefetcher({
    required this.rootPath,
    required this.log,
    required this.runShell,
  });

  /// OAS root path used as the Git working directory.
  final String rootPath;

  /// Writes deployment log lines.
  final void Function(String message) log;

  /// Runs one shell command and reports whether it succeeded.
  final Future<bool> Function(String command, {bool allowFailure}) runShell;

  /// Fetches the configured branch with progress output.
  Future<bool> prefetchRepository() async {
    try {
      final config = DeployGitConfig.read(rootPath);
      if (!config.autoUpdate) {
        return true;
      }
      final configured = await _configureRepository(config);
      if (!configured) {
        return false;
      }
      return _fetchBranch(config);
    } catch (e) {
      log('ERROR: Failed to prepare git fetch: $e');
      return false;
    }
  }

  Future<bool> _configureRepository(DeployGitConfig config) async {
    if (!await _runGitCommand(config, ['init'])) {
      return false;
    }
    final remoteUpdated = await _runGitCommand(config, [
      'remote',
      'set-url',
      'origin',
      config.repository,
    ], allowFailure: true);
    if (!remoteUpdated &&
        !await _runGitCommand(config, [
          'remote',
          'add',
          'origin',
          config.repository,
        ])) {
      return false;
    }
    return _configureNetwork(config);
  }

  Future<bool> _configureNetwork(DeployGitConfig config) async {
    if (config.gitProxy.isNotEmpty) {
      if (!await _runGitCommand(config, [
        'config',
        '--local',
        'http.proxy',
        config.gitProxy,
      ])) {
        return false;
      }
      if (!await _runGitCommand(config, [
        'config',
        '--local',
        'https.proxy',
        config.gitProxy,
      ])) {
        return false;
      }
    }
    if (!await _runGitCommand(config, [
      'config',
      '--local',
      'http.version',
      'HTTP/1.1',
    ])) {
      return false;
    }
    return _runGitCommand(config, [
      'config',
      '--local',
      'core.compression',
      '0',
    ]);
  }

  Future<bool> _fetchBranch(DeployGitConfig config) async {
    log(
      'INFO: ==================== PREFETCH REPOSITORY BRANCH ====================',
    );
    return _runGitCommand(config, [
      '-c',
      'http.version=HTTP/1.1',
      '-c',
      'core.compression=0',
      'fetch',
      '--progress',
      'origin',
      config.branch,
    ]);
  }

  Future<bool> _runGitCommand(
    DeployGitConfig config,
    List<String> arguments, {
    bool allowFailure = false,
  }) {
    final git = config.getExecutablePath(rootPath);
    final command = shellExecutableArguments(git, arguments);
    log('INFO: $command');
    return runShell(command, allowFailure: allowFailure);
  }
}
