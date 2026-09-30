/// 启动时校验 OAS 目录，品牌动画结束后进入可操作的主界面。
/// 有效目录的自动部署和进度展示由主界面负责；错误路径留给用户修正。
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:oasx/modules/boot/splash_task.dart';
import 'package:oasx/modules/server/controllers/server_controller.dart';
import 'package:oasx/utils/platform_utils.dart';

/// 保留启动状态 API，供启动画面订阅。
enum BootPhase { probing, fastBoot, deploying, failed }

class BootCoordinator extends GetxController {
  final Rxn<SplashTask> task = Rxn<SplashTask>();
  final phase = BootPhase.probing.obs;
  bool _started = false;
  bool _closed = false;

  @override
  void onInit() {
    super.onInit();
    if (PlatformUtils.isDesktop) {
      scheduleMicrotask(_probe);
    } else {
      phase.value = BootPhase.fastBoot;
    }
  }

  Future<void> _probe() async {
    if (_started) return;
    _started = true;
    try {
      final server = Get.isRegistered<ServerController>()
          ? Get.find<ServerController>()
          : Get.put<ServerController>(ServerController(), permanent: true);
      final rootOk = server.authenticatePath(server.rootPathServer.value);
      server.rootPathAuthenticated.value = rootOk;
      if (!rootOk) {
        server.addLog(
          'ERROR: OAS 目录无效，请在部署页面重新选择：${server.rootPathServer.value}',
        );
      }
    } catch (error) {
      debugPrint('boot probe failed: $error');
    }
    // 给首帧和图像解码留出时间，不等待部署网络操作。
    await Future<void>.delayed(const Duration(milliseconds: 200));
    if (!_closed) phase.value = BootPhase.fastBoot;
  }

  @override
  void onClose() {
    _closed = true;
    super.onClose();
  }
}
