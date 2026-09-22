import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:oasx/config/theme.dart';
import 'package:oasx/modules/common/models/storage_key.dart';
import 'package:oasx/service/system_tray_service.dart';

class ThemeService extends GetxService {
  final _storage = GetStorage();
  final _dark = false.obs;

  /// 当前配色种子，可在设置页切换并持久化
  final _seed = ColorSeed.baseColor.obs;

  bool get isDarkMode => _dark.value;

  /// 当前配色种子
  ColorSeed get seed => _seed.value;

  /// 当前种子色
  Color get color => _seed.value.color;

  /// 按当前种子生成的亮色主题
  ThemeData get lightTheme => buildLightTheme(color);

  /// 按当前种子生成的暗色主题
  ThemeData get darkTheme => buildDarkTheme(color);

  ThemeMode get themeMode => isDarkMode ? ThemeMode.dark : ThemeMode.light;

  @override
  void onInit() {
    _dark.value = _storage.read(StorageKey.dark.name) ?? false;
    _seed.value = ColorSeed.fromName(
      _storage.read<String>(StorageKey.colorSeed.name),
    );
    _applyTheme();
    super.onInit();
  }

  /// 切换明暗模式
  void switchTheme([bool? dark]) {
    _dark.value = dark ?? !_dark.value;
    _storage.write(StorageKey.dark.name, _dark.value);
    _applyTheme();
    _syncTray();
  }

  /// 切换配色种子
  void switchSeed(ColorSeed next) {
    if (_seed.value == next) {
      return;
    }
    _seed.value = next;
    _storage.write(StorageKey.colorSeed.name, next.name);
    _applyTheme();
    _syncTray();
  }

  void _applyTheme() {
    // 同步更新亮/暗两套主题，切换明暗时无需重建页面
    Get.changeTheme(lightTheme);
    Get.changeThemeMode(themeMode);
  }

  void _syncTray() {
    if (Get.isRegistered<SystemTrayService>()) {
      Get.find<SystemTrayService>().syncTrayTheme(isDarkMode);
    }
  }
}
