import 'dart:async';
import 'dart:io';

import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:process_run/shell.dart';

import 'package:oasx/api/api_client.dart';
import 'package:oasx/config/oas_defaults.dart';
import 'package:oasx/modules/common/models/storage_key.dart';
import 'package:oasx/modules/home/controllers/dashboard_controller.dart';
import 'package:oasx/modules/log/log_mixin.dart';
import 'package:oasx/modules/server/models/deploy_git_prefetcher.dart';
import 'package:oasx/modules/server/models/deploy_python_config.dart';
import 'package:oasx/modules/settings/controllers/settings_controller.dart';
import 'package:oasx/service/locale_service.dart';
import 'package:oasx/service/script_service.dart';

class ServerController extends GetxController with LogMixin {
  ServerController({GetStorage? storage}) : _storage = storage ?? GetStorage();

  @override
  int get maxLines => 1000;

  final rootPathServer = ''.obs;
  final rootPathAuthenticated = true.obs;
  final showDeploy = true.obs;
  final deployContent = ''.obs;
  final autoLoginAfterDeploy = false.obs;
  final isDeployLoading = false.obs;
  final GetStorage _storage;
  Shell? shell;
  var shellController = ShellLinesController();
  var shellErrorController = ShellLinesController();

  /// Tracks whether taskkill already reported that pythonw.exe is absent.
  var _pythonwNotRunningLogged = false;

  @override
  void onInit() {
    final storedRoot = _storage.read(StorageKey.rootPathServer.name);
    final savedRoot = storedRoot is String ? storedRoot : null;
    rootPathServer.value = Platform.isWindows
        ? resolveStartupOasRootPath(
            savedRootPath: savedRoot,
            isValidRoot: authenticatePath,
          )
        : (savedRoot ?? 'Please set OAS root path');
    if (rootPathServer.value != savedRoot &&
        authenticatePath(rootPathServer.value)) {
      _storage.write(StorageKey.rootPathServer.name, rootPathServer.value);
    }
    autoLoginAfterDeploy.value =
        _storage.read(StorageKey.autoLoginAfterDeploy.name) ?? false;
    shell = getShell;
    shellController.stream.listen(
      (event) => addLog(!event.contains('INFO') ? 'INFO: $event' : event),
    );
    shellErrorController.stream.listen(_addShellErrorLine);
    rootPathAuthenticated.value = authenticatePath(rootPathServer.value);
    if (rootPathAuthenticated.value) {
      readDeploy();
    }
    super.onInit();
  }

  void updateRootPathServer(String value) {
    rootPathAuthenticated.value = authenticatePath(value);
    rootPathServer.value = value;
    shell = getShell;
    Get.find<SettingsController>().storage.write(
      StorageKey.rootPathServer.name,
      rootPathServer.value,
    );
    if (rootPathAuthenticated.value) {
      readDeploy();
    }
  }

  bool authenticatePath(String root) {
    root.replaceAll('\\', '/');
    try {
      final rootDir = Directory(root);
      if (!rootDir.existsSync()) {
        return false;
      }
      final deploy = File('${rootDir.path}/config/deploy.yaml');
      if (!deploy.existsSync()) {
        return false;
      }
      final pythonConfig = DeployPythonConfig.read(rootDir.path);
      final python = File(pythonConfig.getPythonPath(rootDir.path));
      if (!python.existsSync()) {
        return false;
      }
      final git = File('${rootDir.path}/toolkit/Git/mingw64/bin/git.exe');
      if (!git.existsSync()) {
        return false;
      }
      final installer = File('${rootDir.path}/deploy/installer.py');
      if (!installer.existsSync()) {
        return false;
      }
    } catch (e) {
      printError(info: e.toString());
      return false;
    }
    return true;
  }

  void readDeploy() {
    final filePath = '${rootPathServer.value}\\config\\deploy.yaml';
    try {
      final file = File(filePath);
      if (file.existsSync()) {
        deployContent.value = file.readAsStringSync();
      } else {
        deployContent.value = 'File not found';
      }
    } catch (e) {
      deployContent.value = 'Error reading file: $e';
    }
  }

  void writeDeploy(String value) {
    final filePath = '${rootPathServer.value}\\config\\deploy.yaml';
    deployContent.value = value;
    try {
      final file = File(filePath);
      if (file.existsSync()) {
        file.writeAsStringSync(deployContent.value);
      } else {
        deployContent.value = 'File not found';
      }
    } catch (e) {
      deployContent.value = 'Error writing file: $e';
    }
  }

  /// Imports one YAML file into the current OAS deploy config path.
  bool importDeployFile(String sourcePath) {
    final source = File(sourcePath);
    if (!source.existsSync()) {
      return false;
    }
    if (!sourcePath.toLowerCase().endsWith('.yaml')) {
      return false;
    }
    final targetPath = '${rootPathServer.value}\\config\\deploy.yaml';
    try {
      source.copySync(targetPath);
      readDeploy();
      return true;
    } catch (e) {
      deployContent.value = 'Error importing file: $e';
      return false;
    }
  }

