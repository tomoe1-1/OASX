/// 启动动画的星尘粒子与 HUD 装饰绘制
///
/// 两者都在归一化坐标系里描述，由 [SplashGeometry] 缩放。
/// 粒子用确定性随机（固定种子）生成，保证每次启动星图一致，
/// 避免「每次开机星象都不同」的廉价感。
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// 单颗星尘
@immutable
class Star {
  const Star({
    required this.x,
    required this.y,
    required this.radius,
    required this.phase,
    required this.twinkleSpeed,
    required this.drift,
  });

  final double x;
  final double y;
  final double radius;

  /// 闪烁相位（0–1），错开每颗星的节奏
  final double phase;

  /// 闪烁频率倍数
  final double twinkleSpeed;

  /// 漂移速度（归一化单位/秒），正负决定方向
  final Offset drift;
}

/// 星尘场：生成 + 更新
class StarField {
  StarField({this.count = 130, int seed = 0x4F41})
      : _rng = math.Random(seed);

  /// 粒子数量
  final int count;

  final math.Random _rng;
  List<Star>? _stars;

  /// 惰性生成，避免在构造函数里做随机（便于 const 场景）
  List<Star> get stars => _stars ??= _generate();

  List<Star> _generate() {
    final out = <Star>[];
    for (var i = 0; i < count; i++) {
      // 极坐标撒点，中心稀疏、外缘密集 —— 视觉上更聚焦
      final angle = _rng.nextDouble() * math.pi * 2;
      final dist = math.pow(_rng.nextDouble(), 0.55).toDouble();
      final x = 0.5 + math.cos(angle) * dist * 0.72;
      final y = 0.5 + math.sin(angle) * dist * 0.72;
      out.add(Star(
        x: x,
        y: y,
        radius: 0.6 + _rng.nextDouble() * 1.7,
        phase: _rng.nextDouble(),
        twinkleSpeed: 0.25 + _rng.nextDouble() * 0.85,
        drift: Offset(
          (_rng.nextDouble() - 0.5) * 0.012,
          -0.004 - _rng.nextDouble() * 0.014,
        ),
      ));
    }
    return out;
  }
}

/// 按时间推进星尘并绘制
void paintStars(
  Canvas canvas,
  Size size,
  List<Star> stars,
  double t,
  Color color,
  double intensity,
) {
  final short = math.min(size.width, size.height);
  final cx = size.width / 2;
  final cy = size.height / 2;

  for (final s in stars) {
    // 漂移是循环的：走出 1.0 后回绕，避免长时间运行后星星跑光
    final dx = (s.x + s.drift.dx * t) % 1.0;
    final dy = (s.y + s.drift.dy * t) % 1.0;
    final px = cx + (dx - 0.5) * short;
    final py = cy + (dy - 0.5) * short;
    if (px < -4 || py < -4 || px > size.width + 4 || py > size.height + 4) {
      continue;
    }

    // 闪烁：正弦，相位错开
    final tw = 0.5 + 0.5 * math.sin((t * s.twinkleSpeed + s.phase) * math.pi * 2);
    final alpha = (0.18 + 0.62 * tw) * intensity;
    if (alpha <= 0.01) {
      continue;
    }

    final paint = Paint()
      ..color = color.withValues(alpha: alpha.clamp(0.0, 1.0))
      ..maskFilter = s.radius > 1.6
          ? const MaskFilter.blur(BlurStyle.normal, 1.6)
          : null;
    canvas.drawCircle(Offset(px, py), s.radius, paint);
  }
}

/// ---- HUD 装饰 ----

/// 四角框线：每个角一个 L 形，带一小段内缩的断线（科技感）
void paintHudCorners(Canvas canvas, Size size, Color color, double opacity) {
  final paint = Paint()
    ..color = color.withValues(alpha: 0.55 * opacity)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.2
    ..strokeCap = StrokeCap.round;

  const inset = 22.0;
  const arm = 26.0;
  final w = size.width, h = size.height;

  final paths = <Path>[
    // 左上
    Path()
      ..moveTo(inset, inset + arm)
      ..lineTo(inset, inset)
      ..lineTo(inset + arm, inset),
    // 右上
    Path()
      ..moveTo(w - inset - arm, inset)
      ..lineTo(w - inset, inset)
      ..lineTo(w - inset, inset + arm),
    // 左下
    Path()
      ..moveTo(inset, h - inset - arm)
      ..lineTo(inset, h - inset)
      ..lineTo(inset + arm, h - inset),
    // 右下
    Path()
      ..moveTo(w - inset - arm, h - inset)
      ..lineTo(w - inset, h - inset)
      ..lineTo(w - inset, h - inset - arm),
  ];

  for (final p in paths) {
    canvas.drawPath(p, paint);
  }
}

