import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/scheduler.dart';
import 'package:oasx/utils/eye_motion.dart';
import 'package:oasx/config/design_tokens.dart';
import 'package:oasx/modules/home/models/home_workbench_layout.dart';

/// 主界面底衬：正面人物与星空随整个软件窗口缓慢漂移、等比铺满。
/// [HomeBackdropScaffold] 让标题栏和正文透出同一幅画面及同一个动画。
/// 绘制出血明确裁在软件区域内；缺失资源时保留深色底，不露出桌面。
/// 宽画幅不可用时回退到旧的立绘动画、静态图；下列舞台参数仅用于回退。
/// 系统开启「减少动态效果」时保留首帧并停止推进。
class HomeBackdrop extends StatefulWidget {
  const HomeBackdrop({super.key, this.child});

  /// 叠在底衬之上的界面内容。
  final Widget? child;

  @override
  State<HomeBackdrop> createState() => _HomeBackdropState();
}

/// One continuous background for the entire home window, including its caption.
class HomeBackdropScaffold extends StatelessWidget {
  const HomeBackdropScaffold({super.key, this.appBar, required this.body});

  final PreferredSizeWidget? appBar;
  final Widget body;

  @override
  Widget build(BuildContext context) => HomeBackdrop(
    child: Scaffold(
      backgroundColor: Colors.transparent,
      appBar: appBar,
      body: body,
    ),
  );
}

/// 立绘资源逻辑尺寸。
///
/// 注意：这里只参与比值运算（画幅宽 = 画幅高 × 宽/高），位图的真实像素
/// 尺寸以解码结果为准 —— 动画帧是 740×1120（解码耗时决定帧率上限），
/// 静态海报是 1480×2240（高分屏 1:1），两者比值相同，绘制公式不变。
/// 取这么大不是「以为能变清晰」，而是为了**减少重采样次数**，
/// 详见 `tools/build_home_backdrop_asset.py` 头注的重采样链分析。
const double _kArtWidth = 1480;
const double _kArtHeight = 2240;

/// 画布高度相对窗口高度的比例。
///
/// 1.1 是第二版素材（头肩特写）的值：立绘是**全高人像** —— 顶部
/// 出血 10%（发顶自然裁掉）、底边贴窗口下缘，主体占满窗口高。
/// 旧值 1.6 是为「全窗氛围」素材设计的 ——
/// 画幅被放得很大、脸落在窗口右上区域，人物只以约 20% 的透过率从
/// 半透明面板后面隐约可见（用户反馈「只有黑块」）。
///
/// 现在「可见性」由右侧的**立绘舞台**承担（见 [backdropStageWidth]）：
/// 详情面板右缘收进一条无面板区，立绘的脸完整落在舞台里、以
/// [_kOpacity] 全亮度显示；身体其余部分照旧透过面板做氛围。
const double _kHeightRatio = 1.1;

/// 画布的垂直锚点：立绘中心相对窗口高的位置。
///
/// 0.45 约等于垂直居中；立绘上下都超出窗口，自然裁切。
const double _kAnchorY = 0.45;

/// 三栏布局的最小总宽：左栏 340 + 分割缝 16 + 详情 360 + 分割缝 16
/// + 日志 360（常量来自 `home_workbench_layout.dart`）。
///
/// 舞台是「奢侈品」：只有三栏最低需求**之外**还有富余时才让出。
const double _kThreePaneFloorWidth =
    kHomeWorkbenchDefaultCollectionWidth +
    kHomeWorkbenchDividerWidth +
    kHomeWorkbenchMinDetailsWidth +
    kHomeWorkbenchDividerWidth +
    kHomeWorkbenchMinLogWidth;

