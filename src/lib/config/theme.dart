import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:chinese_font_library/chinese_font_library.dart';

import 'design_tokens.dart';

const List<String> _webChineseFontFallback = <String>[
  'PingFang SC',
  'Hiragino Sans GB',
  'Microsoft YaHei',
  'Noto Sans SC',
  'Noto Sans CJK SC',
  'Source Han Sans SC',
  'WenQuanYi Micro Hei',
  'sans-serif',
];

/// 配色种子：用户可在设置页切换，按 name 持久化
enum ColorSeed {
  baseColor('M3 Baseline', '基础紫', Color(0xff6750a4)),
  indigo('Indigo', '靛蓝', Color(0xff3f51b5)),
  blue('Blue', '天蓝', Color(0xff2196f3)),
  teal('Teal', '青碧', Color(0xff009688)),
  green('Green', '森绿', Color(0xff4caf50)),
  yellow('Yellow', '暖黄', Color(0xfffbc02d)),
  orange('Orange', '活力橙', Color(0xfffb8c00)),
  deepOrange('Deep Orange', '朱砂', Color(0xffff5722)),
  pink('Pink', '樱粉', Color(0xffe91e63));

  const ColorSeed(this.label, this.labelZh, this.color);

  /// 英文标签
  final String label;

  /// 中文标签
  final String labelZh;

  /// 种子色
  final Color color;

  /// 按 name 查找，未知或空值回落到 baseColor
  static ColorSeed fromName(String? name) {
    if (name == null || name.isEmpty) {
      return ColorSeed.baseColor;
    }
    return ColorSeed.values.firstWhere(
      (seed) => seed.name == name,
      orElse: () => ColorSeed.baseColor,
    );
  }
}

/// 兼容旧引用（按英文标签索引）
const Map<String, Color> colorSeedMap = <String, Color>{
  'M3 Baseline': Color(0xff6750a4),
  'Indigo': Color(0xff3f51b5),
  'Blue': Color(0xff2196f3),
  'Teal': Color(0xff009688),
  'Green': Color(0xff4caf50),
  'Yellow': Color(0xfffbc02d),
  'Orange': Color(0xfffb8c00),
  'Deep Orange': Color(0xffff5722),
  'Pink': Color(0xffe91e63),
};

/// 亮色主题：按配色种子动态生成
ThemeData buildLightTheme([Color seed = const Color(0xff6750a4)]) {
  final scheme = ColorScheme.fromSeed(
    seedColor: seed,
    brightness: Brightness.light,
  );
  return _baseTheme(_tintNeutrals(scheme, seed), Brightness.light);
}

/// 暗色主题：按配色种子动态生成
ThemeData buildDarkTheme([Color seed = const Color(0xff6750a4)]) {
  final scheme = ColorScheme.fromSeed(
    seedColor: seed,
    brightness: Brightness.dark,
  );
  return _baseTheme(_tintNeutrals(scheme, seed), Brightness.dark);
}

/// 给中性表面注入极低 chroma 的品牌色倾向（tinted neutral）。
///
/// ## 为什么需要这一步
///
/// `ColorScheme.fromSeed` 生成的中性色是按「与种子同色相、但 chroma 趋近 0」
/// 推导的，实际落到 `surface` / `surfaceContainer*` 上时 chroma 常常只剩
/// 1–2 / 255，肉眼读起来就是一片死灰。死灰的问题是**与品牌色脱节** ——
/// 界面主体和被强调的控件像来自两套设计。
///
/// ## 做法
///
/// 不重新生成整套色板（那会破坏 M3 的 tonal palette 一致性，也会让
/// 对比度失控），而是**只对表面族做微量染色**：
///
/// 1. 取出种子的 HSL 色相 [hue]
/// 2. 对每个表面色，用 `HSLColor.fromColor(...).withHue(hue)` 换色相，
///    同时把 saturation 压到极低
/// 3. 用 `Color.alphaBlend` 以很小的 alpha 叠回原色，保留原明度
///
/// 关键点是**只改色相不改明度**。明度一旦动了，`onSurface` 系列的
/// 4.5:1 对比度就全废了 —— 而对比度是这个项目优先级最高的约束
/// （见 `.impeccable.md`：挂机一整晚不能看累）。
///
/// 染色强度按亮度分档。
///
/// ## 这两个数字是实测标定出来的，不是拍脑袋
///
/// 初版用了 0.06 —— 结果**完全无效**：暗色表面的 RGB 本来就在
/// 18~45 这个窄区间，6% 的混合量经过舍入后连一个色阶都动不了，
/// 等于没做（实测色相偏移 0.0°）。
///
/// 标定过程：
///
/// | strength | 18,18,20 → | 色相偏移 | 判断 |
/// |---|---|---|---|
/// | 0.06 | 18,18,20 | 0.0° | **无效** |
/// | 0.22 | 17,19,21 | -30° | 可见但偏弱 |
/// | 0.35 | 16,20,21 | -48° | **可见且不脏** ← 取这个 |
/// | 0.50 | 15,22,22 | -60° | 开始明显发青，过头 |
///
/// 亮色主题另算：亮色表面 RGB 在 230~250，差值空间大得多，
/// 同样的 alpha 视觉上重得多，所以取更小值。
const double _kDarkTintStrength = 0.35;
const double _kLightTintStrength = 0.20;

