/// 启动动画左侧的「加载状态面板」
///
/// 参考视频里左侧是品牌字标区，OASX 这里把它升级成**部署进度面板** ——
/// 少女立绘占据右侧，左侧留白正好承载：
///
/// ```
///   OASX                        ← 品牌字标（由 splash_painter 绘制）
///   ────
///   2026 年 9 月 29 日 · 周二     ← 日期（同上，非本面板）
///   把该做的事做完，剩下的交给时间  ← 每日语录（同上）
///
///   ◉ 检查运行环境               ← 阶段列表（状态齐全）
///   ◉ 拉取 OAS 仓库
///   ◐ 安装运行依赖      [ 63% ]   ← 进行中：脉冲 + 自身进度
///   ○ 启动 OAS 服务               ← 待处理：暗描边
///   ○ 建立连接
///
///   ▓▓▓▓▓▓▓▓▓░░░░░░░░ 63%       ← 总进度条
///
///   Cloning into 'OAS'...        ← 实时细节（弱化截断）
/// ```
///
/// 设计要点：
/// - 阶段状态用**形状 + 颜色**双重编码（不只是颜色），色盲可用
/// - 进行中的阶段有**脉冲呼吸**，让「正在装」这件事有生命感
/// - 失败用**实心红点 + 断线**，一眼可辨
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:oasx/modules/boot/splash_palette.dart';
import 'package:oasx/modules/boot/splash_task.dart';

/// 面板绘制所需的输入
class SplashPanelData {
  const SplashPanelData({
    required this.stages,
    required this.overallProgress,
    required this.failed,
    required this.statusLine,
  });

  final List<SplashStage> stages;
  final double overallProgress;
  final bool failed;

  /// 底部滚动细节行（取当前进行中阶段的 detail）
  final String statusLine;

  // 历史：这里曾有 `titleText` / `subtitleText`，用于面板自绘的品牌区。
  // 改造后品牌字标（含日期 + 语录）统一由 `splash_painter` 绘制、面板接在
  // 其下方 —— 面板再画一遍就会出现两个 OASX。两个字段随之失去用途，
  // 保留只会让调用方以为改了文本面板会跟着变。

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    if (other is! SplashPanelData) {
      return false;
    }
    if (other.overallProgress != overallProgress ||
        other.failed != failed ||
        other.statusLine != statusLine ||
        other.stages.length != stages.length) {
      return false;
    }
    for (var i = 0; i < stages.length; i++) {
      if (other.stages[i] != stages[i]) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
        overallProgress,
        failed,
        statusLine,
        Object.hashAll(stages),
      );
}