/// 右缘「立绘舞台」宽度 —— 工作台给底衬让出的**无面板区**。
///
/// [workbenchWidth] 是**工作台内容宽**（窗口宽 − 左右页边距），与
/// `home_view_actions.dart` 的 `Padding.all(Spacing.md)` 对应：
/// 布局侧（`home_workbench_body.dart`）的 `constraints.maxWidth`
/// 正是这个值；painter 侧用 `size.width − 2×Spacing.md` 换算。
/// 两侧必须共用本函数，否则脸会错位出舞台。
///
/// 宽度分两步定：
/// 1. **理想值**：脸在显示尺寸下约占 0.24×窗口高 ≈ 0.13×窗口宽，
///    按窗口宽 13% 缩放、夹在 [120, 300]（下限保住完整双眼，
///    上限防止超宽屏上舞台变成一条空走廊）；
/// 2. **让步**：工作台宽度不够「三栏最低需求 + 舞台」时，舞台从
///    理想值往下缩，让无可让就到 0 —— 舞台是装饰，三栏布局是
///    功能，装饰永远给功能让路。
double backdropStageWidth(double workbenchWidth) {
  final ideal = (workbenchWidth * 0.13).clamp(120.0, 300.0).toDouble();
  final affordable = (workbenchWidth - _kThreePaneFloorWidth)
      .clamp(0.0, ideal)
      .toDouble();
  return affordable;
}

/// 水平锚点：立绘锚点距窗口右缘 = 舞台宽的一半 + 页边距。
///
/// 输入同样是工作台内容宽（见 [backdropStageWidth]），返回值换算回
/// **窗口坐标** —— 舞台列的右缘贴着窗口右缘内缩一个页边距，立绘
/// 锚点（脸中心）落在舞台正中。
///
/// 用「距右缘偏移」而不是窗口宽比例：舞台宽度不随宽高比变化，
/// 锚点跟着舞台走才能保证**脸永远落在舞台中心**（眼睛是立绘的
/// 识别核心）。历史值 0.95（窗口宽比例）是第一版「全窗氛围」
/// 构图用的，舞台方案下不再需要。
double backdropAnchorFromRight(double workbenchWidth) {
  return backdropStageWidth(workbenchWidth) / 2 + Spacing.md;
}

/// 立绘在画布内的水平锚点（素材里的横向位置）。
///
/// 素材是头肩特写，**脸中心（双眼中点）约在素材 x=0.52** —— 由
/// 1280×800 实际渲染发现原值 0.52 仍让右眼贴近窗口边缘，
/// 取 0.58 将人像左移约 35px，让双眼完整留在画布内。改素材构图时这里要
/// 同步（生成脚本 `build_home_backdrop_anim_v2.py` 的 CROP_BOX
/// 决定脸的位置）。
const double _kArtAnchorX = 0.58;

/// 底衬整体不透明度。
///
/// 素材生成时已按「低亮度、保色相」处理（`build_home_backdrop_anim_v2.py`
/// 的 TARGET_BRIGHTNESS + 左侧渐变压暗），0.80 足够让发丝肌理与青色
/// 眼睛清晰可见。可读性**不**靠这个值兜底 —— 靠舞台把脸挪出文字区
/// （[backdropStageWidth]）、半透明面板、以及逐帧
/// 真实几何验收（`tools/measure_real_geometry.py`）。
const double _kOpacity = 0.80;

/// 全屏氛围底的不透明度。
///
/// 氛围底本身就是「压暗后的深空 + 少女柔光」（生成脚本里均值 26/255），
/// 不需要再打折；留 0.08 是让主题 surface 色仍能透上来一点，切到别的
/// 主题种子色时暗部色相会跟着走，不会是一块死板的固定蓝。
const double _kAmbientOpacity = 0.92;

/// 左侧渐隐的起点与终点（占窗口宽的比例）。
///
/// ## 方向不能写反（踩过的坑：立绘整块消失）
///
/// 渐隐是用 `BlendMode.dstIn` 做的 —— 语义是「dst 乘以 **src 的 alpha**」。
/// 所以渐变色里**透明的那端 = 立绘被擦掉的那端**。要做「左侧淡出、
/// 右侧保留」，渐变必须写成 [起点全透明 → 终点不透明]；写反了立绘会
/// 在窗口右半部被整体擦成 0 alpha，而立绘恰恰锚在右缘舞台上 —— 表现是
/// 「代码在跑、日志无报错、画面上什么都没有」。
///
/// 取值：起点 0.26 要早于双栏分割缝（约 0.36），否则缝隙里只剩纯表面色；
/// 终点 0.62 之后立绘满强度，覆盖详情/日志面板与舞台。
const double _kFadeLeftStart = 0.26;
const double _kFadeLeftEnd = 0.62;

