/// 启动动画配色令牌
///
/// 参考「深色科技 HUD」调性：深空蓝黑底 + 青蓝线框高光。
/// 与全局 [ColorSeed] 联动 —— [SplashPalette.fromSeed] 按当前主题种子色
/// 推导出整体色相，使启动动画在不同主题下保持同一套明度关系，
/// 只换色相，不破坏「深空感」。
///
/// 色值取自参考视频实测（色相集中在 190°–230°）：
/// - 底色 `#05070E` 深空蓝黑
/// - 线框主色 `#328FD3` → 高光 `#6DC3E3`
library;

import 'package:flutter/material.dart';

/// 一套完整的启动动画配色
@immutable
class SplashPalette {
  const SplashPalette({
    required this.backdropTop,
    required this.backdropBottom,
    required this.vignette,
    required this.wire,
    required this.wireGlow,
    required this.wireDim,
    required this.scan,
    required this.star,
    required this.text,
    required this.textDim,
    required this.textFaint,
    required this.accent,
    required this.iris,
  });

  /// 背景径向渐变的中心色
  final Color backdropTop;

  /// 背景径向渐变的外缘色
  final Color backdropBottom;

  /// 四周暗角，压住边缘让中心更聚焦
  final Color vignette;

  /// 线框主色（角色轮廓）
  final Color wire;

  /// 线框高光（已「实体化」的段落）
  final Color wireGlow;

  /// 尚未实体化的暗淡线框
  final Color wireDim;

  /// 扫描光带的颜色
  final Color scan;

  /// 星尘粒子
  final Color star;

  /// 主标题文字
  final Color text;

  /// 副标题 / 小字
  final Color textDim;

  /// 第三档文字：比 [textDim] 再暗一档，用于**事实性**元信息。
  ///
  /// 加这一档是因为「日期 + 语录」这一组内部还需要再分主次：
  /// 日期是背景事实（今天几号），语录是这一组的重点。若两者同色，
  /// 两行会糊成一块，读的时候得逐字辨认才知道哪行是什么。
  ///
  /// 明度取 0.44（textDim 是 0.58）—— 在 `#04060C` 底上对比度约 4.6:1，
  /// 仍过 WCAG AA 的 4.5:1；再暗就会掉到不达标。
  final Color textFaint;

  /// 强调色（进度条、HUD 角标）
  final Color accent;

  /// 虹膜色（少女睁眼时瞳孔的发光色，青绿）
  ///
  /// 与主体青蓝拉开一点的色相，让「睁眼」成为整段动画的唯一高饱和焦点。
  final Color iris;

  /// 按主题种子色推导整套配色。
  ///
  /// 做法：保留参考视频的 HSL 明度/饱和度骨架，
  /// 只把色相换成种子色的色相。这样切到「樱粉」主题时，
  /// 线框会变粉，但仍是「深空 + 霓虹线框」的观感。
  factory SplashPalette.fromSeed(Color seed) {
    final hsl = HSLColor.fromColor(seed);
    final hue = hsl.hue;

    Color h(double h, double s, double l) =>
        HSLColor.fromAHSL(1, (hue + h) % 360, s, l).toColor();

    return SplashPalette(
      backdropTop: h(0, 0.45, 0.07),
      backdropBottom: const Color(0xFF04060C),
      // 暗角只做「轻微收边」，不做压场。
      //
      // 曾用 0xCC（80% 黑）+ 渐变起点 0.55：右下角离径向中心最远，
      // 实测叠加了约 67% 的黑，把立绘右下的身体整个压成一块死黑
      // （用户反馈「右下的黑块遮挡」）。现在 32% 黑 + 起点外推到
      // 0.70，同样的角落只剩约 24% 黑 —— 仍有聚焦作用，但不再
      // 出现可辨认的「黑块」。见 paintVignette 的注释。
      vignette: const Color(0x52000000),
      wire: h(0, 0.72, 0.52),
      wireGlow: h(-6, 0.82, 0.72),
      wireDim: h(0, 0.42, 0.34),
      scan: h(-4, 0.88, 0.66),
      star: h(0, 0.30, 0.86),
      text: h(0, 0.18, 0.96),
      textDim: h(0, 0.28, 0.58),
      textFaint: h(0, 0.24, 0.44),
      accent: h(-6, 0.80, 0.62),
      iris: h(24, 0.82, 0.60),
    );
  }

  /// 参考视频的默认配色（深空青蓝），不依赖主题时使用。
  static const SplashPalette deepSpace = SplashPalette(
    backdropTop: Color(0xFF0A1428),
    backdropBottom: Color(0xFF04060C),
    // 与 fromSeed 的 vignette 保持同一档强度（见那里的注释：
    // 0xCC 曾把右下角压成 67% 黑的死块）。
    vignette: Color(0x52000000),
    wire: Color(0xFF328FD3),
    wireGlow: Color(0xFF6DC3E3),
    wireDim: Color(0xFF1E4A6E),
    scan: Color(0xFF83D3DC),
    star: Color(0xFFD6E4F0),
    text: Color(0xFFF2F6FA),
    textDim: Color(0xFF6E8CA8),
    textFaint: Color(0xFF54708A),
    accent: Color(0xFF4FA8D8),
    iris: Color(0xFF2FE8C8),
  );

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is SplashPalette &&
        other.backdropTop == backdropTop &&
        other.backdropBottom == backdropBottom &&
        other.vignette == vignette &&
        other.wire == wire &&
        other.wireGlow == wireGlow &&
        other.wireDim == wireDim &&
        other.scan == scan &&
        other.star == star &&
        other.text == text &&
        other.textDim == textDim &&
        other.textFaint == textFaint &&
        other.accent == accent &&
        other.iris == iris;
  }

  @override
  int get hashCode => Object.hash(
        backdropTop,
        backdropBottom,
        vignette,
        wire,
        wireGlow,
        wireDim,
        scan,
        star,
        text,
        textDim,
        textFaint,
        accent,
        iris,
      );
}
