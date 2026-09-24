import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:oasx/config/design_tokens.dart';
import 'package:oasx/config/theme.dart';
import 'package:oasx/service/theme_service.dart';

/// 配色种子选择器：横向排列九种主题色圆点，当前项打勾
class ColorSeedPicker extends StatelessWidget {
  const ColorSeedPicker({super.key});

  @override
  Widget build(BuildContext context) {
    final themeService = Get.find<ThemeService>();
    final scheme = Theme.of(context).colorScheme;

    return Obx(() {
      final current = themeService.seed;
      return Wrap(
        spacing: Spacing.sm,
        runSpacing: Spacing.sm,
        alignment: WrapAlignment.end,
        children: ColorSeed.values.map((seed) {
          final selected = seed == current;
          return Tooltip(
            message: seed.labelZh,
            child: Semantics(
              label: seed.labelZh,
              selected: selected,
              button: true,
              child: InkWell(
                borderRadius: const BorderRadius.all(Radius.circular(Radii.sm)),
                onTap: () => themeService.switchSeed(seed),
                // 圆点视觉尺寸保持 30，靠外层 padding 把命中区撑到 42，
                // 满足触屏最小可点区域，同时不破坏九宫格的视觉密度。
                child: Padding(
                  padding: const EdgeInsets.all(Spacing.xsPlus),
                  child: AnimatedContainer(
                    duration: Motion.of(context, Motion.fast),
                    curve: Motion.standard,
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: seed.color,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: selected ? scheme.onSurface : Colors.transparent,
                        width: 2,
                      ),
                      boxShadow: selected
                          ? const <BoxShadow>[
                              BoxShadow(
                                color: Color(0x33000000),
                                blurRadius: 6,
                                offset: Offset(0, 2),
                              ),
                            ]
                          : null,
                    ),
                    // 打勾是纯装饰：选中态已由 Semantics.selected 播报，
                    // 读屏无需再念一个对勾图标。
                    child: ExcludeSemantics(
                      child: AnimatedOpacity(
                        duration: Motion.of(context, Motion.fast),
                        opacity: selected ? 1 : 0,
                        child: const Icon(
                          Icons.check,
                          size: 17,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        }).toList(growable: false),
      );
    });
  }
}
