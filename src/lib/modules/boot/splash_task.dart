/// 启动动画的任务模型
///
/// 启动动画有两种模式，由 [SplashTask] 驱动：
///
/// - [SplashTask.timed]：固定时长的品牌展示。OAS 已就绪时走这条，
///   定格一段仪式感画面后交棒主界面。
/// - [SplashTask.staged]：阶段驱动的进度可视化。OAS 未部署或需要重启
///   服务时走这条 —— 动画不再按固定时间推进，而是**跟随真实部署进度**，
///   装多久就演多久。
///
/// 两个模式的共同点是「进度 0–1 + 阶段列表」这两项抽象，绘制层只认它，
/// 不关心背后是计时器还是 git 子进程。
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

/// 单个阶段的运行状态
enum SplashStageState {
  /// 尚未开始
  pending,

  /// 进行中
  running,

  /// 已完成
  done,

  /// 失败
  failed,
}

/// 部署阶段
@immutable
class SplashStage {
  const SplashStage({
    required this.label,
    this.detail = '',
    this.state = SplashStageState.pending,
    this.progress = 0,
  });

  /// 阶段名（左侧面板主文案），如「拉取 OAS 仓库」
  final String label;

  /// 该阶段的补充说明（弱化小字），如「Cloning into 'OAS'...」
  final String detail;

  final SplashStageState state;

  /// 该阶段自身进度 0–1（-1 表示不确定进度，走脉冲动画）
  final double progress;

  SplashStage copyWith({
    String? label,
    String? detail,
    SplashStageState? state,
    double? progress,
  }) {
    return SplashStage(
      label: label ?? this.label,
      detail: detail ?? this.detail,
      state: state ?? this.state,
      progress: progress ?? this.progress,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is SplashStage &&
        other.label == label &&
        other.detail == detail &&
        other.state == state &&
        other.progress == progress;
  }

  @override
  int get hashCode => Object.hash(label, detail, state, progress);
}

/// 启动动画的数据源
abstract class SplashTask {
  /// 阶段列表（顺序固定，长度固定）
  List<SplashStage> get stages;

  /// 整体进度 0–1
  double get overallProgress;

  /// 是否已全部结束（成功或失败）
  bool get isFinished;

  /// 是否失败
  bool get hasFailed;

  /// 状态变化流 —— 绘制层订阅它来重建
  Stream<void> get changes;

  /// 用户是否可跳过。部署进行中不可跳过（正在装东西，
  /// 点掉会让人误以为装好了）。
  bool get canSkip;

  /// 释放资源
  void dispose();
}

/// 固定时长的品牌展示任务
///
/// 用 [AnimationController] 之外的方式驱动也行，但这里保持最简：
/// 由外部每帧喂进度，`isFinished` 由 `progress >= 1` 判定。
class TimedSplashTask implements SplashTask {
  TimedSplashTask({
    required this.stages,
    required this.duration,
  });

  @override
  final List<SplashStage> stages;

  final Duration duration;

  final StreamController<void> _changes = StreamController<void>.broadcast();

  double _progress = 0;

  /// 由外部（动画 ticker）每帧调用
  void setProgress(double value) {
    final next = value.clamp(0.0, 1.0);
    if (next == _progress) {
      return;
    }
    _progress = next;
    // 按整体进度点亮阶段
    _syncStageStates();
    if (!_changes.isClosed) {
      _changes.add(null);
    }
  }

  void _syncStageStates() {
    final n = stages.length;
    if (n == 0) {
      return;
    }
    for (var i = 0; i < n; i++) {
      final begin = i / n;
      final next = stages[i].state;
      if (_progress >= (i + 1) / n) {
        if (next != SplashStageState.done) {
          stages[i] = stages[i].copyWith(
            state: SplashStageState.done,
            progress: 1,
          );
        }
      } else if (_progress >= begin) {
        if (next != SplashStageState.running) {
          stages[i] = stages[i].copyWith(
            state: SplashStageState.running,
            progress: ((_progress - begin) * n).clamp(0.0, 1.0),
          );
        } else {
          stages[i] = stages[i].copyWith(
            progress: ((_progress - begin) * n).clamp(0.0, 1.0),
          );
        }
      }
    }
  }

