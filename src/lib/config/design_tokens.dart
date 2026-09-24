/// 全局设计令牌（Design Tokens）
///
/// 集中管理间距、圆角、阴影、动效时长与字体层级，
/// 避免各处硬编码数值导致观感不一致。
library;

import 'package:flutter/material.dart';

/// 间距刻度：4 的倍数，遵循 8pt 栅格
///
/// 中间档（`xsPlus` / `smMid` / `smPlus` / `lgPlus`）是为了消灭
/// `Spacing.sm + 2` 这类「令牌 + 偏移」写法 —— 偏移算术会让刻度失去意义，
/// 也让后续统一调档时漏改。需要新档位就加进刻度，不要在调用点算。
abstract final class Spacing {
  static const double xxs = 2;
  static const double xs = 4;
  static const double xsPlus = 6;
  static const double sm = 8;
  static const double smMid = 9;
  static const double smPlus = 10;
  static const double md = 12;
  static const double mdPlus = 14;
  static const double lg = 16;
  static const double lgPlus = 18;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 32;

  static const EdgeInsets page = EdgeInsets.all(xl);
  static const EdgeInsets card = EdgeInsets.all(md);
  static const EdgeInsets item = EdgeInsets.symmetric(vertical: xs);
  static const EdgeInsets inlineGap = EdgeInsets.symmetric(horizontal: sm);
}

/// 圆角刻度
abstract final class Radii {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double pill = 999;

  static const BorderRadius cardRadius = BorderRadius.all(Radius.circular(md));
  static const BorderRadius smRadius = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius chipRadius = BorderRadius.all(Radius.circular(pill));
}

/// 动效时长与曲线：统一交互节奏
abstract final class Motion {
  /// 微交互：悬停、按压反馈
  static const Duration fast = Duration(milliseconds: 120);

  /// 紧凑过渡：拖拽高亮、滑块伸缩这类「贴近手指」的即时反馈。
  ///
  /// 比 [fast] 稍慢一点，是为了让状态色的淡入能被眼睛捕捉到；
  /// 但必须明显快于 [normal]，否则拖拽时会感觉「拖泥带水」。
  static const Duration settle = Duration(milliseconds: 180);

  /// 常规过渡：展开、淡入
  static const Duration normal = Duration(milliseconds: 220);

  /// 页面级切换
  static const Duration slow = Duration(milliseconds: 320);

  static const Curve standard = Curves.easeOutCubic;

  /// 强调曲线：用于需要"落定感"的位移
  static const Curve emphasized = Curves.easeInOutCubicEmphasized;

  /// 减速曲线：入场位移专用（与 [standard] 区分开，避免同名不同义）
  static const Curve decelerate = Curves.decelerate;

  /// 滚动定位曲线：滚动到某个位置时用，起手快、收尾缓。
  static const Curve scrollCurve = Curves.easeOut;

  /// 尊重系统「减少动态效果」偏好。
  ///
  /// 开启无障碍选项时返回 [Duration.zero]，让过渡瞬时完成。
  /// 所有动画时长都应经由此方法取值，不要直接写 [fast]/[normal]/[slow]，
  /// 否则会绕过用户的系统设置。
  static Duration of(BuildContext context, Duration duration) {
    return MediaQuery.maybeDisableAnimationsOf(context) ?? false
        ? Duration.zero
        : duration;
  }

  /// 等价于 `of(context, fast)`，用于 `AnimatedXxx(duration:)` 这类
  /// 只能接 [Duration] 的构造参数，避免每次都要写一长串。
  static Duration fastOf(BuildContext context) => of(context, fast);

  /// 等价于 `of(context, settle)`。
  static Duration settleOf(BuildContext context) => of(context, settle);

  /// 等价于 `of(context, normal)`。
  static Duration normalOf(BuildContext context) => of(context, normal);

  /// 等价于 `of(context, slow)`。
  static Duration slowOf(BuildContext context) => of(context, slow);
}

/// 语义色：跨模块统一的一套状态色。
///
/// 此前项目里存在两套并存的色板（状态用 #16A34A 系、图表用 #DC2626 系），
/// 同一个「错误」出现两种红。这里收口为唯一来源。
///
/// 关于硬编码：这些色值刻意不走 [ColorScheme] 的种子派生 ——
/// 语义色必须稳定（停止永远是那个灰、异常永远是那个橙），
/// 不应随用户切换的 9 种主题种子而漂移。
///
/// ## 亮/暗双变体
///
/// 同一组色在亮色底与暗色底上的对比度差异极大。实测原色值：
///
/// | 语义色 | 白底 | 暗色 surfaceContainerHigh |
/// |---|---|---|
/// | warning #F59E0B | **2.15:1** ✗ | 6.64:1 |
/// | success #16A34A | **3.30:1** ✗ | 4.33:1 |
/// | danger #DC2626 | 4.83:1 | **2.95:1** ✗ |
///
/// 也就是说没有任何一组单色能同时满足两种主题的 4.5:1。
/// 因此每个语义色都提供亮/暗两档，由 [of] 按当前 [Brightness] 选择。
/// **新代码一律用 [of]，不要直接引用 [successLight] 等单档常量** ——
/// 直接引用会把界面钉死在一种主题上。
abstract final class SemanticColors {
  // ---- 亮色主题档位（在白底/浅灰卡片上 >= 4.5:1）----

  /// 运行中 / 成功 / 正常（亮色主题）
  static const Color successLight = Color(0xFF15803D);

  /// 异常 / 待处理 / 警告（亮色主题）
  static const Color warningLight = Color(0xFFB45309);

  /// 错误 / 失败 / 危险（亮色主题）
  static const Color dangerLight = Color(0xFFDC2626);

