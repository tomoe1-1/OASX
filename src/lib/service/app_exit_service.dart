import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:oasx/modules/common/models/storage_key.dart';
import 'package:oasx/modules/settings/controllers/settings_controller.dart';
import 'package:oasx/service/app_exit_unload_handler_io.dart'
    if (dart.library.html) 'package:oasx/service/app_exit_unload_handler_web.dart';
import 'package:oasx/utils/platform_utils.dart';

/// Coordinates OAS shutdown behavior during application exit.
class AppExitService extends GetxService with WidgetsBindingObserver {
  /// Stores the persisted exit shutdown preference.
  final GetStorage _storage = GetStorage();

  /// Tracks whether OAS should be shut down when OASX exits.
  final RxBool shutdownOasOnExit = false.obs;

  /// Tracks whether desktop close confirmation should be skipped.
  final RxBool skipExitConfirmDialog = false.obs;

  /// Prevents duplicate shutdown calls during the same exit sequence.
  bool _shutdownStarted = false;

  /// Limits how long a real exit waits for the shutdown request.
  static const Duration exitShutdownTimeout = Duration(seconds: 2);

  @override
  void onInit() {
    super.onInit();
    shutdownOasOnExit.value =
        _storage.read(StorageKey.shutdownOasOnExit.name) ?? false;
    skipExitConfirmDialog.value =
        _storage.read(StorageKey.skipExitConfirmDialog.name) ?? false;
    _registerPlatformExitHooks();
  }

  @override
  void onClose() {
    if (PlatformUtils.isMobile) {
      WidgetsBinding.instance.removeObserver(this);
    }
    super.onClose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.detached) {
      return;
    }
    unawaited(shutdownOasForExitIfEnabled());
  }

  /// Persists whether OAS should be shut down when OASX exits.
  void updateShutdownOasOnExit(bool enabled) {
    shutdownOasOnExit.value = enabled;
    _storage.write(StorageKey.shutdownOasOnExit.name, enabled);
  }

  /// Persists whether the desktop exit confirmation dialog is skipped.
  void updateSkipExitConfirmDialog(bool skip) {
    skipExitConfirmDialog.value = skip;
    _storage.write(StorageKey.skipExitConfirmDialog.name, skip);
  }

  /// Shuts down OAS for a real app exit when the user preference allows it.
  Future<void> shutdownOasForExitIfEnabled({
    Duration timeout = exitShutdownTimeout,
  }) async {
    if (!shutdownOasOnExit.value || _shutdownStarted) {
      return;
    }
    _shutdownStarted = true;
    try {
      if (!Get.isRegistered<SettingsController>()) {
        return;
      }
      await Get.find<SettingsController>()
          .killServer(showTip: false, resetDashboardToDisconnected: false)
          .timeout(timeout);
    } catch (_) {}
  }

  /// Registers platform-specific hooks that represent app termination.
  void _registerPlatformExitHooks() {
    if (PlatformUtils.isWeb) {
      registerAppExitUnloadHandler(() {
        unawaited(shutdownOasForExitIfEnabled());
      });
      return;
    }
    if (PlatformUtils.isMobile) {
      WidgetsBinding.instance.addObserver(this);
    }
  }
}
