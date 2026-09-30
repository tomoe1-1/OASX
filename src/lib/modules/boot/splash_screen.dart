/// OASX 启动动画页
///
/// 参考「深色科技 HUD」开机动画的调性：深空蓝黑底 → 少女线稿勾勒
/// → 扫描光带实体化 → 睁眼 → 打字机标题 + HUD 装饰。
///
/// 设计约束：
/// - **可跳过**：点击画面或按任意键立即结束，不绑架用户
/// - **尊重无障碍**：系统开启「减少动态效果」时直接呈现静态终态
/// - **立绘驱动**：主体是 `assets/splash/` 下的少女立绘（闭眼/睁眼 ×
///   实体/线稿四张），其余 HUD 由 [CustomPainter] 绘制
/// - **锁定青蓝**：不跟随用户主题，保证品牌时刻的色相稳定
library;

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;
import 'package:flutter/services.dart' show rootBundle;
import 'package:oasx/modules/boot/splash_decor.dart';
import 'package:oasx/modules/boot/splash_deploy_panel.dart';
import 'package:oasx/modules/boot/splash_motto.dart';
import 'package:oasx/modules/boot/splash_painter.dart';
import 'package:oasx/modules/boot/splash_palette.dart';
import 'package:oasx/modules/boot/splash_task.dart';
import 'package:oasx/utils/platform_utils.dart';
import 'package:window_manager/window_manager.dart';

/// 主标题（打字机逐字显现）
const String kSplashTitle = 'OASX';

// 字标下方的一行信息由「日期 + 每日语录」组成，取代原先的固定副标题
// 「OAS 工作模式」。取内容与排版规则的逻辑都在 `splash_motto.dart`。

/// 启动动画总时长（供外部排期与测试引用）
Duration get splashTotalDuration => SplashPainter.totalDuration;

/// 把启动动画叠在主界面之上的容器。
///
/// 主界面在底层**已经构建完成**，启动动画盖在上面 —— 这样淡出时
/// 底下是真界面而非空屏，观感连续。动画结束或用户跳过后淡出移除。
class SplashGate extends StatefulWidget {
  const SplashGate({super.key, required this.child, this.duration, this.task});

  /// 主界面
  final Widget child;

  /// 覆盖动画时长，便于测试
  final Duration? duration;

  /// 数据源：部署模式传入 [StagedSplashTask]，品牌模式留空
  final SplashTask? task;

  @override
  State<SplashGate> createState() => _SplashGateState();
}

class _SplashGateState extends State<SplashGate> {
  bool _visible = true;
  bool _fadingOut = false;
  bool _mounted_ = true;
  Timer? _fadeTimer;

  static const Duration _fadeOut = Duration(milliseconds: 340);