/// 渐隐两端的颜色：**起点必须透明，终点必须不透明**。
///
/// 单独提成常量是为了让 `backdropFadeLeftColors()` 把方向暴露给
/// 测试 —— 方向写反不会报任何错，只会让立绘整块消失（真实事故，
/// 见 [backdropFadeLeftColors] 的文档注释）。
const Color _kFadeLeftStartColor = Color(0x00FFFFFF);
const Color _kFadeLeftEndColor = Color(0xFFFFFFFF);

/// 左侧渐隐的方向探针：`(起点色, 终点色)`。
///
/// ## 为什么值得一个测试
///
/// 渐隐用 `BlendMode.dstIn` 实现 —— dst 乘以 **src 的 alpha**，所以
/// **透明的那端就是被擦掉的那端**。做「左侧淡出、右侧保留」时渐变必须
/// `[起点透明 → 终点不透明]`；写反没有任何编译期或运行期征兆，
/// 立绘却在窗口右半部被整体擦成 0 alpha —— 而立绘恰恰锚在右缘舞台上，
/// 表现就是「代码在跑、日志无报错、画面上什么都没有」。
/// 测试钉住 `起点alpha < 终点alpha`，方向一反立即红。
@visibleForTesting
({Color start, Color end}) backdropFadeLeftColors() =>
    (start: _kFadeLeftStartColor, end: _kFadeLeftEndColor);

/// 上下渐隐带的高度（占窗口高比例）。
const double _kFadeBandY = 0.10;

/// Rest closed, wake slowly, hold open, then close gently once per 18 seconds.
@visibleForTesting
double backdropEyeOpening(double seconds) {
  final t = seconds % 18;
  if (t < 0.7) return 0;
  if (t < 4.3) return Curves.easeInOutCubic.transform((t - 0.7) / 3.6);
  if (t < 16.8) return 1;
  return 1 - Curves.easeInOutCubic.transform((t - 16.8) / 1.2);
}