/// 染色饱和度：决定「有色的灰」还是「灰的色」。
/// 0.30 时染出来的是带明显色相倾向的中性色，仍然不会被认成彩色。
const double _kDarkTintSat = 0.30;
const double _kLightTintSat = 0.16;

ColorScheme _tintNeutrals(ColorScheme scheme, Color seed) {
  final hue = HSLColor.fromColor(seed).hue;
  final isDark = scheme.brightness == Brightness.dark;

  final strength = isDark ? _kDarkTintStrength : _kLightTintStrength;
  final saturation = isDark ? _kDarkTintSat : _kLightTintSat;

  /// 把 [base] 的色相换成品牌色相，再以 [strength] 叠回去。
  /// 明度、alpha 一律不动 —— 明度一动，`onSurface` 系列的
  /// 4.5:1 对比度就全废了。
  Color tint(Color base) {
    final hsl = HSLColor.fromColor(base);
    final target = HSLColor.fromAHSL(
      hsl.alpha,
      hue,
      saturation,
      hsl.lightness,
    ).toColor();
    return Color.alphaBlend(target.withValues(alpha: strength), base);
  }

  return scheme.copyWith(
    surface: tint(scheme.surface),
    surfaceDim: tint(scheme.surfaceDim),
    surfaceBright: tint(scheme.surfaceBright),
    surfaceContainerLowest: tint(scheme.surfaceContainerLowest),
    surfaceContainerLow: tint(scheme.surfaceContainerLow),
    surfaceContainer: tint(scheme.surfaceContainer),
    surfaceContainerHigh: tint(scheme.surfaceContainerHigh),
    surfaceContainerHighest: tint(scheme.surfaceContainerHighest),
    outlineVariant: tint(scheme.outlineVariant),
    outline: tint(scheme.outline),
  );
}

