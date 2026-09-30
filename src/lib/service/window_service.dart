import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:get_storage/get_storage.dart';
import 'package:oasx/modules/common/models/storage_key.dart';
import 'package:oasx/modules/common/models/window_state.dart';
import 'package:oasx/modules/common/widgets/exit_confirm_dialog.dart';
import 'package:oasx/service/app_exit_service.dart';
import 'package:oasx/service/system_tray_service.dart';
import 'package:oasx/service/window_geometry.dart';
import 'package:oasx/utils/platform_utils.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';

part 'window_service_exit.dart';

const Size _defaultDesktopWindowSize = Size(1200, 800);
const Size _minimumWindowsWindowSize = Size(260, 420);

class WindowService extends GetxService with WindowListener {
  // ignore: unused_field
  final _storage = GetStorage();
  final Completer<void> _readyCompleter = Completer<void>();
  Future<void> get ready => _readyCompleter.future;

  bool _didInitDesktop = false;
  bool _isSystemTrayReady = false;
  int _trayInitToken = 0;

  Timer? _debounceTimer;
  DateTime? _lastSaveTime;
  bool _isSavingWindowState = false;
  List<Rect> _displayWorkAreas = [];
  final enableWindowState = false.obs;
  final enableSystemTray = false.obs;

  @override
  Future<void> onInit() async {
    try {
      await _initDesktopIfNeeded();
    } catch (e) {
      printError(info: 'window init failed: $e');
    } finally {
      if (!_readyCompleter.isCompleted) {
        _readyCompleter.complete();
      }
    }
    super.onInit();
  }