class _HomeBackdropState extends State<HomeBackdrop>
    with SingleTickerProviderStateMixin {
  /// 正面立绘与星空同在一张宽画幅里，作为主页首选底图。
  static const String _kFullAsset = 'assets/images/main_bg_muse_front_full.png';

  /// 动画源（参考视频「已渲染段」的乒乓循环，100 帧 / 每帧 83ms）。
  /// 生成与验收：`tools/build_home_backdrop_anim.py`。
  static const String _kAnimAsset = 'assets/images/main_bg_muse_anim.webp';

  /// 静态回退源（动画加载失败 / 单帧异常时使用）。
  static const String _kStaticAsset = 'assets/images/main_bg_muse.jpg';

  /// 全屏氛围底（深空径向渐变 + 少女重度模糊柔光，1600×900）。
  ///
  /// 生成与取色依据：`tools/build_home_backdrop_ambient.py`。
  /// 它是「背景全覆盖」的那一层 —— 立绘是竖构图，物理上铺不满横屏，
  /// 靠这一层把深空底色和人物的青光铺到窗口每一个像素。
  /// 加载失败只是少了氛围，立绘与界面照常，不降级。
  static const String _kAmbientAsset = 'assets/images/main_bg_muse_ambient.jpg';

  /// 帧时长兜底值：正常路径用帧自带的 duration 推进，
  /// 只防个别编码器给出 0 时长导致空转。
  static const Duration _kFallbackFrameDuration = Duration(milliseconds: 83);

  ui.Image? _art;
  ui.Image? _ambient;
  ui.Image? _fullArt;
  ui.Image? _closedEyes;
  List<ui.Image> _eyeFrames = const <ui.Image>[];
  EyeMotion? _eyeMotion;
  final _motionClock = _BackdropClock();
  late final Ticker _motionTicker;
  double _motionOrigin = 0;
  ui.Codec? _codec;

  /// 动画循环的世代号：dispose 时 +1，循环里的 `await` 返回后发现
  /// 世代变了就退出 —— 这是异步循环最可靠的取消方式。
  int _generation = 0;

  /// 已被替换下来的旧帧。**不能立即 dispose**：光栅线程可能还握着它
  /// 在合成当前帧，撞上会崩。延迟两帧再释放，届时必然不在屏幕上。
  final List<ui.Image> _graveyard = <ui.Image>[];

  /// 资源加载失败的原因；`null` 表示没失败（或尚未完成）。
  ///
  /// ## 为什么要把失败「记下来」而不是直接吞掉
  ///
  /// 这里原先写的是 `catch (_) {}`，理由是「底衬是装饰，读不到图不该阻塞
  /// 主界面」—— 这个判断本身没错，但**静默**带来过一次很贵的排查成本：
  ///
  /// 手工构建链少生成了 `AssetManifest.bin`（引擎只认 `.bin`，不认 `.json`），
  /// 于是 `rootBundle.load()` 抛异常、被这里吞掉、画面什么也不显示、
  /// 日志里一个字都没有。表现是「代码改了、构建也过了、跑起来毫无变化」，
  /// 从现象根本追不到原因。
  ///
  /// 现在的原则：**降级可以静默，失败不可以**。
  /// 降级行为不变（仍回退成纯表面色，不阻塞界面），
  /// 但把原因留在字段上，并在 debug 构建里打一行日志。
  Object? _loadError;

  bool _animated = false;

  @override
  void initState() {
    super.initState();
    _motionTicker = createTicker((elapsed) {
      _motionClock.advance((_motionOrigin + elapsed.inMicroseconds / 1e6) % 18);
    });
    unawaited(_load());
    unawaited(_loadAmbient());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_fullArt != null) _updateMotion();
  }

  void _updateMotion() {
    _motionTicker.stop();
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _motionClock.advance(4.3, stationary: true);
      return;
    }
    _motionOrigin = _motionClock.seconds;
    _motionTicker.start();
  }

  Future<void> _loadAmbient() async {
    try {
      final data = await rootBundle.load(_kAmbientAsset);
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
      final frame = await codec.getNextFrame();
      codec.dispose();
      if (!mounted) {
        frame.image.dispose();
        return;
      }
      setState(() => _ambient = frame.image);
    } catch (error) {
      assert(() {
        // ignore: avoid_print
        print('[HomeBackdrop] 氛围底加载失败: $error');
        return true;
      }());
    }
  }

  Future<void> _load() async {
    final List<Object> errors = <Object>[];

    // ---- ① 正面宽画幅：覆盖整个软件内容区 ----
    try {
      final data = await rootBundle.load(_kFullAsset);
      final fullCodec = await ui.instantiateImageCodec(
        data.buffer.asUint8List(),
      );
      final frame = await fullCodec.getNextFrame();
      fullCodec.dispose();
      if (!mounted) {
        frame.image.dispose();
        return;
      }
      await _loadClosedEyes();
      await _loadEyeFrames(frame.image);
      if (!mounted) {
        frame.image.dispose();
        return;
      }
      setState(() => _fullArt = frame.image);
      _updateMotion();
      return;
    } catch (e) {
      errors.add(e);
    }

    // ---- ② 旧动画 WebP（宽画幅不可用时回退） ----
    ui.Codec? codec;
    try {
      final data = await rootBundle.load(_kAnimAsset);
      codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
      if (codec.frameCount <= 1) {
        // 单帧的「动画」= 编码出了问题（只编进了最后一帧之类），
        // 当作动画失败处理，回退静态。
        errors.add(StateError('$_kAnimAsset 只有 ${codec.frameCount} 帧，视为编码异常'));
        codec.dispose();
        codec = null;
      }
    } catch (e) {
      errors.add(e);
      codec?.dispose();
      codec = null;
    }

    if (codec != null) {
      if (!mounted) {
        codec.dispose();
        return;
      }
      _codec = codec;
      _animated = true;
      unawaited(_runAnimation(codec));
      return;
    }

    // ---- ③ 旧静态 jpg 回退 ----
    try {
      final data = await rootBundle.load(_kStaticAsset);
      final staticCodec = await ui.instantiateImageCodec(
        data.buffer.asUint8List(),
      );
      final frame = await staticCodec.getNextFrame();
      staticCodec.dispose();
      if (!mounted) {
        frame.image.dispose();
        return;
      }
      setState(() => _art = frame.image);
    } catch (e) {
      errors.add(e);
      // 失败原因必须可见：debug 下打日志，同时存字段供测试断言。
      // 不要改回 `catch (_) {}` —— 见 _loadError 的文档注释。
      assert(() {
        // ignore: avoid_print
        print(
          '[HomeBackdrop] 底衬资源加载失败，已降级为纯表面色。\n'
          '  尝试过：$_kFullAsset → $_kAnimAsset → $_kStaticAsset\n'
          '  原因链：${errors.join(' | ')}\n'
          '  排查：确认 flutter_assets/AssetManifest.bin 含这两个条目'
          '（运行 tools/sync_asset_manifest.py --verify）。',
        );
        return true;
      }());
      if (mounted) {
        setState(() => _loadError = errors.last);
      } else {
        _loadError = errors.last;
      }
    }
  }

  Future<void> _loadClosedEyes() async {
    ui.Codec? codec;
    try {
      final data = await rootBundle.load(
        'assets/images/main_bg_muse_front_closed.png',
      );
      codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
      final frame = await codec.getNextFrame();
      if (!mounted) {
        frame.image.dispose();
        return;
      }
      setState(() => _closedEyes = frame.image);
    } catch (error) {
      debugPrint('[HomeBackdrop] Closed eye asset unavailable: $error');
    } finally {
      codec?.dispose();
    }
  }

  Future<void> _loadEyeFrames(ui.Image open) async {
    final frames = <ui.Image>[];
    try {
      for (final name in ['quarter', 'half', 'three_quarter']) {
        final data = await rootBundle.load(
          'assets/images/main_bg_muse_front_eye_$name.png',
        );
        final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
        try {
          frames.add((await codec.getNextFrame()).image);
        } finally {
          codec.dispose();
        }
      }
      if (!mounted) {
        for (final image in frames) {
          image.dispose();
        }
        return;
      }
      EyeMotion? motion;
      if (_closedEyes != null) {
        try {
          motion = await EyeMotion.prepareHome([_closedEyes!, ...frames, open]);
        } catch (error) {
          debugPrint('[HomeBackdrop] Eye texture preparation failed: $error');
        }
      }
      if (!mounted) {
        motion?.dispose();
        for (final image in frames) {
          image.dispose();
        }
        return;
      }
      if (motion != null) {
        for (final image in frames) {
          image.dispose();
        }
        setState(() => _eyeMotion = motion);
      } else {
        setState(() => _eyeFrames = frames);
      }
    } catch (error) {
      for (final image in frames) {
        image.dispose();
      }
      debugPrint('[HomeBackdrop] Intermediate eye frames unavailable: $error');
    }
  }

  /// 逐帧推进循环：以**帧自带的时长**自-paced（100ms/帧由编码写入），
  /// 循环由世代号或 codec 错误终止。
  Future<void> _runAnimation(ui.Codec codec) async {
    final gen = ++_generation;
    ui.Image? previous;
    while (mounted && gen == _generation) {
      final ui.FrameInfo info;
      try {
        info = await codec.getNextFrame();
      } catch (_) {
        // 解码到头或 codec 已释放。文件声明 loop=0（无限循环），
        // 正常永远不会走到；真走到了就停在当前帧。
        break;
      }
      if (!mounted || gen != _generation) {
        info.image.dispose();
        break;
      }
      setState(() => _art = info.image);
      if (previous != null) {
        _graveyard.add(previous);
        while (_graveyard.length > 2) {
          _graveyard.removeAt(0).dispose();
        }
      }
      previous = info.image;
      // 尊重系统「减少动态效果」：首帧照常解码显示，之后不再推进 ——
      // 内容正确，只去掉运动。前庭障碍用户约 35%，这不是可选项。
      if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
        break;
      }
      final d = info.duration;
      await Future<void>.delayed(
        d <= Duration.zero ? _kFallbackFrameDuration : d,
      );
    }
  }

  /// 底衬当前是否处于降级状态（资源没加载出来）。
  ///
  /// 供测试断言「资源缺失时是**可见地**降级，而不是静默」。
  @visibleForTesting
  bool get isDegraded => _art == null && _loadError != null;

  /// 当前是否在播逐帧动画（静态回退时为 false）。
  @visibleForTesting
  bool get isAnimated => _animated || _motionTicker.isActive;

  @override
  void dispose() {
    _motionTicker.dispose();
    _motionClock.dispose();
    _generation++;
    _codec?.dispose();
    for (final image in _graveyard) {
      image.dispose();
    }
    _graveyard.clear();
    _art?.dispose();
    _ambient?.dispose();
    _fullArt?.dispose();
    _closedEyes?.dispose();
    _eyeMotion?.dispose();
    for (final image in _eyeFrames) {
      image.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final art = _art;
    final ambient = _ambient;
    final fullArt = _fullArt;
    return Stack(
      fit: StackFit.expand,
      children: [
        // The artwork deliberately overscans; clip only its paint so it cannot
        // leave a stale strip outside the software's drawing area after resize.
        ClipRect(
          child: RepaintBoundary(
            child: CustomPaint(
              painter: _BackdropPainter(
                image: art,
                ambient: ambient,
                fullImage: fullArt,
                motionClock: _motionClock,
                closedEyes: _closedEyes,
                eyeFrames: _eyeFrames,
                eyeMotion: _eyeMotion,
              ),
            ),
          ),
        ),
        if (widget.child != null) widget.child!,
      ],
    );
  }
}

