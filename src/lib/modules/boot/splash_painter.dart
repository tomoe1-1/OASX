/// 启动动画主绘制器
///
/// 画面分左右两块：
///
/// - **右侧**：少女立绘。线稿勾勒 → 扫描实体化 → 睁眼，三段式。
/// - **左侧**：品牌字标 + 部署面板，**两者可并存**（同一条左栏基线，
///   字标在上、面板在下）：
///   - 品牌模式（`panelData == null`）：只有字标，用完整尺寸，
///     作为画面的第二视觉锚点撑住左半边。
///   - 部署模式（`panelData != null`）：字标缩到左栏顶部（`compact`），
///     下方接部署进度面板。此时画面主角是进度，字标退为一行标识。
///
/// 时间轴（[progress] 是**整体进度**，不是固定时长）：
///
/// | 区段 | 内容 |
/// |---|---|
/// | 0.00–0.14 | 深空底 + 星尘点亮 |
/// | 0.04–0.26 | 少女线稿自暗转亮（快，一笔带过） |
/// | 0.10–0.34 | 品牌字标点亮（部署模式；品牌模式为 0.56–0.90） |
/// | 0.24–0.58 | 扫描光带自上而下，立绘实体化 |
/// | 0.54–0.94 | **睁眼**（占 0.40，3.6秒）—— 眼区扫描 + 瞳孔渐亮 |
/// | 0.68–0.99 | 虹膜高光炸开（覆盖整个睁眼过程） |
/// | 0.56–0.90 | 部署进度面板入场 |
/// | 0.96–1.00 | 收束高光，准备交棒 |
///
/// 睁眼为何要「慢且分段」：闭眼/睁眼两张立绘只差瞳孔像素，
/// 直接整张交叉淡入时屏幕唯一变动的只有几十个像素，
/// 人眼抓不到动作。所以这里用「眼区扫描光带扫过 → 瞳孔渐亮收缩 →
/// 冲击波扩散」三样显式信号，构成一个真正可读的睁眼事件。
///
/// 品牌模式下 [progress] 由 `AnimationController` 按固定时长推进；
/// 部署面板由真实部署阶段驱动，眼睑由独立时钟保证缓慢开启。
library;

import 'package:oasx/utils/eye_motion.dart';

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:oasx/modules/boot/splash_decor.dart';
import 'package:oasx/modules/boot/splash_deploy_panel.dart';
import 'package:oasx/modules/boot/splash_geometry.dart';
import 'package:oasx/modules/boot/splash_motto.dart';
import 'package:oasx/modules/boot/splash_palette.dart';

/// 阶段文案（品牌模式的左侧列表，保持英文 HUD 调性）
const List<String> kSplashStages = <String>[
  'LOADING CORE',
  'LINKING OAS',
  'SYNCING CONFIG',
  'CALIBRATING',
  'READY',
];

/// 立绘资源路径
class SplashArt {
  static const String closedSolid = 'assets/splash/girl_closed.jpg';
  static const String openSolid = 'assets/splash/girl_open.jpg';
  static const String closedWire =
      'assets/splash/girl_closed_wire_extended.png';
  static const String openWire = 'assets/splash/girl_open_wire_extended.png';
  static const String cornerRepair = 'assets/splash/girl_corner_repair.png';
}

class SplashPainter extends CustomPainter {
  SplashPainter({
    required this.progress,
    required this.palette,
    required this.stars,
    required this.starTime,
    required this.titleText,
    required this.dateText,
    required this.mottoText,
    required this.reduceMotion,
    required this.textScaler,
    required this.artClosed,
    required this.artOpen,
    required this.artClosedWire,
    required this.artOpenWire,
    this.artCornerRepair,
    this.eyeProgress,
    this.artEyeFrames = const <ui.Image?>[],
    this.eyeMotion,
    this.panelData,
    this.progressBias = 0.0,
    this.skippable = true,
  });

  /// 整体进度 0–1
  final double progress;
  final double? eyeProgress;
  final List<ui.Image?> artEyeFrames;
  final EyeMotion? eyeMotion;

  final SplashPalette palette;

  final List<Star> stars;

  /// 星尘独立时钟（秒），与 progress 解耦，让星星持续漂移
  final double starTime;

  /// 标题文字
  final String titleText;

  /// 字标下方的一行信息：日期（例：`2026 年 9 月 29 日 · 周二`）
  ///
  /// 原先这里是固定副标题「OAS 工作模式」—— 一句永远不变的功能说明，
  /// 第二次开机就不会再有人读它，却占着字标正下方最贵的位置。
  /// 换成日期后这一栏每天来都不一样。
  final String dateText;

