import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:oasx/config/design_tokens.dart';
import 'package:oasx/modules/home/controllers/dashboard_controller.dart';
import 'package:oasx/translation/i18n_content.dart';
class ConfigStateIndicator extends StatelessWidget {
  const ConfigStateIndicator({
    super.key,
    required this.state,
    this.size = 18,
  });

  final HomeScriptStateFilter state;
  final double size;

  @override
  Widget build(BuildContext context) {
    final palette = _paletteFor(state, context);
    // 这个光点承载的是「脚本处于什么状态」这个关键信息，
    // 但读屏用户看不到颜色和形状。用 Semantics 把它转成可朗读的状态文本，
    // 否则屏幕阅读器念到的只是一个无意义的图标。
    return Semantics(
      label: palette.label,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: palette.color.withValues(alpha: 0.12),
          shape: BoxShape.circle,
        ),
        child: SizedBox(
          width: size + 12,
          height: size + 12,
          child: Icon(
            palette.icon,
            size: size,
            color: palette.color,
          ),
        ),
      ),
    );
  }

  _StatePalette _paletteFor(
    HomeScriptStateFilter value,
    BuildContext context,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return switch (value) {
      HomeScriptStateFilter.running => _StatePalette(
          color: SemanticColors.success(context),
          icon: Icons.circle_rounded,
          label: I18n.run.tr,
        ),
      HomeScriptStateFilter.abnormal => _StatePalette(
          color: SemanticColors.warning(context),
          icon: Icons.circle_rounded,
          label: I18n.homeScriptAbnormal.tr,
        ),
      HomeScriptStateFilter.stopped => _StatePalette(
          color: scheme.outline,
          icon: Icons.donut_large,
          label: I18n.stop.tr,
        ),
      HomeScriptStateFilter.offline => _StatePalette(
          color: SemanticColors.info(context),
          icon: Icons.browser_updated_rounded,
          label: I18n.homeScriptOffline.tr,
        ),
      HomeScriptStateFilter.all => _StatePalette(
          color: scheme.outline,
          icon: Icons.circle,
          label: I18n.selectAll.tr,
        ),
    };
  }
}

class _StatePalette {
  const _StatePalette({
    required this.color,
    required this.icon,
    required this.label,
  });

  final Color color;
  final IconData icon;

  /// 读屏可朗读的状态名。
  final String label;
}