ThemeData _baseTheme(ColorScheme scheme, Brightness brightness) {
  final isDark = brightness == Brightness.dark;

  OutlineInputBorder outlined(Color color, [double width = 1]) =>
      OutlineInputBorder(
        borderRadius: const BorderRadius.all(Radius.circular(Radii.sm)),
        borderSide: BorderSide(color: color, width: width),
      );

  RoundedRectangleBorder rounded([double radius = Radii.sm]) =>
      RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(radius)),
      );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    brightness: brightness,
    textTheme: _buildTextTheme(brightness),
    scaffoldBackgroundColor: scheme.surface,
    canvasColor: scheme.surface,
    splashFactory: InkSparkle.splashFactory,
    visualDensity: VisualDensity.standard,
    // ---- 交互状态色 ----
    //
    // `InkWell` / `ListTile` / `NavigationRail` 这类组件的悬停、按压、
    // 焦点反馈默认取 `onSurface @ 0.08~0.12`，在本项目偏暗的表面上
    // 会显出一层「灰蒙蒙」的脏感，且和品牌色无关。
    //
    // 统一改为 primary 的低 alpha：悬停最轻、按压居中、焦点最重。
    // 强度按亮度分档 —— 同样的 alpha 在暗底上视觉更重，所以暗色取更小值。
    //
    // 注意这是**填充式**反馈。有描边的控件（输入框等）另由
    // `focusedBorder` 提供描边式焦点提示，两者互补而非重复。
    hoverColor: scheme.primary.withValues(alpha: isDark ? 0.05 : 0.04),
    focusColor: scheme.primary.withValues(alpha: isDark ? 0.09 : 0.06),
    highlightColor: scheme.primary.withValues(alpha: isDark ? 0.07 : 0.05),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: scheme.surface,
      indicatorColor: scheme.secondaryContainer,
      indicatorShape: rounded(Radii.sm),
      selectedIconTheme: IconThemeData(color: scheme.onSecondaryContainer),
      unselectedIconTheme: IconThemeData(color: scheme.onSurfaceVariant),
      selectedLabelTextStyle: TextStyle(
        color: scheme.onSurface,
        fontWeight: FontWeight.w600,
      ),
      unselectedLabelTextStyle: TextStyle(color: scheme.onSurfaceVariant),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: scheme.onSurface,
        fontSize: 16,
        fontWeight: FontWeight.w600,
      ),
    ),
    // ---- 表面层级 ----
    //
    // 暗色主题的「高度」必须靠**表面明度**表达，不能靠阴影
    // （阴影在黑底上根本看不见）。因此这里建立一条明确的四级梯度：
    //
    //   surface(底) < panel(surfaceContainer) < card(surfaceContainerHigh) < 浮层(dialog/menu)
    //
    // 关键修正：card 从 `surfaceContainerHigh` 提到 `surfaceContainerHigh`
    // 不变，但 **panel 从 `surfaceContainer` 明确下来**，让「面板底」和
    // 「卡片面」拉开一档可辨的差距。原先两者在某些种子下几乎同色，
    // 导致卡片看起来像「贴在面板上的一张贴纸」，层次糊成一团。
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      // 卡片比面板亮一档 —— 亮色主题反过来，卡片取最浅（近白）
      color: isDark ? scheme.surfaceContainerHigh : scheme.surfaceContainerLowest,
      shape: const RoundedRectangleBorder(borderRadius: Radii.cardRadius),
    ),
    // 描边收敛：`outlineVariant` 本身已经是低对比度色，
    // 暗色下再叠 0.4 alpha 会把分隔线压到几乎不可见（分隔失去意义），
    // 但拉满又会让满屏「格子感」。0.55 / 0.6 是实测下来
    // 「看得见但抢不了戏」的位置。
    dividerTheme: DividerThemeData(
      color: scheme.outlineVariant.withValues(alpha: isDark ? 0.55 : 0.6),
      space: 1,
      thickness: 1,
    ),
    listTileTheme: ListTileThemeData(
      shape: rounded(Radii.sm),
      iconColor: scheme.onSurfaceVariant,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: Spacing.md,
        vertical: Spacing.xxs,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: isDark
          ? scheme.surfaceContainerHigh.withValues(alpha: 0.5)
          : scheme.surfaceContainerHighest.withValues(alpha: 0.45),
      border: outlined(scheme.outlineVariant),
      enabledBorder: outlined(scheme.outlineVariant),
      disabledBorder: outlined(scheme.outlineVariant.withValues(alpha: 0.4)),
      focusedBorder: outlined(scheme.primary, 1.6),
      errorBorder: outlined(scheme.error),
      focusedErrorBorder: outlined(scheme.error, 1.6),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: Spacing.md,
        vertical: Spacing.md,
      ),
    ),
    // ---- 按钮 ----
    //
    // 触摸目标：桌面端鼠标精度高，但项目里有触屏设备（Win 平板），
    // 且 `Spacing.md`(=12) 的垂直内边距 + 14px 字高 ≈ 38px，
    // 低于 44px 下限。这里统一提到 `Spacing.mdPlus`(=14)，
    // 让默认按钮落到 ~44px，不靠调用点各自补 padding。
    //
    // `tapTargetSize` 保持 `shrinkWrap`（桌面）而非 `padded`（移动），
    // 因为列表里密集排布按钮时 padded 会撑出大量空白；
    // 靠真实 padding 达标比靠透明命中区达标更诚实。
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: rounded(),
        padding: const EdgeInsets.symmetric(
          horizontal: Spacing.lg,
          vertical: Spacing.mdPlus,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: rounded(),
        side: BorderSide(color: scheme.outlineVariant),
        padding: const EdgeInsets.symmetric(
          horizontal: Spacing.lg,
          vertical: Spacing.mdPlus,
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        shape: rounded(),
        padding: const EdgeInsets.symmetric(
          horizontal: Spacing.md,
          vertical: Spacing.xsPlus,
        ),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(shape: rounded(Radii.sm)),
    ),
    chipTheme: ChipThemeData(
      shape: const RoundedRectangleBorder(borderRadius: Radii.chipRadius),
      side: BorderSide(color: scheme.outlineVariant),
      labelStyle: TextStyle(color: scheme.onSurface, fontSize: 12),
    ),
    tooltipTheme: TooltipThemeData(
      waitDuration: const Duration(milliseconds: 400),
      decoration: BoxDecoration(
        color: scheme.inverseSurface,
        borderRadius: const BorderRadius.all(Radius.circular(Radii.sm)),
      ),
      textStyle: TextStyle(color: scheme.onInverseSurface, fontSize: 12),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: rounded(Radii.md),
      // 浮起提示默认贴底并和窗口边缘产生「悬空」感，
      // 给一点外边距让它和内容区保持视觉联系。
      insetPadding: const EdgeInsets.all(Spacing.lg),
    ),
    // ---- 浮层层级 ----
    //
    // 对话框 / 菜单 / 弹窗必须比卡片**更亮一档**，否则它们铺在卡片上时
    // 边界消失，看起来像没弹出来。暗色主题用 `surfaceContainerHighest`，
    // 亮色主题用纯 `surface`（最白）—— 两者都严格高于 `cardTheme.color`。
    dialogTheme: DialogThemeData(
      backgroundColor:
          isDark ? scheme.surfaceContainerHighest : scheme.surface,
      surfaceTintColor: Colors.transparent,
      elevation: isDark ? 0 : 6,
      shape: rounded(Radii.lg),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: isDark ? scheme.surfaceContainerHighest : scheme.surface,
      surfaceTintColor: Colors.transparent,
      elevation: isDark ? 0 : 6,
      shape: rounded(Radii.md),
    ),
    menuTheme: MenuThemeData(
      style: MenuStyle(
        shape: WidgetStatePropertyAll(rounded(Radii.md)),
        elevation: WidgetStatePropertyAll(isDark ? 0 : 6),
        backgroundColor: WidgetStatePropertyAll(
          isDark ? scheme.surfaceContainerHighest : scheme.surface,
        ),
      ),
    ),
    // ---- 滚动条 ----
    scrollbarTheme: ScrollbarThemeData(
      thickness: const WidgetStatePropertyAll(8),
      radius: const Radius.circular(Radii.xs),
      thumbVisibility: const WidgetStatePropertyAll(false),
      // 滚动条默认颜色在某些种子上几乎与底同色，滑不动看不出来。
      // 给一个明确偏低但可辨的取值。
      thumbColor: WidgetStatePropertyAll(
        scheme.onSurface.withValues(alpha: isDark ? 0.28 : 0.22),
      ),
      trackColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: <TargetPlatform, PageTransitionsBuilder>{
        TargetPlatform.windows: FadeUpwardsPageTransitionsBuilder(),
        TargetPlatform.linux: FadeUpwardsPageTransitionsBuilder(),
        TargetPlatform.macOS: FadeUpwardsPageTransitionsBuilder(),
        TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
        TargetPlatform.iOS: FadeUpwardsPageTransitionsBuilder(),
      },
    ),
    extensions: <ThemeExtension<dynamic>>[
      OasxEffects.dark(isDark),
    ],
  );
}