  /// 字标下方的第二行：每日语录。
  ///
  /// 与 [dateText] 同属「日期 + 语录」这一组。分两个字段而不是拼一个字符串，
  /// 是因为两者字号、字重、颜色都不同（日期是弱化的事实，语录是稍亮的一句话）。
  final String mottoText;

  /// 系统「减少动态效果」时为 true，所有动画走静态终态
  final bool reduceMotion;

  /// 文本缩放，跟随系统辅助设置
  final TextScaler textScaler;

  /// 立绘：闭眼实体 / 睁眼实体 / 闭眼线稿 / 睁眼线稿
  final ui.Image? artClosed;
  final ui.Image? artOpen;
  final ui.Image? artClosedWire;
  final ui.Image? artOpenWire;
  final ui.Image? artCornerRepair;

  /// 部署面板数据。非空时左侧画部署面板，为空时画品牌字标。
  final SplashPanelData? panelData;

  /// 进度起点偏移。
  ///
  /// 品牌模式从 0 开始（深空 → 线稿 → 实体 → 睁眼）。
  /// 部署模式传一个正值，让画面**跳过已经演过的开场**——
  /// 因为切换模式时 [SplashScreen] 会因 key 变化而重建，
  /// 若不偏移就会从深空重播一遍，视觉上是明显的「倒退」。
  /// 取 0.24 落在「扫描实体化」起点，正好接住品牌期已展示的立绘。
  final double progressBias;

  /// 当前是否允许用户跳过（决定底部是否画跳过提示）。
  ///
  /// 部署进行中为 `false` —— 此刻点掉会让人误以为已经装好。
  /// 提示语本身也要区分：可跳时写「点击跳过」，不可跳时写「部署中」
  /// 并去掉呼吸（没有可执行的动作就不该做动作暗示）。
  final bool skippable;

  /// 品牌模式下的固定时长（部署模式不用）
  ///
  /// 9.0s 的分配（按比例）：线稿 0.04–0.26 ≈ 2.0s，
  /// 实体化 0.24–0.58 ≈ 3.1s，睁眼 0.54–0.94 = 3.6s ——
  /// 睁眼是整段的主角，必须慢且有余韵。
  static const Duration totalDuration = Duration(milliseconds: 9000);

  /// 实际用于取样的进度 = 外部进度按 [progressBias] 拉伸到剩余区间。
  ///
  /// 之所以用「拉伸」而不是「平移」，是为了让部署模式的进度条走到
  /// 100% 时画面也正好收尾 —— 若只做 `p + bias`，外部进度到 1 时
  /// 画面早已越界停在终态，后半段就成了静止画面。
  double get _p {
    if (reduceMotion) {
      return 1.0;
    }
    final raw = progress.clamp(0.0, 1.0);
    if (progressBias <= 0) {
      return raw;
    }
    final span = 1.0 - progressBias;
    return (progressBias + raw * span).clamp(0.0, 1.0);
  }

  /// 把整体进度映射到某个区段的局部进度 0–1
  double _seg(double begin, double end) {
    if (end <= begin) {
      return 1;
    }
    return ((_p - begin) / (end - begin)).clamp(0.0, 1.0);
  }

  static double _easeOut(double t) => 1 - math.pow(1 - t, 3).toDouble();

  static double _easeInOut(double t) =>
      t < 0.5 ? 4 * t * t * t : 1 - math.pow(-2 * t + 2, 3) / 2;

  // ---------------------------------------------------------------- 立绘绘制

  /// 立绘放大倍率（在 cover 贴合基础上的额外微调）。
  ///
  /// 资源本身已是「头肩特写」构图（少女占图内 x∈[0.42,1.0]、y 满高）。
  /// 早期用 1.16 会把它放大到 1392×928 塞进 1200×800，导致头部与右侧
  /// 大面积被裁（实测 top=-64、left=-144）—— 观感像「画面没对准」。
  /// 改为 1.0：立绘正好铺满高度，不额外放大。
  static const double _artScale = 1.0;

  /// 资源逻辑尺寸（三张立绘都是 1200×800）。
  ///
  /// 只用到宽高比，具体像素值无关 —— 取真实分辨率是为了让这里的
  /// cover 计算和 `_pastePlus` 里的 `img.width/height` 有个共同出处。
  static const double _artW = 1200;
  static const double _artH = 800;