class _BackdropClock extends ChangeNotifier {
  double seconds = 0;
  double phase = 0;
  void advance(double value, {bool stationary = false}) {
    seconds = value;
    phase = stationary ? 0 : value / 18;
    notifyListeners();
  }
}

class _BackdropPainter extends CustomPainter {
  _BackdropPainter({
    required this.image,
    required this.ambient,
    required this.fullImage,
    required this.motionClock,
    required this.closedEyes,

    required this.eyeFrames,
    required this.eyeMotion,
  }) : super(repaint: motionClock);

  final ui.Image? image;
  final ui.Image? ambient;
  final ui.Image? fullImage;
  final _BackdropClock motionClock;
  double get motionPhase => motionClock.phase;
  final ui.Image? closedEyes;
  double get eyeOpening => backdropEyeOpening(motionClock.seconds);
  final List<ui.Image> eyeFrames;
  final EyeMotion? eyeMotion;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    final surface = _surfaceOf();
    canvas.drawRect(Offset.zero & size, Paint()..color = surface);

    final full = fullImage;
    if (full != null) {
      // cover + 7% 出血：窗口任意拉伸后仍盖满边缘，轻微漂移也不露底。
      final scale =
          math.max(size.width / full.width, size.height / full.height) * 1.07;
      final width = full.width * scale;
      final height = full.height * scale;
      final phase = motionPhase * math.pi * 2;
      final left =
          (size.width - width) / 2 + math.sin(phase) * size.width * 0.012;
      final top =
          (size.height - height) / 2 + math.cos(phase) * size.height * 0.008;
      canvas.drawImageRect(
        full,
        Rect.fromLTWH(0, 0, full.width.toDouble(), full.height.toDouble()),
        Rect.fromLTWH(left, top, width, height),
        Paint()..filterQuality = FilterQuality.medium,
      );
      _paintEyes(canvas, full, Rect.fromLTWH(left, top, width, height));
      // 面板下压低高光；右侧正面人物保留更完整的蓝青细节。
      canvas.drawRect(
        Offset.zero & size,
        Paint()
          ..shader = ui.Gradient.linear(
            Offset.zero,
            Offset(size.width, 0),
            const <Color>[
              Color(0xAD061120),
              Color(0x80061120),
              Color(0x30061120),
            ],
            const <double>[0, 0.58, 1],
          ),
      );
      return;
    }

