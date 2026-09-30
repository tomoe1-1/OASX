/// 启动协调器 —— 决定「启动动画演什么」，并在后台预备部署任务。
///
/// 之所以要这层，是因为启动时有两个诉求会打架：
///
/// 1. **动画要立刻出现**：窗口显示后不能干等几秒才出画面（用户会以为卡死）
/// 2. **要知道是否需要部署**：`authenticatePath` 要读磁盘、解析 yaml，
///    这几百毫秒不该阻塞首帧
///
/// 折中做法：窗口一起来就播「品牌动画」（不需要任何 IO），
/// 同时**并发**做部署判定。若判定需要部署，则把舞台交给
/// [StagedSplashTask] —— 品牌动画无缝切到「部署进度动画」。
///
/// 表现层（[SplashGate]）不关心这些，它只订阅本协调器暴露的
/// 「当前任务」，任务换了就重建。
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:oasx/modules/boot/boot_orchestrator.dart';
import 'package:oasx/modules/boot/splash_task.dart';
import 'package:oasx/modules/server/controllers/server_controller.dart';
import 'package:oasx/modules/settings/controllers/settings_controller.dart';
import 'package:oasx/utils/platform_utils.dart';

/// 启动阶段的三种去向
enum BootPhase {
  /// 还在判定中，先播品牌动画
  probing,

  /// 无需部署（服务已就绪或用户关了自动部署）→ 品牌动画播完就进主界面
  fastBoot,

  /// 需要部署 → 动画改为进度可视化
  deploying,

  /// 部署失败 → 动画停住，交棒主界面由它显示错误
  failed,
}

/// 启动协调器（全局单例，由 `main` 注册进 GetX）
class BootCoordinator extends GetxController {
  /// 当前数据源。`null` = 品牌动画（无阶段列表）
  final Rxn<SplashTask> task = Rxn<SplashTask>();

  final phase = BootPhase.probing.obs;

  Timer? _probeTimer;
  bool _started = false;

  @override
  void onInit() {
    super.onInit();
    if (PlatformUtils.isWindows || PlatformUtils.isDesktop) {
      // 不阻塞首帧：延后一拍再探测
      scheduleMicrotask(_probe);
    } else {
      phase.value = BootPhase.fastBoot;
    }
  }

  /// 探测是否需要部署
  Future<void> _probe() async {
    if (_started) {
      return;
    }
    _started = true;

    // 品牌动画的最短展示时长。
    //
    // 这里刻意压得很短（200ms）：需求是「启动时若未部署就直接开始部署」，
    // 任何多余等待都是在让用户干看。200ms 只够首帧稳定落地（窗口 Show
    // 与立绘解码并行进行），不至于产生「刚亮就切」的撕裂感。
    //
    // 注：探测本身（authenticatePath 读磁盘 + 解析 yaml）就在这段时间里
    // 并发跑完，所以正常情况下并不会真的补时。
    const minBrandShow = Duration(milliseconds: 200);
    final brandStart = DateTime.now();

    var needsDeploy = false;
    String reason = '';

    try {
      final settings = Get.isRegistered<SettingsController>()
          ? Get.find<SettingsController>()
          : null;
      final server = Get.isRegistered<ServerController>()
          ? Get.find<ServerController>()
          : Get.put<ServerController>(ServerController(), permanent: true);

      // 用户关了「自动部署」就不强推部署流程
      final autoDeploy = settings?.autoDeploy.value ?? true;

      final rootOk = server.rootPathServer.value.isNotEmpty &&
          server.authenticatePath(server.rootPathServer.value);

      if (!rootOk && autoDeploy) {
        needsDeploy = true;
        reason = 'OAS 尚未部署';
      } else {
        // 环境在，但服务可能没起来 —— 交给主界面的既有自检去处理，
        // 启动动画这里只负责「装没装」的判断。
        needsDeploy = false;
      }
    } catch (e) {
      // 探测失败一律走快速模式，把问题留给主界面（它有完整的错误 UI）
      needsDeploy = false;
      debugPrint('boot probe failed: $e');
    }

    // 补齐最小品牌展示时长
    final elapsed = DateTime.now().difference(brandStart);
    if (elapsed < minBrandShow) {
      await Future.delayed(minBrandShow - elapsed);
    }

    if (!needsDeploy) {
      phase.value = BootPhase.fastBoot;
      return;
    }

    // ---- 进入部署模式：挂上阶段任务 ----
    debugPrint('boot: $reason，进入部署流程');
    final stagedTask = createBootTask();
    task.value = stagedTask;
    phase.value = BootPhase.deploying;

    final orchestrator = BootOrchestrator(
      task: stagedTask,
      controller: Get.isRegistered<ServerController>()
          ? Get.find<ServerController>()
          : Get.put<ServerController>(ServerController(), permanent: true),
    );

    final outcome = await orchestrator.run();
    if (!outcome.ok) {
      phase.value = BootPhase.failed;
      debugPrint('boot: 部署失败 ${outcome.message}');
    } else {
      phase.value = BootPhase.fastBoot;
      debugPrint('boot: 部署完成');
    }
  }

  @override
  void onClose() {
    _probeTimer?.cancel();
    super.onClose();
  }
}