/// 绘制左侧面板
///
/// [t] 是面板自身的入场进度 0–1，用于逐个淡入阶段，避免一次性糊上去。
void paintSplashPanel(
  Canvas canvas,
  Size size,
  SplashPanelData data,
  SplashPalette palette,
  double t,
  double time, {
  TextScaler textScaler = TextScaler.noScaling,
}) {
  if (t <= 0) {
    return;
  }

  // --- 布局基准 ---
  //
  // 左栏宽度：面板不再吃满 46%，收到 0.36 —— 用户要求「部署页占比小一点」。
  // 收窄后阶段名与百分比之间仍留得下 `maxW`，不会先撞到截断省略号。
  //
  // 纵向：整个面板**下移到左栏下半区**，上半区留给品牌字标
  // （由 splash_painter 的 `_paintBrandTitle(compact:)` 绘制）。
  // 两者上下分居，互不重叠。
  final panelW = size.width * 0.36;
  final left = size.width * 0.075;
  final maxW = panelW * 0.92;

  TextPainter tp(
    String text,
    Color color,
    double fontSize,
    FontWeight weight, {
    double letterSpacing = 0,
    double maxWidth = double.infinity,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: weight,
          letterSpacing: letterSpacing,
          height: 1.15,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
      textScaler: textScaler,
    )..layout(maxWidth: maxWidth);
    return painter;
  }

  // ---------------------------------------------------------- 品牌字标
  //
  // 历史上这个面板是独占左栏的（画布左侧只有它），所以自带一套
  // 品牌区。改造后品牌字标由 splash_painter 统一绘制、面板接在其下方，
  // 若面板再画一遍，屏幕上会出现两个 OASX。
  //
  // 因此面板的内容起点直接由下面的 `listTop` 决定，不再维护
  // 一个中间变量 —— 少一个「看起来该用、其实没人读」的状态。

  // ---------------------------------------------------------- 阶段列表
  //
  // 纵向压缩：rowH 从 0.062h 收到 0.050h、上限 42→34。
  //
  // 起点 0.28h 是「让左栏内容整体居中」算出来的：
  // 字标区占 y∈[0.09, 0.18]h，面板自身高 = 5×0.05 + 0.035 + 0.055 ≈ 0.34h。
  // 若面板从 0.40h 起，内容在 0.18~0.74h 之间堆着，下方 0.74~1.0h
  // 全空 —— 左栏头重脚轻、中段还漏一大块气。
  // 提到 0.28h 后，整柱落在 0.09~0.68h，上下留白接近，重心稳。
  final listTop = size.height * 0.28;
  final rowH = math.min(size.height * 0.050, 34.0);
  final dotR = rowH * 0.105;
  final labelSize = math.min(size.width * 0.0105, 12.0);
  final detailSize = labelSize * 0.86;

  for (var i = 0; i < data.stages.length; i++) {
    final stage = data.stages[i];
    // 逐个淡入：越靠后的条目入场越晚
    final rowT = Curves.easeOut.transform(
      _clamp01((t - 0.35 - i * 0.09) / 0.45),
    );
    if (rowT <= 0) {
      continue;
    }

    final rowY = listTop + i * rowH;
    final cx = left + dotR;
    final cy = rowY + rowH * 0.32;

    _paintStageMarker(
      canvas,
      cx,
      cy,
      dotR,
      stage.state,
      palette,
      rowT,
      time,
    );

    // 阶段名
    final labelColor = switch (stage.state) {
      SplashStageState.done => palette.text,
      SplashStageState.running => palette.wireGlow,
      SplashStageState.failed => const Color(0xFFFF6B6B),
      SplashStageState.pending => palette.textDim.withValues(alpha: 0.55),
    };
    final labelX = cx + dotR * 2.6;
    final labelY = cy - labelSize * 0.62;

    // 已完成的文案加淡蓝底色条，强化「已点亮」
    if (stage.state == SplashStageState.done && rowT > 0.6) {
      final barW = (labelSize * (stage.label.length * 0.62 + 1.6)) *
          (rowT - 0.6) /
          0.4;
      final barShader = ui.Gradient.linear(
        Offset(labelX - dotR, cy),
        Offset(labelX - dotR + barW, cy),
        <Color>[
          palette.accent.withValues(alpha: 0.16),
          palette.accent.withValues(alpha: 0),
        ],
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(labelX - dotR, cy - labelSize * 0.86, barW,
              labelSize * 1.72),
          Radius.circular(labelSize * 0.3),
        ),
        Paint()..shader = barShader,
      );
    }

    final labelTp = tp(
      stage.label,
      labelColor.withValues(alpha: rowT),
      labelSize,
      stage.state == SplashStageState.running
          ? FontWeight.w600
          : FontWeight.w500,
      letterSpacing: 0.3,
      maxWidth: maxW,
    );
    labelTp.paint(canvas, Offset(labelX, labelY));

    // 进行中：右侧显示该阶段自身百分比
    if (stage.state == SplashStageState.running &&
        stage.progress >= 0 &&
        rowT > 0.8) {
      final pct = '${(stage.progress * 100).round()}%';
      final pctTp = tp(
        pct,
        palette.accent.withValues(alpha: (rowT - 0.8) / 0.2),
        detailSize,
        FontWeight.w600,
        letterSpacing: 0.5,
      );
      pctTp.paint(
        canvas,
        Offset(left + panelW - pctTp.width, labelY + labelSize * 0.08),
      );
    }
  }

  // ---------------------------------------------------------- 总进度条
  //
  // 紧跟阶段列表之后：listTop(0.40h) + 5 × rowH(0.05h) = 0.65h，
  // 留一拍间距放到 0.675h。不再用固定 0.735h —— 那样在阶段数少于 5
  // 时会离列表很远、多于一屏时会撞上细节行。
  final barT = Curves.easeOut.transform(_clamp01(t * 1.4 - 0.5));
  if (barT > 0) {
    final barY =
        listTop + data.stages.length * rowH + size.height * 0.035;
    const barH = 2.6;
    final barW = panelW * 0.78 * barT;

    // 轨道
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(left, barY, barW, barH),
        const Radius.circular(2),
      ),
      Paint()..color = palette.textDim.withValues(alpha: 0.22),
    );

    // 已填充部分
    final fill = data.overallProgress.clamp(0.0, 1.0) * barW;
    if (fill > 0.5) {
      final fillColor = data.failed ? const Color(0xFFFF6B6B) : palette.accent;
      final shader = ui.Gradient.linear(
        Offset(left, barY),
        Offset(left + fill, barY),
        <Color>[
          fillColor.withValues(alpha: 0.55),
          fillColor,
        ],
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(left, barY, fill, barH),
          const Radius.circular(2),
        ),
        Paint()..shader = shader,
      );
      // 前沿高光
      if (!data.failed && data.overallProgress < 1) {
        final glow = ui.Gradient.radial(
          Offset(left + fill, barY + barH / 2),
          9,
          <Color>[
            palette.wireGlow.withValues(alpha: 0.8),
            palette.wireGlow.withValues(alpha: 0),
          ],
        );
        canvas.drawCircle(
          Offset(left + fill, barY + barH / 2),
          9,
          Paint()..shader = glow,
        );
      }
    }

    // 百分比文字
    final pctTp = tp(
      '${(data.overallProgress * 100).round()}%',
      data.failed ? const Color(0xFFFF6B6B) : palette.text,
      labelSize * 1.05,
      FontWeight.w600,
      letterSpacing: 0.6,
    );
    pctTp.paint(canvas, Offset(left + barW + 12, barY - pctTp.height / 2));
  }

  // ---------------------------------------------------------- 底部细节行
  final detailT = Curves.easeOut.transform(_clamp01(t * 2 - 1.1));
  if (detailT > 0 && data.statusLine.isNotEmpty) {
    // 同样跟着进度条走，不写死 0.855h
    final barBottom = listTop + data.stages.length * rowH + size.height * 0.035;
    final detailY = barBottom + size.height * 0.055;
    final detailTp = tp(
      data.statusLine,
      palette.textDim.withValues(alpha: 0.72 * detailT),
      detailSize * 0.95,
      FontWeight.w400,
      letterSpacing: 0.2,
      maxWidth: panelW * 0.95,
    );
    detailTp.paint(canvas, Offset(left, detailY));
  }
}