    // 氛围图按 cover 等比缩放，窗口拉伸时始终铺满，不露出硬边。
    final atmosphere = ambient;
    if (atmosphere != null) {
      final scale = math.max(
        size.width / atmosphere.width,
        size.height / atmosphere.height,
      );
      final width = atmosphere.width * scale;
      final height = atmosphere.height * scale;
      canvas.drawImageRect(
        atmosphere,
        Rect.fromLTWH(
          0,
          0,
          atmosphere.width.toDouble(),
          atmosphere.height.toDouble(),
        ),
        Rect.fromLTWH(
          (size.width - width) / 2,
          (size.height - height) / 2,
          width,
          height,
        ),
        Paint()
          ..filterQuality = FilterQuality.medium
          ..color = const Color.fromRGBO(255, 255, 255, _kAmbientOpacity),
      );
    }

    final image = this.image;
    if (image == null) return;

    // ---- 定位 ----
    final artH = size.height * _kHeightRatio;
    final artW = artH * (_kArtWidth / _kArtHeight);
    // 锚点函数的输入是「工作台内容宽」= 窗口宽 − 左右页边距，
    // 与 home_view_actions 的 Padding.all(Spacing.md) 对应 ——
    // 布局侧拿到的 constraints.maxWidth 正是同一个值。
    final left =
        size.width -
        backdropAnchorFromRight(size.width - 2 * Spacing.md) -
        artW * _kArtAnchorX;
    // 立绘中心对齐窗口高的 _kAnchorY 处，而不是简单居中 ——
    // 居中会让眼睛掉到面板下半区，跟日志正文挤在一起。
    final top = size.height * _kAnchorY - artH / 2;
    final rect = Rect.fromLTWH(left, top, artW, artH);