  /// Exports the saved deploy.yaml file to a user-selected path.
  bool exportDeployFile(String targetPath) {
    if (targetPath.trim().isEmpty) {
      return false;
    }
    final sourcePath = '${rootPathServer.value}\\config\\deploy.yaml';
    final normalizedTarget = targetPath.toLowerCase().endsWith('.yaml')
        ? targetPath
        : '$targetPath.yaml';
    try {
      final source = File(sourcePath);
      if (!source.existsSync()) {
        return false;
      }
      source.copySync(normalizedTarget);
      return true;
    } catch (e) {
      deployContent.value = 'Error exporting file: $e';
      return false;
    }
  }

  String get pathGit => '${rootPathServer.value}\\toolkit\\Git\\mingw64\\bin';
  String get pathPython => '${rootPathServer.value}\\toolkit';
  String get pathAdb =>
      '${rootPathServer.value}\\toolkit\\Lib\\site-packages\\adbutils\\binaries';
  String get pathScripts => '${rootPathServer.value}\\toolkit\\Scripts';
  String get pathSeparator => Platform.isWindows ? ';' : ':';
  Map<String, String> get pathPATH => {
    'PATH': [
      rootPathServer.value,
      pathGit,
      pathPython,
      pathAdb,
      pathScripts,
    ].join(pathSeparator),
  };

  Shell get getShell => Shell(
    workingDirectory: rootPathServer.value,
    runInShell: true,
    environment: pathPATH,
    stdout: shellController.sink,
    stderr: shellErrorController.sink,
    verbose: false,
  );

  /// Runs one shell command and records failures with the requested severity.
  Future<bool> runShell(
    String command, {
    bool allowFailure = false,
    bool ignorePythonwNotRunning = false,
  }) async {
    if (ignorePythonwNotRunning) {
      _pythonwNotRunningLogged = false;
    }
    try {
      await shell!.run(command);
      return true;
    } on ShellException catch (e) {
      if (ignorePythonwNotRunning && _isPythonwNotRunningException(e)) {
        if (!_pythonwNotRunningLogged) {
          addLog('WARNING: pythonw.exe is not running, skip taskkill');
        }
        return true;
      }
      _addShellExceptionLog(e, allowFailure: allowFailure);
      return false;
    }
  }

  /// Adds a shell exception using info or error severity.
  void _addShellExceptionLog(
    ShellException exception, {
    required bool allowFailure,
  }) {
    final prefix = allowFailure ? 'INFO' : 'ERROR';
    addLog('$prefix: ${exception.toString()}');
  }

  /// Detects the taskkill exit code used when pythonw.exe is absent.
  bool _isPythonwNotRunningException(ShellException exception) {
    final lower = exception.message.toLowerCase();
    return exception.result?.exitCode == 128 &&
        lower.contains('taskkill') &&
        lower.contains('pythonw.exe');
  }

  void _addShellErrorLine(String line) {
    final lower = line.toLowerCase();
    final expectedTaskKillOutput = _isExpectedTaskKillOutput(lower);
    if (expectedTaskKillOutput) {
      _pythonwNotRunningLogged = true;
      final message = line.replaceFirst(
        RegExp(r'^\s*ERROR:\s*', caseSensitive: false),
        '',
      );
      addLog('WARNING: $message');
      return;
    }
    if (_isGitProgressLine(lower)) {
      upsertLog('INFO: $line', _isGitProgressLog);
      return;
    }
    final isError = lower.contains('fatal:') || lower.contains('error:');
    addLog('${isError ? 'ERROR' : 'INFO'}: $line');
  }

  /// Detects taskkill output when no pythonw.exe process is running.
  bool _isExpectedTaskKillOutput(String lowerLine) {
    return lowerLine.contains('pythonw.exe') &&
        (lowerLine.contains('not found') || lowerLine.contains('没有找到'));
  }

  bool _isGitProgressLine(String lowerLine) {
    return lowerLine.startsWith('remote: enumerating objects:') ||
        lowerLine.startsWith('remote: counting objects:') ||
        lowerLine.startsWith('remote: compressing objects:') ||
        lowerLine.startsWith('receiving objects:') ||
        lowerLine.startsWith('resolving deltas:') ||
        lowerLine.startsWith('updating files:');
  }

  bool _isGitProgressLog(String log) {
    return _isGitProgressLine(log.replaceFirst('INFO: ', '').toLowerCase());
  }

  Future<bool> prefetchRepository() async {
    final prefetcher = DeployGitPrefetcher(
      rootPath: rootPathServer.value,
      log: addLog,
      runShell: runShell,
    );
    return prefetcher.prefetchRepository();
  }