  /// 信息 / 离线 / 链接（亮色主题）
  static const Color infoLight = Color(0xFF1D4ED8);

  /// 中性 / 已停止 / 未启用（亮色主题）
  static const Color neutralLight = Color(0xFF4B5563);

  // ---- 暗色主题档位（在暗色表面上 >= 4.5:1）----

  /// 运行中 / 成功 / 正常（暗色主题）
  static const Color successDark = Color(0xFF4ADE80);

  /// 异常 / 待处理 / 警告（暗色主题）
  static const Color warningDark = Color(0xFFFBBF24);

  /// 错误 / 失败 / 危险（暗色主题）
  static const Color dangerDark = Color(0xFFF87171);

  /// 信息 / 离线 / 链接（暗色主题）
  static const Color infoDark = Color(0xFF60A5FA);

  /// 中性 / 已停止 / 未启用（暗色主题）
  static const Color neutralDark = Color(0xFF9CA3AF);

  // ---- 按主题取色 ----

  /// 运行中 / 成功 / 正常
  static Color success(BuildContext context) =>
      of(context, successLight, successDark);

  /// 异常 / 待处理 / 警告
  static Color warning(BuildContext context) =>
      of(context, warningLight, warningDark);

  /// 错误 / 失败 / 危险
  static Color danger(BuildContext context) =>
      of(context, dangerLight, dangerDark);

  /// 信息 / 离线 / 链接
  static Color info(BuildContext context) =>
      of(context, infoLight, infoDark);

  /// 中性 / 已停止 / 未启用
  static Color neutral(BuildContext context) =>
      of(context, neutralLight, neutralDark);

  /// 按当前主题在亮/暗两档之间选择。
  static Color of(BuildContext context, Color light, Color dark) =>
      Theme.of(context).brightness == Brightness.dark ? dark : light;

  /// 脚本状态 → 语义色
  ///
  /// 接收 bool 条件而非 [HomeScriptStateFilter]，避免 config 层反向依赖
  /// modules 层。调用方传自己的状态判断即可。
  static Color forState(
    BuildContext context, {
    required bool running,
    required bool abnormal,
    required bool offline,
    required Color fallback,
  }) {
    if (running) {
      return success(context);
    }
    if (abnormal) {
      return warning(context);
    }
    if (offline) {
      return info(context);
    }
    return fallback;
  }

  /// 统计图表用的多色板：同一语义家族，饱和度与明度成对分布。
  ///
  /// 只在图表这类需要"区分多个并列项"的场景使用；
  /// 表达状态一律用上面的 success/warning/danger/info。
  static const List<Color> chartPaletteLight = <Color>[
    Color(0xFF2563EB),
    Color(0xFFDC2626),
    Color(0xFF16A34A),
    Color(0xFFD97706),
    Color(0xFF7C3AED),
    Color(0xFF0891B2),
  ];

  /// 图表色板的暗色主题变体（各色在暗色表面 >= 4.5:1）。
  static const List<Color> chartPaletteDark = <Color>[
    Color(0xFF60A5FA),
    Color(0xFFF87171),
    Color(0xFF4ADE80),
    Color(0xFFFBBF24),
    Color(0xFFA78BFA),
    Color(0xFF22D3EE),
  ];

  /// 按主题取图表色板。
  static List<Color> chartPalette(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? chartPaletteDark
          : chartPaletteLight;
}

/// 字体层级：语义化封装，便于整体调档
abstract final class TypeScale {
  static TextStyle? pageTitle(BuildContext context) =>
      Theme.of(context).textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w600,
            letterSpacing: -0.2,
          );

  static TextStyle? sectionTitle(BuildContext context) =>
      Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
            letterSpacing: -0.1,
          );

  static TextStyle? body(BuildContext context) =>
      Theme.of(context).textTheme.bodyMedium;

  static TextStyle? caption(BuildContext context) =>
      Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.4);
}

/// 语义化表面样式：按亮/暗主题给出卡片、面板的填充与描边
abstract final class Surfaces {
  /// 卡片填充色
  static Color card(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return isDark
        ? scheme.surfaceContainerHigh
        : scheme.surfaceContainerLowest;
  }

  /// 次级面板填充色
  static Color panel(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return isDark ? scheme.surfaceContainer : scheme.surfaceContainerLow;
  }

  /// 分隔线颜色
  static Color divider(BuildContext context) =>
      Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.6);

  /// 柔和阴影：亮色主题下才明显，暗色主题靠层级区分
  static List<BoxShadow> softShadow(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (isDark) {
      return const <BoxShadow>[
        BoxShadow(color: Color(0x33000000), blurRadius: 12, offset: Offset(0, 2)),
      ];
    }
    return const <BoxShadow>[
      BoxShadow(color: Color(0x0F000000), blurRadius: 10, offset: Offset(0, 2)),
      BoxShadow(color: Color(0x08000000), blurRadius: 2, offset: Offset(0, 1)),
    ];
  }
}

/// 统一卡片装饰：圆角 + 填充 + 描边 + 柔和阴影
BoxDecoration cardDecoration(
  BuildContext context, {
  bool elevated = true,
  Color? color,
}) {
  final scheme = Theme.of(context).colorScheme;
  return BoxDecoration(
    color: color ?? Surfaces.card(context),
    borderRadius: Radii.cardRadius,
    border: Border.all(color: Surfaces.divider(context)),
    boxShadow: elevated ? Surfaces.softShadow(context) : null,
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: <Color>[
        (color ?? Surfaces.card(context)),
        Color.alphaBlend(
          scheme.primary.withValues(alpha: 0.03),
          color ?? Surfaces.card(context),
        ),
      ],
    ),
  );
}