    // ---- 绘制 + 渐隐 ----
    //
    // 用 `saveLayer` 把「贴上立绘」和「左消隐」合成一次再整体降透明度，
    // 避免两层分别乘 alpha 时边缘出现叠加误差（缝隙里最容易看出来）。
    canvas.saveLayer(Offset.zero & size, Paint());
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      rect,
      Paint()
        ..filterQuality = FilterQuality.medium
        ..color = const Color.fromRGBO(255, 255, 255, _kOpacity),
    );

    // 左淡出、右保留。dstIn = dst × src.a，因此**透明端在起点**
    // （左侧被擦掉）。方向写反会让立绘从右侧舞台上彻底消失，
    // 详见 backdropFadeLeftColors / _kFadeLeftStart 的注释。
    final fade = Paint()
      ..blendMode = BlendMode.dstIn
      ..shader = ui.Gradient.linear(
        Offset(size.width * _kFadeLeftStart, 0),
        Offset(size.width * _kFadeLeftEnd, 0),
        <Color>[_kFadeLeftStartColor, _kFadeLeftEndColor],
      );
    canvas.drawRect(Offset.zero & size, fade);

    final band = _kFadeBandY * size.height;
    final vert = Paint()
      ..blendMode = BlendMode.dstIn
      ..shader = ui.Gradient.linear(
        Offset.zero,
        Offset(0, size.height),
        <Color>[
          const Color(0x00FFFFFF),
          const Color(0xFFFFFFFF),
          const Color(0xFFFFFFFF),
          const Color(0x00FFFFFF),
        ],
        <double>[0.0, band / size.height, 1 - band / size.height, 1.0],
      );
    canvas.drawRect(Offset.zero & size, vert);

    canvas.restore();
  }

  void _paintEyes(Canvas canvas, ui.Image open, Rect destination) {
    final closed = closedEyes;
    if (closed == null || eyeOpening >= 1) return;
    final frames = <ui.Image>[
      closed,
      if (eyeFrames.length == 3) ...eyeFrames,
      open,
    ];
    final position = eyeOpening.clamp(0.0, 1.0) * (frames.length - 1);
    final index = position.floor().clamp(0, frames.length - 2);
    final mix = position - index;
    canvas.save();
    canvas.translate(destination.left, destination.top);
    canvas.scale(destination.width / 1672, destination.height / 941);
    if (eyeMotion != null) {
      eyeMotion!.paint(canvas, eyeOpening);
      canvas.restore();
      return;
    }
    for (final patch in const [
      Rect.fromLTWH(1040, 340, 112, 82),
      Rect.fromLTWH(1200, 305, 112, 90),
    ]) {
      canvas.save();
      canvas.clipRRect(
        RRect.fromRectAndRadius(patch, const Radius.circular(18)),
      );
      for (final (image, alpha) in [
        (frames[index], 1.0),
        (frames[index + 1], mix),
      ]) {
        canvas.drawImageRect(
          image,
          Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
          const Rect.fromLTWH(0, 0, 1672, 941),
          Paint()
            ..filterQuality = FilterQuality.medium
            ..color = Color.fromRGBO(255, 255, 255, alpha),
        );
      }
      canvas.restore();
    }
    canvas.restore();
  }

  /// 取当前主题的表面色作底。
  ///
  /// 不用 `Theme.of` —— painter 拿不到 context，且底衬只需要
  /// 「和 scaffold 同色」这一个信息。用固定的深色即可，
  /// 色相差异由上面的立绘覆盖，肉眼不可辨。
  Color _surfaceOf() => const Color(0xFF0D1015);

  @override
  bool shouldRepaint(covariant _BackdropPainter old) =>
      old.image != image ||
      old.ambient != ambient ||
      old.fullImage != fullImage ||
      old.motionClock != motionClock ||
      old.closedEyes != closedEyes ||
      old.eyeFrames != eyeFrames ||
      old.eyeMotion != eyeMotion;
}