  /// 部署互斥锁 —— 保证同一时刻只有一条部署链路在跑。
  ///
  /// 存在两个发起方：
  /// 1. 启动动画的 [BootOrchestrator]（用户看到进度面板的那条）
  /// 2. 主界面 [HomeDashboardController] 的既有启动自检
  ///
  /// 两者若同时触发会互相 kill 对方的子进程。这里用单飞（in-flight
  /// future 复用）保证后到的调用**直接等待先到的那次结果**，
  /// 从而实现「进度只走一遍、双方都满意」。
  Future<bool>? _inFlightDeploy;

  /// 部署进度回调：`(阶段索引, 细节文案)`。
  ///
  /// 启动动画在进入部署模式时挂上它，就能把真实进度映射到画面上，
  /// 而不必自己再跑一遍部署命令。
  void Function(int index, String detail)? onDeployStep;

  /// 通知一次进度（内部用，空实现保护）
  void _step(int index, String detail) {
    final cb = onDeployStep;
    if (cb != null) {
      try {
        cb(index, detail);
      } catch (_) {
        // 回调异常不应影响部署主流程
      }
    }
  }

  /// 与 [run] 等价的公开入口，但带互斥 —— 启动动画走这条。
  Future<bool> runExclusive() {
    final existing = _inFlightDeploy;
    if (existing != null) {
      return existing;
    }
    final future = run().then((_) => true).catchError((Object _) => false);
    _inFlightDeploy = future;
    future.whenComplete(() {
      if (identical(_inFlightDeploy, future)) {
        _inFlightDeploy = null;
      }
    });
    return future;
  }

  Future<void> run() async {
    // 错误/搬迁后的目录不能触发停止服务、拉取仓库和依赖安装。
    if (!authenticatePath(rootPathServer.value)) {
      rootPathAuthenticated.value = false;
      final message = 'OAS 目录无效，请在部署页面重新选择：${rootPathServer.value}';
      addLog('ERROR: $message');
      throw StateError(message);
    }
    isDeployLoading.value = true;
    try {
      _step(1, '正在停止旧服务…');
      if (Get.isRegistered<SettingsController>()) {
        await Get.find<SettingsController>().killServer(
          showTip: false,
          resetDashboardToDisconnected: false,
        );
      }
      clearLog();
      shell!.kill();
      await runShell('echo OAS working directory: ');
      await runShell('cd');
      await runShell(
        'taskkill /f /t /im pythonw.exe',
        ignorePythonwNotRunning: true,
      );
      _step(1, '正在拉取 OAS 仓库…');
      await prefetchRepository();
      _step(1, '仓库已同步');
      final pythonConfig = DeployPythonConfig.read(rootPathServer.value);
      _step(2, '正在安装运行依赖（可能需要几分钟）…');
      await runShell(
        shellExecutableArguments(
          pythonConfig.getPythonPath(rootPathServer.value),
          ['-m', 'deploy.installer'],
        ),
      );
      _step(2, '依赖安装完成');
      await runShell('echo Start OAS');
      _step(3, '正在启动 OAS 服务…');
      unawaited(
        runShell(
          shellExecutableArguments(
            pythonConfig.getPythonwPath(rootPathServer.value),
            ['server.py'],
          ),
        ),
      );
      _step(3, '服务已启动');

      final shouldAutoLogin = _resolveAutoLoginAfterDeploy();
      if (!shouldAutoLogin) {
        return;
      }

      final address = _storage.read(StorageKey.address.name) ?? '';
      if (address.isEmpty) {
        return;
      }
      await Future.delayed(const Duration(seconds: 2));
      await _tryConnect(
        address,
        retries: 60,
        retryDelay: const Duration(milliseconds: 500),
      );
    } finally {
      isDeployLoading.value = false;
    }
  }

  bool _resolveAutoLoginAfterDeploy() {
    if (Get.isRegistered<SettingsController>()) {
      final value = Get.find<SettingsController>().autoLoginAfterDeploy.value;
      autoLoginAfterDeploy.value = value;
      return value;
    }
    final value = _storage.read(StorageKey.autoLoginAfterDeploy.name) ?? false;
    autoLoginAfterDeploy.value = value;
    return value;
  }

  Future<bool> _tryConnect(
    String rawAddress, {
    int retries = 1,
    Duration retryDelay = const Duration(milliseconds: 500),
  }) async {
    final address =
        rawAddress.startsWith('http://') || rawAddress.startsWith('https://')
        ? rawAddress
        : 'http://$rawAddress';
    ApiClient().setAddress(address);

    for (int i = 0; i < retries; i++) {
      final connected = await ApiClient().testAddress();
      if (connected) {
        try {
          if (Get.isRegistered<HomeDashboardController>()) {
            await Get.find<HomeDashboardController>()
                .refreshAfterExternalConnected();
          } else if (Get.isRegistered<ScriptService>()) {
            await Get.find<ScriptService>().reloadFromServer();
          }
        } catch (_) {
          // Keep navigation behavior even if dashboard refresh fails here.
        }
        await Get.find<LocaleService>().refreshTransFromRemote();
        Get.offAllNamed('/home');
        return true;
      }
      if (i < retries - 1) {
        await Future.delayed(retryDelay);
      }
    }
    return false;
  }
}
