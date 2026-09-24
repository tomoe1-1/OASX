import 'dart:io' show Platform;
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:oasx/modules/home/models/config_model.dart';
import 'package:oasx/service/app_exit_service.dart';
import 'package:oasx/service/script_service.dart';
import 'package:oasx/translation/i18n_content.dart';
import 'package:oasx/utils/platform_utils.dart';
import 'package:system_tray/system_tray.dart';
import 'package:window_manager/window_manager.dart';

part 'system_tray_service_menu.dart';

class SystemTrayService extends GetxService {
  static const MethodChannel _trayThemeChannel = MethodChannel(
    'oasx/tray_theme',
  );

  final SystemTray _systemTray = SystemTray();
  final AppWindow _appWindow = AppWindow();

  bool _isTrayVisible = false;
  bool? _lastAppliedTrayDarkMode;

  Future<bool> showTray() async {
    if (!PlatformUtils.isDesktop) return false;
    if (_isTrayVisible) return true;

    final iconPath = Platform.isWindows
        ? 'assets/images/Icon-app.ico'
        : 'assets/images/Icon-app.png';

    try {
      final ok = await _systemTray.initSystemTray(
        title: 'OASX',
        iconPath: iconPath,
      );
      if (!ok) return false;

      await _rebuildMenu();
      _systemTray.registerSystemTrayEventHandler((eventName) async {
        if (eventName == kSystemTrayEventClick) {
          // 单击默认显示窗口
          await windowManager.show();
          await windowManager.focus();
        } else if (eventName == kSystemTrayEventRightClick) {
          // 右键打开菜单
          await _rebuildMenu();
          Platform.isWindows
              ? _systemTray.popUpContextMenu()
              : _appWindow.show();
        }
      });
      _isTrayVisible = true;
      return true;
    } catch (_) {
      _isTrayVisible = false;
      return false;
    }
  }

  Future<void> hideTray() async {
    if (_isTrayVisible) {
      await _systemTray.destroy();
      _isTrayVisible = false;
    }
  }

  Future<void> _rebuildMenu() async {
    await syncTrayTheme();
    final Menu mainMenu = Menu();
    await mainMenu.buildFrom([
      ...buildScriptMenuGroups(),
      MenuSeparator(),
      MenuItemLabel(
        label: I18n.showWindow.tr,
        onClicked: (_) async {
          await windowManager.show();
          await windowManager.focus();
        },
      ),
      MenuItemLabel(
        label: I18n.exit.tr,
        onClicked: (_) async {
          await _shutdownOasForExit();
          await windowManager.setPreventClose(false);
          await hideTray();
          await windowManager.close();
        },
      ),
    ]);
    await _systemTray.setContextMenu(mainMenu);
  }

  Future<void> syncTrayTheme([bool? darkMode]) async {
    if (!Platform.isWindows) return;
    final dark = darkMode ?? Get.isDarkMode;
    if (_lastAppliedTrayDarkMode == dark) return;
    try {
      final applied = await _trayThemeChannel.invokeMethod<bool>(
        'setDarkMode',
        {'dark': dark},
      );
      if (applied == true) _lastAppliedTrayDarkMode = dark;
    } catch (_) {}
  }

  Future<void> _shutdownOasForExit() async {
    if (!Get.isRegistered<AppExitService>()) return;
    await Get.find<AppExitService>().shutdownOasForExitIfEnabled();
  }
}