/// 画一个阶段标记：不同状态不同形状
void _paintStageMarker(
  Canvas canvas,
  double cx,
  double cy,
  double r,
  SplashStageState state,
  SplashPalette palette,
  double alpha,
  double time,
) {
  switch (state) {
    case SplashStageState.done:
      // 实心圆 + 外圈光环（已点亮）
      final halo = ui.Gradient.radial(
        Offset(cx, cy),
        r * 3.2,
        <Color>[
          palette.accent.withValues(alpha: 0.35 * alpha),
          palette.accent.withValues(alpha: 0),
        ],
      );
      canvas.drawCircle(
        Offset(cx, cy),
        r * 3.2,
        Paint()..shader = halo,
      );
      canvas.drawCircle(
        Offset(cx, cy),
        r,
        Paint()..color = palette.accent.withValues(alpha: alpha),
      );
      // 中心小白点，像「已亮起的指示灯」
      canvas.drawCircle(
        Offset(cx, cy),
        r * 0.36,
        Paint()..color = palette.text.withValues(alpha: alpha),
      );

    case SplashStageState.running:
      // 脉冲圆环：外环随 time 呼吸
      final pulse = 0.5 + 0.5 * math.sin(time * 3.4);
      canvas.drawCircle(
        Offset(cx, cy),
        r * (1.0 + 0.55 * pulse),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..color = palette.wireGlow.withValues(alpha: (0.55 - 0.3 * pulse) * alpha),
      );
      canvas.drawCircle(
        Offset(cx, cy),
        r * 0.72,
        Paint()..color = palette.wireGlow.withValues(alpha: alpha),
      );

    case SplashStageState.failed:
      // 实心红点 + 打断的圈，和「完成」明显区分
      canvas.drawCircle(
        Offset(cx, cy),
        r,
        Paint()..color = const Color(0xFFFF6B6B).withValues(alpha: alpha),
      );
      canvas.drawLine(
        Offset(cx - r * 1.9, cy),
        Offset(cx - r * 1.1, cy),
        Paint()
          ..strokeWidth = 1.4
          ..color = const Color(0xFFFF6B6B).withValues(alpha: alpha),
      );

    case SplashStageState.pending:
      // 空心细环：等待中，最弱
      canvas.drawCircle(
        Offset(cx, cy),
        r * 0.92,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = palette.textDim.withValues(alpha: 0.45 * alpha),
      );
  }
}

double _clamp01(double v) => v.clamp(0.0, 1.0);
