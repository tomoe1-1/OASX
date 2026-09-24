part of 'window_service.dart';

extension WindowServiceExitX on WindowService {
  Future<void> _shutdownOasForExit() async {
    if (!Get.isRegistered<AppExitService>()) return;
    await Get.find<AppExitService>().shutdownOasForExitIfEnabled();
  }

  Future<ExitConfirmResult?> _resolveCloseAction() async {
    final appExitService = _appExitService;
    if (appExitService?.skipExitConfirmDialog.value == true) {
      return ExitConfirmResult(
        minimizeToTray: enableSystemTray.value,
        shutdownOas: appExitService?.shutdownOasOnExit.value ?? false,
        skipConfirm: true,
      );
    }
    return Get.dialog<ExitConfirmResult>(
      ExitConfirmDialog(
        initialMinimizeToTray: enableSystemTray.value,
        initialShutdownOas: appExitService?.shutdownOasOnExit.value ?? false,
      ),
      barrierDismissible: false,
    );
  }

  Future<void> _applyCloseAction(ExitConfirmResult result) async {
    _appExitService?.updateShutdownOasOnExit(result.shutdownOas);
    if (result.skipConfirm) {
      _appExitService?.updateSkipExitConfirmDialog(true);
    }
    if (result.minimizeToTray) {
      _updateSystemTrayPreference(true);
      await _hideToTrayIfReady();
      return;
    }
    await updateSystemTrayEnable(false);
    await _shutdownOasForExit();
    await windowManager.setPreventClose(false);
    await windowManager.close();
  }

  Future<void> _hideToTrayIfReady() async {
    final ready = await _prepareSystemTrayForHide();
    if (ready) {
      await windowManager.hide();
    }
  }

  Future<bool> _prepareSystemTrayForHide() async {
    if (_isSystemTrayReady) return true;
    if (!Get.isRegistered<SystemTrayService>()) return false;
    final ok = await Get.find<SystemTrayService>().showTray();
    _isSystemTrayReady = ok;
    if (ok) {
      await windowManager.setPreventClose(true);
    }
    return ok;
  }

  AppExitService? get _appExitService {
    if (!Get.isRegistered<AppExitService>()) return null;
    return Get.find<AppExitService>();
  }
}