  @override
  void initState() {
    super.initState();
    // 窗口显示兜底。
    //
    // Windows runner 靠 `SetNextFrameCallback(() => Show())` 显示窗口，
    // 该回调只在「下一个渲染帧完成」时触发。启动动画这一层如果让首帧
    // 迟迟不落地，窗口就会一直停在 `SW_HIDE`（进程活着但没有可见窗口）。
    //
    // 这里在首帧渲染后主动调一次 `show()`：`windowManager.show()` 是幂等的，
    // 若 runner 已经显示过则只是一次空操作，但能把时序风险兜住。
    // 用 postFrameCallback 而非 initState 直调，确保调用时至少已有一帧布局。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_mounted_) {
        return;
      }
      unawaited(_ensureWindowVisible());
    });
  }

  Future<void> _ensureWindowVisible() async {
    if (!PlatformUtils.isDesktop) {
      return;
    }
    try {
      await windowManager.ensureInitialized();
      if (await windowManager.isVisible()) {
        return;
      }
      await windowManager.show();
      await windowManager.focus();
    } catch (_) {
      // 窗口插件不可用时静默降级：不显示也仅仅是窗口不弹出，
      // 不应该因为兜底逻辑失败而影响主流程。
    }
  }

  void _onSplashFinished() {
    if (!_mounted_ || !_visible || _fadingOut) {
      return;
    }
    setState(() => _fadingOut = true);
    // 淡出完成后彻底移除节点，不留常驻空 widget。
    _fadeTimer = Timer(_fadeOut, () {
      if (_mounted_) {
        setState(() => _visible = false);
      }
    });
  }

  @override
  void dispose() {
    _mounted_ = false;
    _fadeTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;

    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        widget.child,
        if (_visible)
          AnimatedOpacity(
            opacity: _fadingOut ? 0.0 : 1.0,
            duration: reduceMotion ? Duration.zero : _fadeOut,
            curve: Curves.easeOut,
            child: SplashScreen(
              onFinished: _onSplashFinished,
              duration: widget.duration,
              task: widget.task,
            ),
          ),
      ],
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({
    super.key,
    required this.onFinished,
    this.duration,
    this.task,
  });

  /// 动画结束（或用户跳过）时回调，由调用方负责移除启动层
  final VoidCallback onFinished;

  /// 覆盖动画时长，便于测试与调试（仅品牌模式生效）
  final Duration? duration;

  /// 数据源。
  ///
  /// - `null` → 品牌模式：固定时长动画，左侧画字标
  /// - [TimedSplashTask] → 品牌模式，进度由本地计时器推进
  /// - [StagedSplashTask] → 部署模式：进度由真实部署阶段驱动，
  ///   左侧画进度面板，动画时长 = 部署耗时
  final SplashTask? task;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _controller;

  /// 星尘独立时钟：与主动画解耦，让星星持续漂移
  late final Ticker _starTicker;
  double _starTime = 0;

  final StarField _starField = StarField(count: 130);

  /// 键盘监听用的 FocusNode。
  /// 必须持有而非每次 build 新建 —— 否则每帧都换 node，
  /// 会连带触发焦点重排，干扰窗口首帧的 Show 回调。
  final FocusNode _focusNode = FocusNode(debugLabel: 'splash');

  bool _finished = false;

  /// 任务模式下的进度订阅与状态
  StreamSubscription<void>? _taskSub;
  double _taskProgress = 0;
  bool _finishScheduled = false;

  /// 当前数据源（可能为 null → 纯品牌模式）
  SplashTask? get _task => widget.task;

  /// 字标下方的「日期 + 每日语录」。
  ///
  /// **在字段初始化时算一次**，不是每帧计算 —— 因为 painter 每帧都会读它，
  /// 而 `DateTime.now()` 是变的：若每帧取一次，跨零点那一刻画面上会突然跳字。
  /// 一次求值也保证同一次启动内这一组内容恒定。
  late final String _dateText = formatSplashDate(DateTime.now());
  late final String _mottoText = mottoFor(DateTime.now());

  /// 立绘解码结果：闭眼/睁眼 × 实体/线稿
  ui.Image? _artClosed;
  ui.Image? _artOpen;
  ui.Image? _artClosedWire;
  ui.Image? _artOpenWire;
  ui.Image? _artCornerRepair;

  Duration get _totalDuration => widget.duration ?? SplashPainter.totalDuration;

  /// 预解码立绘资源。
  ///
  /// 用 `instantiateImageCodec` 而非 `Image.asset` —— 拿到的是裸 [ui.Image]，
  /// 可以在 [CustomPainter] 里用 `drawImageRect` + 自定义 blendMode 直接合成，
  /// 也避免了 `Image` widget 自带的解码缓存与生命周期管理开销。
  Future<void> _loadArt() async {
    Future<ui.Image?> decode(String path) async {
      try {
        final data = await rootBundle.load(path);
        final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
        try {
          final frame = await codec.getNextFrame();
          return frame.image;
        } finally {
          codec.dispose();
        }
      } catch (_) {
        return null; // 缺资源时降级到几何线框，不让启动流程失败
      }
    }

    final results = await Future.wait(<Future<ui.Image?>>[
      decode(SplashArt.closedSolid),
      decode(SplashArt.openSolid),
      decode(SplashArt.closedWire),
      decode(SplashArt.openWire),
      decode(SplashArt.cornerRepair),
    ]);
    if (!mounted) {
      for (final image in results) {
        image?.dispose();
      }
      return;
    }
    setState(() {
      _artClosed = results[0];
      _artOpen = results[1];
      _artClosedWire = results[2];
      _artOpenWire = results[3];
      _artCornerRepair = results[4];
    });
  }

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(vsync: this, duration: _totalDuration);

    unawaited(_loadArt());

    _starTicker = createTicker((elapsed) {
      final t = elapsed.inMicroseconds / 1e6;
      // 只在有可见变化时重建，避免无意义的 60fps setState
      if ((t - _starTime).abs() > 1 / 30) {
        setState(() => _starTime = t);
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      final disableAnimations =
          MediaQuery.maybeDisableAnimationsOf(context) ?? false;

      if (disableAnimations) {
        // 无障碍：直接落终态并立即交棒
        _controller.value = 1.0;
        _starTime = 0.6;
        _finish();
        return;
      }

      _starTicker.start();

      if (_task != null) {
        // ---- 任务模式：进度来自外部任务，不用 controller 自己跑 ----
        _taskSub = _task!.changes.listen((_) {
          if (!mounted) {
            return;
          }
          setState(() {
            _taskProgress = _task!.overallProgress;
          });
          // 任务结束 → 走收尾（品牌模式等 controller 走完，
          // 部署模式由任务自身状态决定）
          if (_task!.isFinished) {
            _finishFromTask();
          }
        });
        // 兜底拉一次初始状态（任务可能在挂载前就已开始推进）
        setState(() => _taskProgress = _task!.overallProgress);
        if (_task!.isFinished) {
          _finishFromTask();
        }
        return;
      }

      // ---- 品牌模式：controller 按固定时长推进 ----
      _controller.forward();
      _controller.addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          // 尾部驻留：动画走完不立刻切走，让「睁眼终态」停留一拍。
          // 否则睁眼刚完成就被主界面顶掉，用户根本看不到睁开的眼睛。
          Timer(const Duration(milliseconds: 720), () {
            if (mounted) {
              _finish();
            }
          });
        }
      });
    });
  }

  /// 任务驱动模式下，任务结束后延迟一小段时间再交棒 ——
  /// 让「完成」态（进度条满格 + 阶段全绿）在画面上停留一拍，
  /// 否则用户看不到收尾。
  void _finishFromTask() {
    if (_finishScheduled) {
      return;
    }
    _finishScheduled = true;
    final holdMs = widget.task is StagedSplashTask ? 900 : 400;
    Timer(Duration(milliseconds: holdMs), () {
      if (mounted) {
        _finish();
      }
    });
  }

  void _finish() {
    if (_finished || !mounted) {
      return;
    }
    _finished = true;
    // 结束后停止持续绘制星尘。调用方可能继续保留启动页一小段时间，
    // 此时只需显示终态；常驻 ticker 会让页面持续重绘。
    _starTicker.stop();
    widget.onFinished();
  }

  void _skip() {
    // 部署进行中不允许跳过：正在装东西，点掉会让人误以为已经装好。
    if (_finished || (_task != null && !_task!.canSkip)) {
      return;
    }
    _controller.stop();
    _starTicker.stop();
    _finish();
  }

  @override
  void dispose() {
    _taskSub?.cancel();
    _focusNode.dispose();
    _starTicker.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 启动动画固定用「深空青蓝」配色，不跟随用户主题。
    //
    // 理由：启动动画是品牌时刻，色相应该稳定 —— 参考视频的视觉锚点就是
    // 蓝青霓虹（#1E5FD8 / #2FE8C8）。若跟随主题，切到紫色主题时整幅
    // 画面会变紫，和少女立绘的固有青蓝打起来。
    const palette = SplashPalette.deepSpace;

    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;

    return Scaffold(
      backgroundColor: palette.backdropBottom,
      // 用 LayoutBuilder 拿到 body 的真实约束尺寸，显式喂给 CustomPaint。
      // 之前用 size: Size.infinite 时，绘制区尺寸与约束不一致，
      // 导致整幅画面偏移（实测约 +243, +94）、外环被右边缘裁切。
      body: LayoutBuilder(
        builder: (context, constraints) {
          final canvasSize = Size(
            constraints.maxWidth.isFinite ? constraints.maxWidth : 0,
            constraints.maxHeight.isFinite ? constraints.maxHeight : 0,
          );
          return SizedBox.fromSize(
            size: canvasSize,
            child: KeyboardListener(
              focusNode: _focusNode,
              onKeyEvent: (_) => _skip(),
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _skip,
                  child: AnimatedBuilder(
                    animation: _controller,
                    builder: (context, _) {
                      final task = _task;
                      // 进度来源：有任务用任务进度，否则用 controller
                      final double progress;
                      SplashPanelData? panel;
                      if (task != null) {
                        progress = _taskProgress;
                        // 从「进行中」的阶段取一句细节文案放底部
                        String statusLine = '';
                        for (final s in task.stages) {
                          if (s.state == SplashStageState.running) {
                            statusLine = s.detail.isEmpty ? s.label : s.detail;
                            break;
                          }
                        }
                        panel = SplashPanelData(
                          stages: task.stages,
                          overallProgress: _taskProgress,
                          failed: task.hasFailed,
                          statusLine: statusLine,
                        );
                      } else {
                        progress = _controller.value;
                      }

                      return CustomPaint(
                        size: canvasSize,
                        isComplex: true,
                        willChange: true,
                        painter: SplashPainter(
                          progress: progress,
                          palette: palette,
                          stars: _starField.stars,
                          starTime: _starTime,
                          titleText: kSplashTitle,
                          dateText: _dateText,
                          mottoText: _mottoText,
                          reduceMotion: reduceMotion,
                          textScaler: MediaQuery.textScalerOf(context),
                          artClosed: _artClosed,
                          artOpen: _artOpen,
                          artClosedWire: _artClosedWire,
                          artOpenWire: _artOpenWire,
                          artCornerRepair: _artCornerRepair,
                          panelData: panel,
                          // 部署模式跳过开场线稿期：切模式时本层会因 key
                          // 变化而重建，不偏移就会从深空重播一遍。
                          progressBias: task != null ? 0.24 : 0.0,
                          // 部署进行中不允许跳过（`_skip()` 同判），
                          // 底部提示据此换成「请勿关闭窗口」的静态文字。
                          skippable: task?.canSkip ?? true,
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
