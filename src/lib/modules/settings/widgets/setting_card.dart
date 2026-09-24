import 'package:flutter/material.dart';
import 'package:oasx/config/design_tokens.dart';
import 'package:oasx/modules/settings/widgets/setting_item.dart';
import 'package:styled_widget/styled_widget.dart';

class SettingCard extends StatelessWidget {
  final String title;
  final List<SettingItem> items;

  const SettingCard({
    super.key,
    required this.title,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(Spacing.lg),
        child: <Widget>[
          Row(
            children: [
              // 左侧主题色小竖条，为分区标题建立视觉锚点
              Container(
                width: 3,
                height: 16,
                decoration: BoxDecoration(
                  color: scheme.primary,
                  borderRadius: const BorderRadius.all(
                    Radius.circular(Radii.pill),
                  ),
                ),
              ),
              const SizedBox(width: Spacing.sm),
              Text(title, style: TypeScale.sectionTitle(context)),
            ],
          ),
          const SizedBox(height: Spacing.md),
          Divider(color: Surfaces.divider(context), height: 1),
          const SizedBox(height: Spacing.xs),
          ...items.map((item) => item.padding(vertical: Spacing.xxs)),
        ].toColumn(crossAxisAlignment: CrossAxisAlignment.start),
      ),
    );
  }
}
