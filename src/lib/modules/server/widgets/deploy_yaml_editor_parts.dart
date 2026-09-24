part of 'deploy_yaml_editor.dart';

class _DeployYamlNodeView extends StatelessWidget {
  const _DeployYamlNodeView({
    required this.node,
    required this.level,
    required this.controllerOf,
    required this.focusNodeOf,
    required this.onChanged,
    required this.isCollapsed,
    required this.onToggleSection,
  });

  final DeployYamlNode node;
  final int level;
  final TextEditingController Function(DeployYamlValueLine line) controllerOf;
  final FocusNode Function(DeployYamlValueLine line) focusNodeOf;
  final void Function(DeployYamlValueLine line, String value) onChanged;
  final bool Function(DeployYamlNode node) isCollapsed;
  final void Function(DeployYamlNode node) onToggleSection;

  @override
  Widget build(BuildContext context) {
    if (level == 0 && node.valueLine == null) {
      return _DeployYamlSectionCard(content: _buildSection(context));
    }
    return _buildSection(context);
  }

  Widget _buildSection(BuildContext context) {
    final valueLine = node.valueLine;
    if (valueLine != null) {
      return _DeployYamlValueItem(
        line: valueLine,
        comments: _commentText,
        controller: controllerOf(valueLine),
        focusNode: focusNodeOf(valueLine),
        onChanged: (value) => onChanged(valueLine, value),
      );
    }
    final collapsed = isCollapsed(node);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _DeployYamlSectionHeader(
          node: node,
          level: level,
          comments: _commentText,
          collapsed: collapsed,
          onTap: () => onToggleSection(node),
        ),
        if (!collapsed)
          for (final child in node.children)
            _DeployYamlNodeView(
              node: child,
              level: level + 1,
              controllerOf: controllerOf,
              focusNodeOf: focusNodeOf,
              onChanged: onChanged,
              isCollapsed: isCollapsed,
              onToggleSection: onToggleSection,
            ),
      ],
    ).paddingOnly(left: level <= 1 ? 0 : 14, bottom: level == 0 ? 0 : 6);
  }

  String get _commentText {
    return node.comments
        .map((line) => line.raw.trimLeft().replaceFirst(RegExp(r'^#\s?'), ''))
        .where((line) => line.trim().isNotEmpty)
        .join('\n');
  }
}

class _DeployYamlSectionCard extends StatelessWidget {
  const _DeployYamlSectionCard({required this.content});

  final Widget content;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 2,
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.42),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.md)),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: theme.colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(Radii.md),
        ),
        child: Padding(padding: const EdgeInsets.all(Spacing.md), child: content),
      ),
    ).paddingOnly(bottom: Spacing.smPlus);
  }
}

class _DeployYamlSectionHeader extends StatelessWidget {
  const _DeployYamlSectionHeader({
    required this.node,
    required this.level,
    required this.comments,
    required this.collapsed,
    required this.onTap,
  });

  final DeployYamlNode node;
  final int level;
  final String comments;
  final bool collapsed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(Radii.xs),
      onTap: onTap,
      child: Row(
        children: [
          Icon(
            collapsed
                ? Icons.keyboard_arrow_right_rounded
                : Icons.keyboard_arrow_down_rounded,
            size: level == 0 ? 22 : 20,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: Spacing.xs),
          Text(
            node.key,
            style: (level == 0
                    ? theme.textTheme.titleMedium
                    : theme.textTheme.titleSmall)
                ?.copyWith(fontWeight: FontWeight.bold),
          ).expanded(),
          if (comments.isNotEmpty) _DeployYamlHelpTooltip(message: comments),
        ],
      ).paddingOnly(top: level == 0 ? 0 : 4, bottom: level == 0 ? 12 : 8),
    );
  }
}