/// 通过 ThemeExtension 暴露少量派生样式，便于组件统一取用
@immutable
class OasxEffects extends ThemeExtension<OasxEffects> {
  const OasxEffects({required this.isDark});

  final bool isDark;

  factory OasxEffects.dark(bool isDark) => OasxEffects(isDark: isDark);

  @override
  OasxEffects copyWith({bool? isDark}) =>
      OasxEffects(isDark: isDark ?? this.isDark);

  @override
  OasxEffects lerp(ThemeExtension<OasxEffects>? other, double t) {
    if (other is! OasxEffects) {
      return this;
    }
    return OasxEffects(
      isDark: t < 0.5 ? isDark : other.isDark,
    );
  }
}

/// 兼容旧引用：默认种子的亮/暗主题
final ThemeData lightTheme = buildLightTheme();
final ThemeData darkTheme = buildDarkTheme();

TextTheme _buildTextTheme(Brightness brightness) {
  const baseTheme = TextTheme(
    bodyLarge: TextStyle(height: 1.45),
    bodyMedium: TextStyle(height: 1.45),
    bodySmall: TextStyle(height: 1.4),
    labelLarge: TextStyle(height: 1.3),
    labelMedium: TextStyle(height: 1.3),
    labelSmall: TextStyle(height: 1.3),
    titleLarge: TextStyle(height: 1.3),
    titleMedium: TextStyle(height: 1.3),
    titleSmall: TextStyle(height: 1.3),
  );
  if (kIsWeb) {
    return _applyFontFallback(baseTheme, _webChineseFontFallback);
  }
  return baseTheme.apply(fontFamily: 'LatoLato').useSystemChineseFont(
        brightness,
      );
}

TextTheme _applyFontFallback(TextTheme textTheme, List<String> fallback) {
  return textTheme.copyWith(
    bodyLarge: _applyTextStyleFallback(textTheme.bodyLarge, fallback),
    bodyMedium: _applyTextStyleFallback(textTheme.bodyMedium, fallback),
    bodySmall: _applyTextStyleFallback(textTheme.bodySmall, fallback),
    labelLarge: _applyTextStyleFallback(textTheme.labelLarge, fallback),
    labelMedium: _applyTextStyleFallback(textTheme.labelMedium, fallback),
    labelSmall: _applyTextStyleFallback(textTheme.labelSmall, fallback),
    titleLarge: _applyTextStyleFallback(textTheme.titleLarge, fallback),
    titleMedium: _applyTextStyleFallback(textTheme.titleMedium, fallback),
    titleSmall: _applyTextStyleFallback(textTheme.titleSmall, fallback),
  );
}

TextStyle? _applyTextStyleFallback(TextStyle? style, List<String> fallback) {
  return style?.copyWith(fontFamilyFallback: fallback);
}
