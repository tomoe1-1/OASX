import 'package:flutter/material.dart';
import 'package:styled_widget/styled_widget.dart';

import 'package:oasx/config/design_tokens.dart';

class SettingItem extends StatelessWidget {
  final Widget left;
  final Widget right;
  final VoidCallback? onTap;

  /// 右侧内容过宽时（如配色选择器）改为上下排列
  final bool stacked;

  const SettingItem({
    super.key,
    required this.left,
    required this.right,
    this.onTap,
    this.stacked = false,
  });

  @override
  Widget build(BuildContext context) {
    final Widget content = stacked
        ? <Widget>[
            left,
            right.padding(top: Spacing.sm).alignment(Alignment.centerRight),
          ].toColumn(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
          ).padding(vertical: Spacing.xs)
        : <Widget>[
            Flexible(child: left),
            const SizedBox(width: Spacing.sm),
            right,
          ].toRow(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
          ).padding(vertical: Spacing.xs);

    if (onTap == null) {
      return content;
    }
    return InkWell(
      onTap: onTap,
      borderRadius: const BorderRadius.all(Radius.circular(Radii.sm)),
      child: content,
    );
  }
}
