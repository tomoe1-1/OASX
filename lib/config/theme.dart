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
  return _baseTheme(scheme, Brightness.light);
}

/// 暗色主题：按配色种子动态生成
ThemeData buildDarkTheme([Color seed = const Color(0xff6750a4)]) {
  final scheme = ColorScheme.fromSeed(
    seedColor: seed,
    brightness: Brightness.dark,
  );
  return _baseTheme(scheme, Brightness.dark);
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
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: isDark ? scheme.surfaceContainerHigh : scheme.surfaceContainerLowest,
      shape: const RoundedRectangleBorder(borderRadius: Radii.cardRadius),
    ),
    dividerTheme: DividerThemeData(
      color: scheme.outlineVariant.withValues(alpha: isDark ? 0.4 : 0.6),
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
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: rounded(),
        padding: const EdgeInsets.symmetric(
          horizontal: Spacing.lg,
          vertical: Spacing.md,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: rounded(),
        side: BorderSide(color: scheme.outlineVariant),
        padding: const EdgeInsets.symmetric(
          horizontal: Spacing.lg,
          vertical: Spacing.md,
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(shape: rounded()),
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
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: isDark ? scheme.surfaceContainerHigh : scheme.surface,
      shape: rounded(Radii.lg),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: isDark ? scheme.surfaceContainerHigh : scheme.surfaceContainerLowest,
      shape: rounded(Radii.md),
    ),
    menuTheme: MenuThemeData(
      style: MenuStyle(
        shape: WidgetStatePropertyAll(rounded(Radii.md)),
        backgroundColor: WidgetStatePropertyAll(
          isDark ? scheme.surfaceContainerHigh : scheme.surfaceContainerLowest,
        ),
      ),
    ),
    scrollbarTheme: const ScrollbarThemeData(
      thickness: WidgetStatePropertyAll(8),
      radius: Radius.circular(Radii.xs),
      thumbVisibility: WidgetStatePropertyAll(false),
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
