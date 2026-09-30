import 'package:device_preview/device_preview.dart';
import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:oasx/modules/boot/boot_coordinator.dart';
import 'package:oasx/modules/boot/splash_screen.dart';
import 'package:oasx/modules/settings/controllers/settings_controller.dart';
import 'package:oasx/service/app_exit_service.dart';
import 'package:oasx/service/autostart_service.dart';
import 'package:oasx/service/app_update_service.dart';
import 'package:oasx/service/locale_service.dart';
import 'package:oasx/service/script_service.dart';
import 'package:oasx/service/system_tray_service.dart';
import 'package:oasx/service/theme_service.dart';
import 'package:oasx/service/websocket_service.dart';
import 'package:oasx/service/window_service.dart';
import 'package:oasx/translation/i18n.dart';
import 'package:oasx/utils/logger.dart';
import 'package:oasx/utils/platform_utils.dart';
import 'package:oasx/routes.dart';
import 'package:responsive_builder/responsive_builder.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initService();

  runApp(
    DevicePreview(
      enabled: !kReleaseMode && PlatformUtils.isWindows,
      builder: (context) => const OASXApp(),
    ),
  );
}

/// 「还没有部署任务」时给启动层用的占位 key。
///
/// 与真实任务的 identity 一起构成启动层的重建信号：任务从无到有时
/// key 改变 → Flutter 丢弃旧 State → 新的 SplashScreen 重新 initState
/// → 订阅到部署任务。详见 [OASXApp.build] 里的说明。
const Object _brandTaskKey = 'oasx-splash-brand';

class OASXApp extends StatelessWidget {
  const OASXApp({super.key});

  @override
  Widget build(BuildContext context) {
    final localeService = Get.find<LocaleService>();
    final themeService = Get.find<ThemeService>();

    return ResponsiveApp(
      builder: (context) {
        return Obx(
          () => GetMaterialApp(
            debugShowCheckedModeBanner: false,
            builder: (context, child) {
              // 启动动画叠在整棵路由树之上：主界面在底层先建好，
              // 动画淡出时底下已是真实界面，避免硬切跳变。
              //
              // 启动时若检测到 OAS 未部署，BootCoordinator 会把
              // «部署进度任务» 挂上来，SplashGate 随即从品牌动画切到
              // 部署进度动画 —— 动画即进度，装完正好收尾。
              final app = DevicePreview.appBuilder(context, child);
              if (!PlatformUtils.isWindows) {
                return app;
              }
              final coordinator = Get.isRegistered<BootCoordinator>()
                  ? Get.find<BootCoordinator>()
                  : null;
              return Obx(() {
                final t = coordinator?.task.value;
                // ── key 不能省 ──
                // BootCoordinator 会在探测完成后把 null 换成 StagedSplashTask。
                // 若不换 key，Flutter 会复用同一份 State（同类型、同位置），
                // SplashScreen 的 initState 不再执行 → 新任务永远不被订阅 →
                // 部署进度页根本不会出现（表现为「部署分支像没接上」）。
                // 用任务 identity 作 key，任务一换就重建整棵启动层。
                return SplashGate(
                  key: ValueKey<Object>(t ?? _brandTaskKey),
                  task: t,
                  child: app,
                );
              });
            },
            scrollBehavior: GlobalBehavior(),
            translations: Messages(),
            locale: localeService.currentLocale,
            fallbackLocale: localeService.fallbackLocale,
            title: 'OASX',
            initialRoute: Routes.initial,
            getPages: Routes.routes,
            theme: themeService.lightTheme,
            darkTheme: themeService.darkTheme,
            themeMode: themeService.themeMode,
          ),
        );
      },
    );
  }
}

class GlobalBehavior extends MaterialScrollBehavior {
  @override
  Set<PointerDeviceKind> get dragDevices => {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
  };
}

Future<void> initService() async {
  await GetStorage.init();

  Get.put(SettingsController(), permanent: true);
  Get.put(AppExitService(), permanent: true);
  if (PlatformUtils.isDesktop) {
    Get.put(SystemTrayService(), permanent: true);
  }
  Get.lazyPut<WebSocketService>(() => WebSocketService(), fenix: true);
  final windowService = Get.put(WindowService());
  // 启动协调器：窗口起来后探测是否需要部署
  Get.put(BootCoordinator(), permanent: true);

  await Future.wait([
    initLogger(),
    Get.putAsync(() async => LocaleService()),
    Get.putAsync(() async => ThemeService()),
    Get.putAsync(() async => AutoStartService(), permanent: true),
    Get.putAsync(() async => AppUpdateService(), permanent: true),
    windowService.ready,
    Get.putAsync(() async => ScriptService(), permanent: true),
  ]);
}
