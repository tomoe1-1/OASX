import 'package:flutter/material.dart';
import 'package:oasx/config/design_tokens.dart';

/// 通用的分段式页签条：等分占宽、滑动高亮块。
///
/// 用于主工作台与右侧栏的页签，替换原先零散的 ChoiceChip 行，
/// 让两处页签在视觉上保持同一套语言。
class SegmentedTabStrip<T> extends StatelessWidget {
  const SegmentedTabStrip({
    super.key,
    required this.tabs,
    required this.currentTab,
    required this.labelOf,
    required this.onSelected,
    this.iconOf,
  });

  /// 全部页签，按展示顺序排列。
  final List<T> tabs;

  /// 当前选中的页签。
  final T currentTab;

  /// 页签文案解析器。
  final String Function(T tab) labelOf;

  /// 页签图标解析器，返回 null 表示不显示图标。
  final IconData? Function(T tab)? iconOf;

  /// 选中回调。
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(Spacing.xs),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: Radii.chipRadius,
      ),
      child: Row(
        children: tabs.map((tab) {
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1),
              child: _SegmentedTabItem(
                label: labelOf(tab),
                icon: iconOf?.call(tab),
                selected: tab == currentTab,
                onTap: () => onSelected(tab),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _SegmentedTabItem extends StatelessWidget {
  const _SegmentedTabItem({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  final String label;
  final IconData? icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final foreground =
        selected ? scheme.onSurface : scheme.onSurfaceVariant;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: Radii.chipRadius,
        onTap: onTap,
        child: AnimatedContainer(
          duration: Motion.of(context, Motion.fast),
          curve: Motion.standard,
          padding: const EdgeInsets.symmetric(
            horizontal: Spacing.sm,
            vertical: Spacing.smMid,
          ),
          decoration: BoxDecoration(
            color: selected ? scheme.surface : Colors.transparent,
            borderRadius: Radii.chipRadius,
            boxShadow: selected ? Surfaces.softShadow(context) : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 16, color: foreground),
                const SizedBox(width: Spacing.xs),
              ],
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: foreground,
                        fontWeight:
                            selected ? FontWeight.w600 : FontWeight.w500,
                      ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
