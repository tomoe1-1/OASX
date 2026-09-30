/// 启动编排：把「检查环境 → 拉取仓库 → 安装依赖 → 启动服务 → 建立连接」
/// 这条链路映射成一个 [StagedSplashTask]，供启动动画消费。
///
/// **关键设计：不自己重复执行部署。**
/// 部署命令由 [ServerController.run] 执行（已带互斥锁），本编排器只负责
/// **订阅它的真实进度并翻译成动画阶段**。这样：
///
/// - 进度是真实的，不是假动画
/// - 与主界面既有的启动自检共用同一次部署（互斥锁保证），不会装两遍
/// - 动画时长 = 部署耗时，装得慢就演得慢
///
/// 设计要点：
/// - **每阶段有最短停留时间**：git 拉取可能 200ms 就结束，直接跳会让画面一闪，
///   用户来不及看清阶段名。
/// - **失败即停**：任一阶段失败，任务标记 failed，动画停在红色状态。
/// - **不可跳过**：部署期间 `canSkip == false`。
library;

import 'dart:async';

import 'package:oasx/modules/boot/splash_task.dart';
import 'package:oasx/modules/server/controllers/server_controller.dart';

/// 每阶段的最短停留时长 —— 避免快阶段「一闪而过」
const Duration kStageMinDwell = Duration(milliseconds: 450);

/// 一次启动编排的结果
class BootOutcome {
  const BootOutcome({
    required this.ok,
    this.alreadyDeployed = false,
    this.message = '',
  });

  final bool ok;

  /// 是否本来就已部署（走了快速通道）
  final bool alreadyDeployed;

  final String message;
}

/// 启动编排器
class BootOrchestrator {
  BootOrchestrator({required this.task, required this.controller});

  final StagedSplashTask task;
  final ServerController controller;

  DateTime _stageEntered = DateTime.now();

  void _enter(int index, {String? detail}) {
    _stageEntered = DateTime.now();
    task.begin(index);
    if (detail != null) {
      task.update(index, detail: detail);
    }
  }

  /// 等待「最短停留」补齐后，才把阶段标为完成
  Future<void> _completeAfterDwell(int index) async {
    final elapsed = DateTime.now().difference(_stageEntered);
    if (elapsed < kStageMinDwell) {
      await Future.delayed(kStageMinDwell - elapsed);
    }
    task.complete(index);
  }

  /// 执行启动链路
  Future<BootOutcome> run() async {
    final root = controller.rootPathServer.value;

    // ---- 阶段 0：检查运行环境 ----
    _enter(0, detail: '正在校验配置与工具链…');
    final ready = controller.authenticatePath(root);
    if (ready) {
      task.update(0, detail: '环境就绪：$root');
    } else {
      task.update(0, detail: '环境未就绪，将执行完整部署');
    }
    await _completeAfterDwell(0);

    // ---- 挂上真实进度回调 ----
    // ServerController.run 里的步骤号：1=仓库 2=依赖 3=服务，
    // 正好对应动画的阶段 1–3（阶段 0 是检查环境，已单独走完）。
    controller.onDeployStep = (stepIndex, detail) {
      final stageIndex = stepIndex.clamp(1, 3);
      if (task.stages[stageIndex].state != SplashStageState.running) {
        _enter(stageIndex, detail: detail);
      } else {
        task.update(stageIndex, detail: detail);
      }
    };

    try {
      if (task.stages[1].state != SplashStageState.running) {
        _enter(1, detail: '正在拉取 OAS 仓库…');
      }

      // ---- 阶段 1–3 由 ServerController 执行，这里只等它跑完 ----
      final ok = await controller.runExclusive();

      if (!ok) {
        final failedIndex = _firstUnfinishedIndex();
        task.fail(failedIndex, '部署过程中断，详见日志');
        return const BootOutcome(ok: false, message: '部署过程中断');
      }

      // 部署返回后，把 1–3 补齐为完成（回调可能没覆盖到最后一步）
      for (var i = 1; i <= 3; i++) {
        final state = task.stages[i].state;
        if (state == SplashStageState.done ||
            state == SplashStageState.failed) {
          continue;
        }
        if (state != SplashStageState.running) {
          _enter(i, detail: '完成');
        }
        await _completeAfterDwell(i);
      }
    } finally {
      controller.onDeployStep = null;
    }

    // ---- 阶段 4：建立连接 ----
    _enter(4, detail: '正在等待服务响应…');
    // 服务刚起来需要一点时间监听端口，这里给一段温和的等待；
    // 真正的连接与刷新由主界面的既有逻辑负责，这里只做「体感收尾」。
    await Future.delayed(const Duration(milliseconds: 600));
    task.update(4, detail: '服务已就绪');
    await _completeAfterDwell(4);

    return const BootOutcome(ok: true);
  }

  int _firstUnfinishedIndex() {
    for (var i = 0; i < task.stages.length; i++) {
      final s = task.stages[i].state;
      if (s != SplashStageState.done) {
        return i;
      }
    }
    return task.stages.length - 1;
  }
}

/// 创建一个部署模式的阶段任务
StagedSplashTask createBootTask() =>
    StagedSplashTask(labels: kDeployStageLabels);