/// 主界面用的半透明面板填充色。
///
/// ## 为什么不改 `Surfaces.panel`
///
/// `Surfaces.panel` 是全项目共用的 —— 设置页、日志页的列表容器都取它。
/// 一旦全局改成半透明，那些**底下没有底衬**的页面就会透出 scaffold 的
/// 纯色，面板看起来像「褪色了」，是纯粹的负收益。
///
/// 所以这里只给主界面开一个口子：主界面有 [HomeBackdrop] 垫底，
/// 半透明才有意义。
///
/// 面板内部的任务行不跟着改 —— 它们本来就是 `Colors.transparent`
/// （只有选中态叠一层 `primaryContainer @ 28%`），会自然透出面板底色。
Color homePanelColor(BuildContext context) {
  final alpha = Theme.of(context).brightness == Brightness.dark ? 0.64 : 0.50;
  return Surfaces.panel(context).withValues(alpha: alpha);
}

/// 右侧工作台需要再透出一层背景，内部卡片仍保留文字底色。
Color homeSidebarPanelColor(BuildContext context) {
  final alpha = Theme.of(context).brightness == Brightness.dark ? 0.50 : 0.38;
  return Surfaces.panel(context).withValues(alpha: alpha);
}

Color homeSidebarCardColor(BuildContext context) {
  final alpha = Theme.of(context).brightness == Brightness.dark ? 0.58 : 0.44;
  return Surfaces.card(context).withValues(alpha: alpha);
}

/// 底衬的纵向留白（debug 用），不参与生产逻辑。
@visibleForTesting
double backdropDebugHeightRatio() => _kHeightRatio;

/// 底衬在窗口最窄处的最小可见宽度，保证小窗口下不会整块消失。
@visibleForTesting
double backdropMinVisibleWidth(double windowWidth) {
  return math.max(0, windowWidth * (1 - _kFadeLeftStart));
}