  /// 计算立绘贴合矩形 —— **cover 策略 + 右对齐**。
  ///
  /// ## 为什么不是「按高度贴合」
  ///
  /// 旧实现是 `h = H; w = h * 1.5; left = W - w`，即永远按画布**高度**
  /// 铺满、右缘贴边。它在 3:2（1200×800）下正好贴合，但宽高比一旦偏离
  /// 就会坏掉，且两个方向坏得不一样（已用离屏渲染实测）：
  ///
  /// | 画布 | 旧实现 | 问题 |
  /// |---|---|---|
  /// | 2560×800 | left=1360, w=1200 | 右缘留 **1360px 空白竖带**，中间一大块死区 |
  /// | 3440×900 | left=2090, w=1350 | 右缘留 **2090px 空白**，画面塌成「左边空、右边挤一条」 |
  /// | 800×1200 | left=-1000, w=1800 | 立绘被放大到 1800×1200，头部与蝴蝶结被裁掉 |
  ///
  /// 根因是：**两个轴独立定尺寸**（高按 H、宽按比例推），于是宽高比偏离时
  /// 必然在一个方向留下空隙、在另一个方向溢出。
  ///
  /// ## cover 的做法
  ///
  /// 让贴图**同时覆盖两个轴**，取两个方向所需缩放里的较大值：
  ///
  /// ```
  /// scale = max(W / artW, H / artH)          // 覆盖画布所需的最小放大倍率
  /// w = artW * scale,  h = artH * scale      // 等比，绝不拉伸
  /// ```
  ///
  /// 这样立绘永远「不裁不少地铺满画布」，超出的部分从**左侧**溢出
  /// （立绘内容偏右，左半是留白，溢出去无所谓）。
  ///
  /// 右对齐仍然保留：`left = W - w`。在超宽画布下 cover 会让 w 远大于 W，
  /// 于是 left 变成大负数 —— 立绘右缘贴边、右侧内容（少女本体）留在画内，
  /// 左侧大片透明区溢出画外。这正是想要的。
  ///
  /// 竖直方向同样 cover，所以竖屏下 `h` 会大于 `H`，顶部略被裁 ——
  /// 但 cover 保证的是「铺满」而非「不裁」，竖屏下裁掉一点天灵盖
  /// 远好过留一条空带或把人挤成细条。
  Rect _artRect(Size size) {
    if (size.isEmpty) {
      return Rect.zero;
    }
    final scale = math.max(size.width / _artW, size.height / _artH) * _artScale;
    final w = _artW * scale;
    final h = _artH * scale;
    final top = (size.height - h) / 2;
    // 右缘贴齐画布右缘：立绘内容靠右，左侧溢出的是留白
    final left = size.width - w;
    return Rect.fromLTWH(left, top, w, h);
  }

  /// 用「加亮」混合贴一张立绘 —— 黑底自动隐形，只留发光部分。
  void _pastePlus(Canvas canvas, ui.Image? img, Rect dst, double opacity) {
    if (img == null || opacity <= 0.001) {
      return;
    }
    final paint = Paint()
      ..color = Color.fromRGBO(255, 255, 255, opacity.clamp(0.0, 1.0))
      ..blendMode = BlendMode.plus
      ..filterQuality = FilterQuality.medium;
    canvas.drawImageRect(
      img,
      Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
      dst,
      paint,
    );
  }

  double _eyeSegment(double begin, double end) {
    final p = reduceMotion ? 1.0 : (eyeProgress ?? _p).clamp(0.0, 1.0);
    return ((p - begin) / (end - begin)).clamp(0.0, 1.0);
  }

  @visibleForTesting
  double get eyeOpening => _easeInOut(_eyeSegment(0.54, 0.94));