/// 左侧 ANALYSIS 风格的阶段列表
///
/// 传入已完成的阶段数，未完成的以暗色显示。
void paintStageList(
  Canvas canvas,
  Size size,
  Color color,
  Color dimColor,
  List<String> stages,
  int completed,
  double opacity,
  TextPainter Function(String, Color) makePainter,
) {
  final left = size.width * 0.075;
  final top = size.height * 0.34;
  const lineHeight = 21.0;

  for (var i = 0; i < stages.length; i++) {
    final done = i < completed;
    final y = top + i * lineHeight;

    // 状态标记：已完成是实心方块，未完成是空心
    final marker = Rect.fromLTWH(left, y + 4, 4, 4);
    if (done) {
      canvas.drawRect(
        marker,
        Paint()..color = color.withValues(alpha: opacity),
      );
    } else {
      canvas.drawRect(
        marker,
        Paint()
          ..color = dimColor.withValues(alpha: 0.7 * opacity)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    }

    final tp = makePainter(stages[i], done ? color : dimColor);
    tp.paint(
      canvas,
      Offset(left + 13, y),
    );
  }
}

/// 右侧竖排小字（MORE / INTELLIGENT / CREATIVE 那种）
///
/// 逐字母竖排，靠右对齐。
void paintVerticalTag(
  Canvas canvas,
  Size size,
  Color color,
  String text,
  double opacity,
  TextPainter Function(String, Color) makePainter,
) {
  final right = size.width * 0.925;
  final top = size.height * 0.30;
  const step = 13.0;

  for (var i = 0; i < text.length; i++) {
    final tp = makePainter(text[i], color);
    tp.paint(canvas, Offset(right - tp.width, top + i * step));
  }
}

/// 底部细进度条
void paintProgressBar(
  Canvas canvas,
  Size size,
  Color trackColor,
  Color fillColor,
  double progress,
  double opacity,
) {
  final w = size.width * 0.24;
  final h = 2.0;
  final left = (size.width - w) / 2;
  final top = size.height * 0.845;

  canvas.drawRRect(
    RRect.fromRectAndRadius(Rect.fromLTWH(left, top, w, h), const Radius.circular(1)),
    Paint()..color = trackColor.withValues(alpha: 0.35 * opacity),
  );

  final filled = (w * progress.clamp(0.0, 1.0)).clamp(0.0, w);
  if (filled <= 0) {
    return;
  }
  canvas.drawRRect(
    RRect.fromRectAndRadius(Rect.fromLTWH(left, top, filled, h), const Radius.circular(1)),
    Paint()..color = fillColor.withValues(alpha: opacity),
  );
}

/// 画面外缘的暗角，把注意力收到中心。
///
/// ## 强度与起点（踩过的坑）
///
/// 最初 `0xCC000000`（80% 黑）+ 从半径 0.55 起渐变：暗角在**离中心最远
/// 的右下角**叠加了约 67% 的黑，和「跳过提示」的暗晕、立绘右下自身的
/// 暗部三层叠在一起，形成一块可辨认的死黑 —— 用户看到的是
/// 「右下有个黑块在遮挡立绘」，而不是「画面收拢到中心」。
///
/// 现在配色侧已把 vignette 降到 32% 黑（见 `SplashPalette`），这里把
/// 渐变起点从 0.55 外推到 **0.70**：暗角只作用于最外缘 30% 的环带，
/// 同一角落的总叠加降到约 24% —— 聚焦效果还在（人眼对边缘压暗非常
/// 敏感，20% 就足够），但任何位置都不会再出现「一块黑」。
void paintVignette(Canvas canvas, Size size, Color vignette) {
  final rect = Offset.zero & size;
  final paint = Paint()
    ..shader = ui.Gradient.radial(
      rect.center,
      math.max(size.width, size.height) * 0.62,
      <Color>[const Color(0x00000000), vignette],
      <double>[0.70, 1.0],
    );
  canvas.drawRect(rect, paint);
}

/// 背景：以中心为原点的径向深空渐变
void paintBackdrop(Canvas canvas, Size size, Color top, Color bottom) {
  final rect = Offset.zero & size;
  // 先铺一层纯色底，避免径向渐变未覆盖的角落露白
  canvas.drawRect(rect, Paint()..color = bottom);

  final paint = Paint()
    ..shader = ui.Gradient.radial(
      Offset(size.width * 0.5, size.height * 0.42),
      math.max(size.width, size.height) * 0.78,
      <Color>[top, bottom],
      <double>[0.0, 1.0],
    );
  canvas.drawRect(rect, paint);
}

/// 底部居中的「点击 / 按键跳过」提示。
///
/// ## 为什么需要它
///
/// 启动动画一直支持跳过（点击画面或按任意键），但**画面上从来没写**。
/// 一个只能靠猜才能发现的能力等于不存在 —— 尤其这段动画在部署模式下
/// 会持续到部署结束，用户干等时会本能地去找「能不能跳过」。
///
/// ## 呼吸节奏为什么是 2.4s / 0.5↔1.0
///
/// 静态文字会被当成界面的一部分读过去（用户扫一眼就忘了），
/// 快闪又像报错在报警。2.4s 一个完整来回是「安静地招手」的量级：
/// 足够让余光注意到，又不会在停留十几秒之后变得烦人。
///
/// 这是从参考实现（DSH 开机动画插件的 `dba-breathe`）里拿来的唯一一条 ——
/// 它的其余克制（看门狗、faststart、播放记录）都是远程视频流的工程问题，
/// 与本地自绘启动页无关。
///
/// ## 不可跳过时为什么反过来「不动」
///
/// 部署进行中（[skippable] 为 false）画的是「正在部署，请稍候」，
/// 这句是**状态陈述**而非邀请。给状态陈述加呼吸动画，等于用动作
/// 暗示存在一个可执行的操作，而这里恰恰没有 —— 用户会去点，然后
/// 什么也不发生，比不提示更糟。所以这里把呼吸整个关掉，只留静态文字。
///
/// [time] 是持续递增的秒数（复用星尘时钟），[t] 是入场进度 0–1。
void paintSkipHint(
  Canvas canvas,
  Size size,
  Color color,
  double time,
  double t, {
  bool skippable = true,
  bool reduceMotion = false,
  TextScaler textScaler = TextScaler.noScaling,
}) {
  if (t <= 0) {
    return;
  }

  // 呼吸：0.5 ↔ 1.0，正弦往返。
  // 用 sin 而不是三角波 —— 三角波在折返点有速度突变，眼睛能看出「顿一下」。
  //
  // 不可跳过 / 减少动态效果时取固定 0.8：仍比纯静态的 1.0 略暗，
  // 保持它在视觉层级里处于「提示」而非「内容」的位置。
  final double breath;
  if (!skippable || reduceMotion) {
    breath = 0.8;
  } else {
    breath = 0.75 + 0.25 * math.sin(time * 2 * math.pi / 2.4);
  }
  final alpha = breath * t;

  final tp = TextPainter(
    text: TextSpan(
      text: skippable ? '点击任意处或按任意键跳过' : '正在部署 OAS，请勿关闭窗口',
      style: TextStyle(
        color: color.withValues(alpha: alpha.clamp(0.0, 1.0)),
        fontSize: 12,
        fontWeight: FontWeight.w400,
        letterSpacing: 1.4,
        height: 1.0,
        // 可读性靠**贴字形的阴影**，不靠背后垫大暗晕。
        //
        // 曾在这里画一个半径 0.62×文字宽、55% 黑的径向暗晕给文字垫底。
        // 实测它护不住：立绘的发光线条正好穿过提示行，垫了晕之后
        // 文字对比度仍只有 1.58:1（晕不够黑）；而把晕加黑到护得住，
        // 它又会和暗角、立绘暗部在画面右下叠成一块死黑
        // （用户反馈「右下的黑块遮挡」）—— 两个方向都是死路。
        //
        // 文字阴影只贴着笔画走：笔画处有一圈近黑描边（对比 5:1+），
        // 笔画之外的画面完全不变 —— 可读性与「不产生黑块」同时成立。
        shadows: <Shadow>[
          // 外层柔影：吃掉高光边缘的辉光
          Shadow(color: const Color(0xE604060C), blurRadius: 5),
          // 内层硬影：贴字一圈，保证字形本身与底分离
          Shadow(color: const Color(0xE604060C), blurRadius: 1.2),
        ],
      ),
    ),
    textDirection: TextDirection.ltr,
    textScaler: textScaler,
  )..layout();

  // 底部居中。用 0.92h 而不是贴着边缘 —— 下方还有暗角，
  // 压在暗角里对比度会掉。
  final x = (size.width - tp.width) / 2;
  final y = size.height * 0.92;

  tp.paint(canvas, Offset(x, y));
}