  Future<void> _initDesktopIfNeeded() async {
    if (_didInitDesktop || !PlatformUtils.isDesktop) return;
    _didInitDesktop = true;

    await windowManager.ensureInitialized();

    enableWindowState.value =
        _storage.read(StorageKey.enableWindowState.name) ?? false;
    enableSystemTray.value =
        _storage.read(StorageKey.enableSystemTray.name) ?? false;

    final lastState = await initWindowState();

    await windowManager.waitUntilReadyToShow(buildWindowOptions(lastState));
    // Apply restored bounds after the plugin restores any minimized/maximized
    // native state; otherwise Windows can replace the requested normal bounds.
    if (lastState != null) {
      await windowManager.setBounds(
        Rect.fromLTWH(
          lastState.x,
          lastState.y,
          lastState.width,
          lastState.height,
        ),
      );
    }
    windowManager.addListener(this);

    // waitUntilReadyToShow 只配置窗口，不会替应用调用 show()。
    // 等首帧画好后再显示，避免启动时留下一个一直隐藏的进程。
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await windowManager.show();
        await windowManager.focus();
      } catch (e) {
        printError(info: 'window show failed: $e');
      }
    });

    _kickoffSystemTrayInit();
  }

  void _kickoffSystemTrayInit() {
    if (!PlatformUtils.isDesktop) return;

    if (!enableSystemTray.value) {
      _isSystemTrayReady = false;
      unawaited(windowManager.setPreventClose(true));
      return;
    }

    _isSystemTrayReady = false;
    unawaited(windowManager.setPreventClose(true));

    final token = ++_trayInitToken;
    unawaited(_ensureSystemTrayReady(token));
  }

  Future<void> _ensureSystemTrayReady(int token) async {
    const maxAttempts = 30;
    const retryDelay = Duration(seconds: 1);

    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      if (!PlatformUtils.isDesktop) return;
      if (!enableSystemTray.value) return;
      if (token != _trayInitToken) return;
      if (!Get.isRegistered<SystemTrayService>()) return;

      final ok = await Get.find<SystemTrayService>().showTray();
      if (ok) {
        _isSystemTrayReady = true;
        await windowManager.setPreventClose(true);
        return;
      }

      await Future.delayed(retryDelay);
    }

    printInfo(info: 'system tray init failed, allow window close.');
    _isSystemTrayReady = false;
    await windowManager.setPreventClose(true);
  }

  WindowOptions buildWindowOptions(WindowStateModel? lastState) {
    final minimumSize = PlatformUtils.isWindows
        ? _minimumWindowsWindowSize
        : null;
    final initialSize = _resolveInitialWindowSize(
      lastState,
      minimumSize: minimumSize,
    );
    return WindowOptions(
      size: initialSize,
      center: lastState == null,
      minimumSize: minimumSize,
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.hidden,
    );
  }

  Size _resolveInitialWindowSize(
    WindowStateModel? lastState, {
    Size? minimumSize,
  }) {
    if (lastState == null) {
      if (_displayWorkAreas.isEmpty) return _defaultDesktopWindowSize;
      return fitWindowSize(
        _defaultDesktopWindowSize,
        _displayWorkAreas.first,
        minimumSize: minimumSize ?? Size.zero,
      );
    }
    if (minimumSize == null) {
      return Size(lastState.width, lastState.height);
    }
    return Size(
      lastState.width < minimumSize.width ? minimumSize.width : lastState.width,
      lastState.height < minimumSize.height
          ? minimumSize.height
          : lastState.height,
    );
  }

  Future<WindowStateModel?> initWindowState() async {
    _displayWorkAreas = await _readDisplayWorkAreas();
    if (!enableWindowState.value) return null;
    return restoreWindowGeometry(
      _storage.read(StorageKey.windowState.name),
      workAreas: _displayWorkAreas,
      minimumSize: PlatformUtils.isWindows
          ? _minimumWindowsWindowSize
          : Size.zero,
    );
  }

  Future<List<Rect>> _readDisplayWorkAreas() async {
    try {
      final displays = await screenRetriever.getAllDisplays();
      final areas = displays
          .map((display) {
            final position = display.visiblePosition ?? Offset.zero;
            final size = display.visibleSize ?? display.size;
            return Rect.fromLTWH(
              position.dx,
              position.dy,
              size.width,
              size.height,
            );
          })
          .where(isValidWindowRect)
          .toList();
      if (areas.length > 1) {
        try {
          final primary = await screenRetriever.getPrimaryDisplay();
          final position = primary.visiblePosition ?? Offset.zero;
          final size = primary.visibleSize ?? primary.size;
          final primaryBounds = Rect.fromLTWH(
            position.dx,
            position.dy,
            size.width,
            size.height,
          );
          final index = areas.indexOf(primaryBounds);
          if (index > 0) {
            final primaryArea = areas.removeAt(index);
            areas.insert(0, primaryArea);
          }
        } catch (e) {
          // The complete display list remains usable if only primary lookup fails.
          printError(info: 'primary display lookup failed: $e');
        }
      }
      return areas;
    } catch (e) {
      printError(info: 'screen work area lookup failed: $e');
      // Unverified saved coordinates are unsafe; use the plugin's default center.
      return [];
    }
  }

  Future<void> _saveWindowState() async {
    if (!PlatformUtils.isDesktop ||
        !enableWindowState.value ||
        _isSavingWindowState) {
      return;
    }
    _isSavingWindowState = true;
    try {
      if (await windowManager.isMinimized() ||
          await windowManager.isMaximized()) {
        return;
      }
      final bounds = await windowManager.getBounds();
      final workAreas = await _readDisplayWorkAreas();
      // A minimize/maximize can begin while querying native bounds/displays.
      final state = windowGeometryToSave(
        bounds,
        isMinimized: await windowManager.isMinimized(),
        isMaximized: await windowManager.isMaximized(),
        workAreas: workAreas,
        minimumSize: PlatformUtils.isWindows
            ? _minimumWindowsWindowSize
            : Size.zero,
      );
      if (state == null) return;
      await _storage.write(
        StorageKey.windowState.name,
        json.encode(state.toJson()),
      );
      printInfo(info: 'save window state:${state.toJson()}');
    } catch (e) {
      printError(info: 'save window state failed: $e');
    } finally {
      _isSavingWindowState = false;
    }
  }

  void _scheduleSave() {
    if (!PlatformUtils.isDesktop || !enableWindowState.value) return;
    final now = DateTime.now();
    if (_lastSaveTime == null ||
        now.difference(_lastSaveTime!) > const Duration(seconds: 2)) {
      _lastSaveTime = now;
      _saveWindowState();
    }
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 500), () async {
      _lastSaveTime = DateTime.now();
      await _saveWindowState();
    });
  }

  @override
  void onWindowMove() => _scheduleSave();
  @override
  void onWindowResize() => _scheduleSave();

  @override
  void onWindowClose() async {
    _debounceTimer?.cancel();
    final preventClose = await windowManager.isPreventClose();
    if (!preventClose) return;
    await _saveWindowState();
    final result = await _resolveCloseAction();
    if (result == null) return;
    await _applyCloseAction(result);
  }

  @override
  void onClose() {
    if (PlatformUtils.isDesktop) {
      windowManager.removeListener(this);
    }
    _debounceTimer?.cancel();
    super.onClose();
  }

  void updateWindowStateEnable(bool newVal) {
    enableWindowState.value = newVal;
    _storage.write(StorageKey.enableWindowState.name, newVal);
  }

  Future<void> updateSystemTrayEnable(bool newVal) async {
    _updateSystemTrayPreference(newVal);

    if (!PlatformUtils.isDesktop) return;

    if (newVal) {
      _kickoffSystemTrayInit();
      return;
    }

    _trayInitToken++;
    _isSystemTrayReady = false;
    await windowManager.setPreventClose(true);
    if (!Get.isRegistered<SystemTrayService>()) {
      return;
    }
    await Get.find<SystemTrayService>().hideTray();
  }

  void _updateSystemTrayPreference(bool enabled) {
    enableSystemTray.value = enabled;
    _storage.write(StorageKey.enableSystemTray.name, enabled);
  }
}