  @override
  double get overallProgress => _progress;

  @override
  bool get isFinished => _progress >= 1.0;

  @override
  bool get hasFailed => false;

  @override
  Stream<void> get changes => _changes.stream;

  @override
  bool get canSkip => true;

  @override
  void dispose() {
    unawaited(_changes.close());
  }
}

/// 阶段驱动的部署任务 —— 由真实部署流程推送状态
///
/// 使用方式（在部署编排处）：
/// ```dart
/// final task = StagedSplashTask(labels: [...]);
/// task.begin(0);                       // 进入第 1 阶段
/// task.updateDetail(0, 'checking...'); // 更新细字
/// task.complete(0);                    // 第 1 阶段完成
/// task.fail(2, 'installer exited 1');  // 第 3 阶段失败
/// ```
class StagedSplashTask implements SplashTask {
  StagedSplashTask({required List<String> labels})
      : stages = labels
            .map((l) => SplashStage(label: l))
            .toList(growable: false);

  @override
  final List<SplashStage> stages;

  final StreamController<void> _changes = StreamController<void>.broadcast();

  bool _failed = false;

  int get _doneCount =>
      stages.where((s) => s.state == SplashStageState.done).length;

  void _emit() {
    if (!_changes.isClosed) {
      _changes.add(null);
    }
  }

  /// 进入第 [index] 阶段
  void begin(int index) {
    if (index < 0 || index >= stages.length) {
      return;
    }
    stages[index] = stages[index].copyWith(
      state: SplashStageState.running,
      progress: 0,
    );
    _emit();
  }

  /// 更新第 [index] 阶段的自身进度与细节文案
  void update(int index, {double? progress, String? detail}) {
    if (index < 0 || index >= stages.length) {
      return;
    }
    stages[index] = stages[index].copyWith(
      progress: progress,
      detail: detail,
    );
    _emit();
  }

  /// 第 [index] 阶段完成
  void complete(int index) {
    if (index < 0 || index >= stages.length) {
      return;
    }
    stages[index] = stages[index].copyWith(
      state: SplashStageState.done,
      progress: 1,
    );
    _emit();
  }

  /// 第 [index] 阶段失败
  void fail(int index, [String? detail]) {
    if (index < 0 || index >= stages.length) {
      return;
    }
    _failed = true;
    stages[index] = stages[index].copyWith(
      state: SplashStageState.failed,
      detail: detail,
    );
    _emit();
  }

  @override
  double get overallProgress {
    final n = stages.length;
    if (n == 0) {
      return 1;
    }
    // 已完成阶段整份计入，进行中阶段按自身进度折半计入，
    // 这样进度条不会在阶段切换时「跳一格」。
    var sum = 0.0;
    for (final s in stages) {
      switch (s.state) {
        case SplashStageState.done:
          sum += 1;
        case SplashStageState.running:
          sum += (s.progress < 0 ? 0.5 : s.progress * 0.5);
        case SplashStageState.failed:
        case SplashStageState.pending:
          break;
      }
    }
    return (sum / n).clamp(0.0, 1.0);
  }

  @override
  bool get isFinished => _failed || _doneCount == stages.length;

  @override
  bool get hasFailed => _failed;

  @override
  Stream<void> get changes => _changes.stream;

  /// 部署进行中不允许跳过 —— 正在装东西，点掉会造成「已装好」的错觉
  @override
  bool get canSkip => false;

  @override
  void dispose() {
    unawaited(_changes.close());
  }
}

/// 默认的阶段文案（部署模式）
const List<String> kDeployStageLabels = <String>[
  '检查运行环境',
  '拉取 OAS 仓库',
  '安装运行依赖',
  '启动 OAS 服务',
  '建立连接',
];

/// 快速模式的阶段文案（品牌展示）
const List<String> kBootStageLabels = <String>[
  'LOADING CORE',
  'LINKING OAS',
  'SYNCING CONFIG',
  'CALIBRATING',
  'READY',
];