  void _pasteOpening(
    Canvas canvas,
    ui.Image? closed,
    ui.Image? open,
    Rect destination,
    double opacity,
    double opening,
  ) {
    if (closed == null || open == null || opening >= 1) {
      _pastePlus(canvas, open ?? closed, destination, opacity);
      return;
    }
    if (opacity <= 0.001) return;
    canvas.saveLayer(
      destination,
      Paint()
        ..blendMode = BlendMode.plus
        ..color = Color.fromRGBO(255, 255, 255, opacity.clamp(0.0, 1.0)),
    );
    canvas.translate(destination.left, destination.top);
    canvas.scale(destination.width / 1200, destination.height / 800);
    const full = Rect.fromLTWH(0, 0, 1200, 800);
    void draw(ui.Image image, [double alpha = 1]) => canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      full,
      Paint()
        ..filterQuality = FilterQuality.medium
        ..color = Color.fromRGBO(255, 255, 255, alpha),
    );
    draw(closed);
    draw(open, opening.clamp(0.0, 1.0));
    if (eyeMotion != null) {
      eyeMotion!.paint(canvas, opening);
      canvas.restore();
      return;
    }
    final hasFrames =
        artEyeFrames.length == 3 && artEyeFrames.every((f) => f != null);
    final frames = <ui.Image>[
      closed,
      if (hasFrames) ...artEyeFrames.cast<ui.Image>(),
      open,
    ];
    final position = opening.clamp(0.0, 1.0) * (frames.length - 1);
    final index = position.floor().clamp(0, frames.length - 2);
    final mix = position - index;
    canvas.save();
    canvas.clipRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(674, 245, 104, 98),
        const Radius.circular(12),
      ),
    );
    // Blend adjacent illustrated eyelids, including their attached eyelashes.
    // The original iris is never revealed through an artificial aperture.
    draw(frames[index]);
    draw(frames[index + 1], mix);
    canvas.restore();
    canvas.restore();
  }

  void _paintArt(Canvas canvas, Size size) {
    final r = _artRect(size);

    // 瞳孔在立绘内归一化坐标（实测自资源，供眼睑/光带定位）
    const eyeU = 0.58;
    const eyeV = 0.33;
    final eye = Offset(r.left + r.width * eyeU, r.top + r.height * eyeV);

    // ---- 睁眼时序（三段，慢速）----
    // liftT  : 眼皮抬起的动作（0.60→0.86 压缩到 0.54→0.94，共 3.6s）——
    //          这是整段动画的主角，用 easeInOut 让「起—中—收」都平滑，
    //          没有突变拐点，人眼才能读出「眼皮慢慢抬起」而不是「闪一下」。
    // shineT : 瞳孔渐亮 + 收缩（比 liftT 晚一拍开始，形成「先睁、后亮」的层次）
    // scanT  : 眼区扫描光带（横跨中段，扫过即「激活」）
    final liftT = eyeOpening;
    final shineT = _easeOut(_eyeSegment(0.76, 0.98));
    final scanT = _eyeSegment(0.60, 0.94);

    // ---- 1. 线稿层：勾勒完成得快，睁眼时再切一张 ----
    final wireIn = _easeOut(_seg(0.04, 0.26));
    final solidIn = _easeInOut(_seg(0.24, 0.58));
    _pastePlus(canvas, artClosedWire, r, wireIn * 0.95 * (1 - solidIn));

    // ---- 2. 实体层：扫描线以上为实体 ----
    final solidOpacity = solidIn * 0.92;
    if (solidOpacity > 0.001) {
      final front = _easeOut(solidIn) * (size.height * 1.15);
      // 实体图的深空底也参与加亮。硬裁剪会在扫描线下方形成整幅画面
      // 的黑色矩形接缝；在独立图层内用渐隐带过渡，再叠回背景。
      canvas.saveLayer(Offset.zero & size, Paint()..blendMode = BlendMode.plus);
      _pasteOpening(canvas, artClosed, artOpen, r, solidOpacity, liftT);
      final repair = artCornerRepair;
      if (repair != null) {
        // 原始实体帧右下角的模糊矩形只在这一角修复。两道柔边让
        // 修复图融入原帧，眼睛和其余立绘仍沿用原来的眨眼动画。
        canvas.saveLayer(Offset.zero & size, Paint());
        canvas.drawImageRect(
          repair,
          Rect.fromLTWH(
            0,
            0,
            repair.width.toDouble(),
            repair.height.toDouble(),
          ),
          r,
          Paint()
            ..filterQuality = FilterQuality.medium
            ..color = Color.fromRGBO(255, 255, 255, solidIn),
        );
        for (final (start, end, horizontal) in <(double, double, bool)>[
          (0.70, 0.90, true),
          (0.72, 0.91, false),
        ]) {
          final a = horizontal
              ? Offset(r.left + r.width * start, 0)
              : Offset(0, r.top + r.height * start);
          final b = horizontal
              ? Offset(r.left + r.width * end, 0)
              : Offset(0, r.top + r.height * end);
          canvas.drawRect(
            Offset.zero & size,
            Paint()
              ..blendMode = BlendMode.dstIn
              ..shader = ui.Gradient.linear(a, b, const <Color>[
                Color(0x00FFFFFF),
                Color(0xFFFFFFFF),
              ]),
          );
        }
        canvas.restore();
      }
      final feather = size.height * 0.20;
      canvas.drawRect(
        Offset.zero & size,
        Paint()
          ..blendMode = BlendMode.dstIn
          ..shader = ui.Gradient.linear(
            Offset(0, front - feather),
            Offset(0, front),
            const <Color>[Color(0xFFFFFFFF), Color(0x00FFFFFF)],
          ),
      );
      canvas.restore();
    }

    // ---- 3. 眼区扫描光带：自上而下扫过眼位，扫过即「激活」----
    //
    // 注：曾在此处画两道「眼睑开合弧线」充当眼皮抬起的动作签，
    // 已移除。原因是那两道弧线是**贴上去的叠加层**——位置靠固定的
    // 归一化坐标估算（眼距 0.185 / 开合量 0.028），而立绘里的眼睛
    // 处于斜向透视且被发丝半遮，弧线既对不上真实眼位，观感也像两个
    // 悬空的胶囊。真正在传递「睁眼」的是下面三样，它们与立绘的发光
    // 质感同源，不需要额外描线：眼区扫描光带 → 虹膜渐亮 + 高光点 →
    // 冲击波扩散。
    if (scanT > 0 && scanT < 1) {
      final eyeBandH = r.height * 0.14;
      final bandY = eye.dy - eyeBandH * 0.65 + eyeBandH * 1.3 * scanT;
      canvas.save();
      canvas.clipRect(
        Rect.fromCenter(
          center: Offset(r.left + r.width * 0.58, eye.dy),
          width: r.width * 0.46,
          height: r.height * 0.16,
        ),
      );
      final shader = ui.Gradient.linear(
        Offset(0, bandY - eyeBandH / 2),
        Offset(0, bandY + eyeBandH / 2),
        <Color>[
          palette.scan.withValues(alpha: 0),
          palette.scan.withValues(alpha: 0.30),
          palette.scan.withValues(alpha: 0),
        ],
        <double>[0.0, 0.5, 1.0],
      );
      canvas.drawRect(
        Rect.fromLTWH(r.left, bandY - eyeBandH / 2, r.width, eyeBandH),
        Paint()..shader = shader,
      );
      canvas.restore();
    }

    // ---- 4. 虹膜渐亮 + 收缩 + 高光点 ----
    if (shineT > 0) {
      final a = math.sin(shineT * math.pi * 0.85) * 0.75; // 不归零，留余晖
      final glowR = size.height * (0.055 - 0.028 * shineT); // 收缩
      final shader = ui.Gradient.radial(
        eye,
        glowR,
        <Color>[
          palette.iris.withValues(alpha: a),
          palette.iris.withValues(alpha: a * 0.35),
          palette.iris.withValues(alpha: 0),
        ],
        <double>[0.0, 0.45, 1.0],
      );
      canvas.drawCircle(eye, glowR, Paint()..shader = shader);
      // 锐利高光点 —— 让瞳孔「有神」
      if (shineT > 0.5) {
        final hp = (shineT - 0.5) / 0.5;
        canvas.drawCircle(
          eye.translate(-glowR * 0.28, -glowR * 0.30),
          glowR * 0.20 * hp,
          Paint()..color = Colors.white.withValues(alpha: 0.85 * hp),
        );
      }
    }

    // ---- 5. 睁眼冲击波：一次性圆环扩散 ----
    final burst = _eyeSegment(0.94, 1.0);
    if (burst > 0 && burst < 1) {
      final a = math.sin(burst * math.pi) * 0.45;
      final ringR = size.height * (0.04 + 0.16 * burst);
      canvas.drawCircle(
        eye,
        ringR,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1.0, size.height * 0.0028 * (1 - burst))
          ..color = palette.iris.withValues(alpha: a),
      );
    }
  }

  // ---------------------------------------------------------------- 主流程

  @override
  void paint(Canvas canvas, Size size) {
    final g = WireGeometry(size);

    // ---- 背景与星尘 ----
    final bgIn = _easeOut(_seg(0.0, 0.14));
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = palette.backdropBottom,
    );
    if (bgIn > 0) {
      canvas.saveLayer(
        Offset.zero & size,
        Paint()..color = Color.fromRGBO(255, 255, 255, bgIn),
      );
      _paintRadialBackdrop(canvas, size);
      canvas.restore();
    }

    paintStars(
      canvas,
      size,
      stars,
      reduceMotion ? 0.6 : starTime,
      palette.star,
      _easeOut(_seg(0.0, 0.18)),
    );

    // ---- 少女立绘（核心）----
    if (artClosed != null &&
        artOpen != null &&
        artClosedWire != null &&
        artOpenWire != null) {
      _paintArt(canvas, size);
    } else {
      _paintWires(canvas, g);
    }

    // ---- 扫描光带 ----
    _paintScan(canvas, size);

    // ---- 左侧：品牌字标 + 部署面板（可并存）----
    //
    // 布局关系（1200×800 基准，立绘内容实际从 x≈740 起）：
    //
    // ```
    //   x=0 ────────────────────────────740 ────────── 1200
    //   ┌──────────────────────┐         ┌───────────────┐
    //   │ OASX                 │         │               │
    //   │ ────                 │         │   少女立绘     │
    //   │ 2026 年 9 月 29 日    │         │  (头肩特写)    │
    //   │ 把该做的事做完…       │         │               │
    //   │                      │         │               │
    //   │ ◉ 检查运行环境        │         │               │
    //   │ ◐ 拉取 OAS 仓库  63% │         │               │
    //   │ ○ 安装运行依赖        │         │               │
    //   │ ▓▓▓▓▓▓░░░░  63%      │         │               │
    //   └──────────────────────┘         └───────────────┘
    // ```
    //
    // 品牌字标**永远是这一栏的头部**，部署面板接在它下面 ——
    // 两者构成一条单列信息柱，而不是争抢同一块地盘。
    //
    // 历史：早前这里是 `if (panel != null) 面板 else 标题` 的二选一。
    // 那样虽然不会重叠，但部署时品牌标识整个消失，用户看到的界面
    // 在启动瞬间「换了一张脸」；而且面板自己的顶部又重画了一遍
    // OASX 字标，等于同一信息出现两次、还只在其中一种模式下出现。
    final panelIn = _easeOut(_seg(0.56, 0.90));
    final panel = panelData;
    if (panel != null) {
      // 部署模式：字标（快速点亮）在上，进度面板（逐个入场）在下。
      // 二者共用同一条左栏基线，由各自的 `t` 控制节奏。
      final brandIn = _easeOut(_seg(0.10, 0.34));
      if (brandIn > 0) {
        _paintBrandTitle(canvas, size, brandIn, compact: true);
      }
      if (panelIn > 0) {
        paintSplashPanel(
          canvas,
          size,
          panel,
          palette,
          panelIn,
          starTime,
          textScaler: textScaler,
        );
      }
    } else if (panelIn > 0) {
      // 品牌模式：字标单独占位，用完整尺寸（无进度面板挤压）
      _paintBrandTitle(canvas, size, panelIn);
    }

    // ---- HUD 四角（弱化，仅装饰）----
    final hudIn = _easeOut(_seg(0.68, 0.92));
    if (hudIn > 0) {
      paintHudCorners(canvas, size, palette.accent, hudIn * 0.8);
    }

    // ---- 收束高光 ----
    final flash = _seg(0.96, 1.0);
    if (flash > 0 && flash < 1) {
      final a = math.sin(flash * math.pi) * 0.12;
      canvas.drawRect(
        Offset.zero & size,
        Paint()..color = palette.wireGlow.withValues(alpha: a),
      );
    }

    // ---- 跳过提示（底部居中，呼吸）----
    //
    // 入场定在 0.30–0.55：开场那几百毫秒画面正在从深空里「长出来」，
    // 这时贴一行字会跟星尘、线稿抢注意力，也让画面显得急。
    // 等主体立住再浮出来，读起来是「顺便告诉你一声」。
    final hintIn = _easeOut(_seg(0.30, 0.55));
    if (hintIn > 0) {
      paintSkipHint(
        canvas,
        size,
        palette.textDim,
        starTime,
        hintIn,
        skippable: skippable,
        reduceMotion: reduceMotion,
        textScaler: textScaler,
      );
    }

    // ---- 暗角 ----
    paintVignette(canvas, size, palette.vignette);
  }

  void _paintRadialBackdrop(Canvas canvas, Size size) {
    final paint = Paint()
      ..shader = ui.Gradient.radial(
        Offset(size.width * 0.5, size.height * 0.42),
        math.max(size.width, size.height) * 0.78,
        <Color>[palette.backdropTop, palette.backdropBottom],
        <double>[0.0, 1.0],
      );
    canvas.drawRect(Offset.zero & size, paint);
  }

  /// 资源未就绪时的兜底几何线框
  void _paintWires(Canvas canvas, WireGeometry g) {
    final wireIn = _easeOut(_seg(0.10, 0.42));
    if (wireIn <= 0) {
      return;
    }
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = palette.wire.withValues(alpha: wireIn * 0.9);
    for (final radius in WireGeometry.ringRadii) {
      canvas.drawCircle(g.center, g.r(radius), base);
    }
    final glow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..color = palette.wireGlow.withValues(alpha: wireIn * 0.85);
    for (final seg in WireGeometry.ticks(g)) {
      canvas.drawLine(seg.$1, seg.$2, glow);
    }
  }

  void _paintScan(Canvas canvas, Size size) {
    final t = _seg(0.24, 0.72);
    if (t <= 0 || t >= 1) {
      return;
    }
    final bandH = size.height * 0.16;
    final y = size.height * (-0.15 + t * 1.25);
    final rect = Rect.fromLTWH(0, y - bandH / 2, size.width, bandH);
    final shader = ui.Gradient.linear(
      Offset(0, rect.top),
      Offset(0, rect.bottom),
      <Color>[
        palette.scan.withValues(alpha: 0),
        palette.scan.withValues(alpha: 0.16),
        palette.scan.withValues(alpha: 0),
      ],
      <double>[0.0, 0.5, 1.0],
    );
    canvas.drawRect(rect, Paint()..shader = shader);

    canvas.drawLine(
      Offset(size.width * 0.24, y),
      Offset(size.width * 0.76, y),
      Paint()
        ..color = palette.scan.withValues(alpha: 0.45)
        ..strokeWidth = 1.0,
    );
  }

  /// 品牌字标 + 副标题。
  ///
  /// [compact] 控制两种排布：
  ///
  /// - `false`（品牌模式）：字标居中于左栏，字号大（最多 62px），
  ///   是整个画面的第二视觉锚点 —— 此刻右边立绘还在线稿阶段，
  ///   左边需要有足够分量撑住画面。
  /// - `true`（部署模式）：字标缩到左栏**顶部**，字号小（约 0.6×），
  ///   给下面的阶段列表让出纵向空间。此时画面的主角是进度，
  ///   字标退居为「这是谁」的一行标识。
  ///
  /// 两种模式共用同一段绘制逻辑与同一条左基线（`left = width * 0.075`），
  /// 保证切换模式时字标不会横向跳动。
  void _paintBrandTitle(
    Canvas canvas,
    Size size,
    double t, {
    bool compact = false,
  }) {
    TextPainter tp(
      String s,
      Color c,
      double sz,
      FontWeight w, {
      double ls = 0,
    }) {
      return TextPainter(
        text: TextSpan(
          text: s,
          style: TextStyle(
            color: c,
            fontSize: sz,
            fontWeight: w,
            letterSpacing: ls,
            height: 1.0,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        textScaler: textScaler,
      )..layout();
    }

    final shown = titleText.isEmpty ? 'OASX' : titleText;

    // 字号与位置按模式分档。
    //
    // compact 下用 0.030 而不是 0.062：一是要给阶段列表腾出
    // 约 250px 纵向空间，二是大字号在顶部会和「部署面板」的
    // 大量小字形成难看的体量差（一个大字压着一堆小字）。
    final baseSize = compact
        ? math.min(size.width * 0.030, 34.0)
        : math.min(size.width * 0.062, 62.0);
    final mainTp = tp(
      shown,
      palette.text,
      baseSize,
      FontWeight.w700,
      ls: baseSize * 0.14,
    );

    // 左基线：与 paintSplashPanel 的 `left` 严格一致（都是 0.075），
    // 否则字标会相对面板左移或右移。
    final left = size.width * 0.075;
    final top = compact ? size.height * 0.135 : size.height * 0.50;
    final origin = Offset(left, top - mainTp.height / 2);

    if (t > 0.55) {
      final glowTp = tp(
        shown,
        palette.wireGlow,
        baseSize,
        FontWeight.w700,
        ls: baseSize * 0.14,
      );
      canvas.save();
      canvas.translate(origin.dx, origin.dy);
      canvas.saveLayer(
        Rect.fromLTWH(-20, -20, glowTp.width + 40, glowTp.height + 40),
        Paint()..color = Color.fromRGBO(255, 255, 255, (t - 0.55) / 0.45 * 0.5),
      );
      glowTp.paint(canvas, Offset.zero);
      canvas.restore();
      canvas.restore();
    }

    canvas.save();
    canvas.translate(origin.dx, origin.dy);
    mainTp.paint(canvas, Offset.zero);
    canvas.restore();

    if (t > 0.7) {
      final a = (t - 0.7) / 0.3;
      canvas.drawRect(
        Rect.fromLTWH(
          origin.dx + mainTp.width + 3,
          origin.dy + mainTp.height * 0.5 - 1,
          mainTp.height - 4,
          2,
        ),
        Paint()..color = palette.accent.withValues(alpha: a),
      );
    }

    // ---- 日期 + 每日语录 ----
    //
    // 取代原固定副标题「OAS 工作模式」。这一组两行，竖排：
    //
    //   OASX —
    //   2026 年 9 月 29 日 · 周二     ← 弱：事实，字号更小、颜色更暗
    //   把该做的事做完，剩下的交给时间  ← 稍亮：一句话，是这一组的重点
    //
    // 层级靠**字号 + 颜色**双维度拉开，不靠加粗 —— 语录只是「一行安静的话」，
    // 加粗会和上方的 OASX 字标抢分量（字标是 w700，语录再粗就乱了）。
    //
    // 出现时机：品牌模式下等字标完全落定（t≥1）才出现；
    // compact（部署模式）提前到 0.75 —— 左栏顶部空间紧，让它紧跟着字标
    // 一起就位，视觉上是「一组」，而不是一个迟到的小尾巴。
    final subAt = compact ? 0.75 : 1.0;
    if (t < subAt) {
      return;
    }

    final dateSize = clampMottoFontSize(baseSize * 0.24);
    final mottoSize = clampMottoFontSize(baseSize * 0.27);

    // 左栏可用宽度 = 字标宽与面板宽取大者，再留一点右缩进。
    // 语录最长 17 个汉字，在基准字号下约 0.27*62*17 ≈ 285px，
    // 1200px 宽的画布左栏足够；缩窗口时才需要下面这层保护。
    final availW = math.max(mainTp.width, size.width * 0.36) - 4;

    var y = origin.dy + mainTp.height + 11;

    if (dateText.isNotEmpty) {
      final dateTp = _fitTextPainter(
        dateText,
        palette.textFaint,
        dateSize,
        FontWeight.w400,
        ls: dateSize * 0.06,
        maxWidth: availW,
      );
      dateTp.paint(canvas, Offset(left + 2, y));
      y += dateTp.height + 7;
    }

    if (mottoText.isNotEmpty) {
      final mottoTp = _fitTextPainter(
        mottoText,
        palette.textDim,
        mottoSize,
        FontWeight.w400,
        ls: mottoSize * 0.02,
        maxWidth: availW,
      );
      mottoTp.paint(canvas, Offset(left + 2, y));
    }
  }

  /// 按可用宽度生成一个 TextPainter；放不下时**先缩字号到下限，
  /// 再退化为省略号截断**。
  ///
  /// 顺序不能反：先截断的话，窗口只是稍窄一点就丢字，而用户其实
  /// 宁愿字小一点也要看全。只有缩到 11px 仍放不下（极窄窗口）才截。
  /// 截断一律交给 `ellipsis` —— 手切字符会把中文和英文单词切坏。
  TextPainter _fitTextPainter(
    String s,
    Color c,
    double size,
    FontWeight w, {
    double ls = 0,
    required double maxWidth,
  }) {
    TextPainter build(double sz, {bool ellipsis = false}) {
      return TextPainter(
        text: TextSpan(
          text: s,
          style: TextStyle(
            color: c,
            fontSize: sz,
            fontWeight: w,
            letterSpacing: ls * (sz / size),
            height: 1.25,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: ellipsis ? '…' : null,
        textScaler: textScaler,
      )..layout(maxWidth: ellipsis ? maxWidth : double.infinity);
    }

    final full = build(size);
    if (full.width <= maxWidth) {
      return full;
    }
    // 按宽度比例估算所需字号，夹到下限后重排一次
    final shrunk = clampMottoFontSize(size * (maxWidth / full.width));
    final fitted = build(shrunk);
    if (fitted.width <= maxWidth) {
      return fitted;
    }
    return build(shrunk, ellipsis: true);
  }

  @override
  bool shouldRepaint(covariant SplashPainter old) {
    return old.progress != progress ||
        old.eyeProgress != eyeProgress ||
        old.artEyeFrames != artEyeFrames ||
        old.eyeMotion != eyeMotion ||
        old.progressBias != progressBias ||
        old.starTime != starTime ||
        old.titleText != titleText ||
        old.dateText != dateText ||
        old.mottoText != mottoText ||
        old.palette != palette ||
        old.reduceMotion != reduceMotion ||
        old.skippable != skippable ||
        old.artClosed != artClosed ||
        old.artOpen != artOpen ||
        old.artClosedWire != artClosedWire ||
        old.artOpenWire != artOpenWire ||
        old.artCornerRepair != artCornerRepair ||
        old.panelData != panelData;
  }
}
