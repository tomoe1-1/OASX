import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:oasx/modules/home/controllers/dashboard_controller.dart';
import 'package:oasx/modules/home/models/config_model.dart';
import 'package:oasx/modules/home/widgets/config_collection_script_label.dart';
import 'package:oasx/modules/home/widgets/config_collection_task_preview.dart';
import 'package:oasx/translation/i18n_content.dart';
import 'package:oasx/config/design_tokens.dart';

class ConfigCollectionTile extends StatelessWidget {
  const ConfigCollectionTile({
    super.key,
    required this.controller,
    required this.script,
    required this.onTap,
    required this.onTogglePower,
    required this.onRename,
    required this.onExport,
    required this.onDelete,
  });

  static const _actionSpacing = 8.0;
  static const _compactLayoutThreshold = 200.0;
  final HomeDashboardController controller;
  final ScriptModel script;
  final VoidCallback onTap;
  final VoidCallback onTogglePower;
  final VoidCallback onRename;
  final VoidCallback onExport;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        return Obx(() {
          final isActive = controller.activeScriptName.value == script.name;
          final showLinkCheckbox = controller.isLinkModeEnabled.value;
          final isLinked = controller.isScriptLinked(script.name);
          final isDragCopyLoading = controller.isDragCopyPendingFor(
            script.name,
          );
          final compactThreshold =
              ConfigCollectionTile._compactLayoutThreshold +
              (showLinkCheckbox ? 64 : 0);
          final isCompact = constraints.maxWidth < compactThreshold;
          final rowColor = isActive
              ? theme.colorScheme.primaryContainer.withValues(alpha: 0.28)
              : Colors.transparent;
          final accentColor = _accentColor(
            context,
            controller.scriptCollectionStateFor(script),
          );
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 1),
            child: Material(
              color: rowColor,
              borderRadius: Radii.smRadius,
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: isDragCopyLoading ? null : onTap,
                child: AnimatedContainer(
                  duration: Motion.of(context, Motion.fast),
                  curve: Motion.standard,
                  padding: EdgeInsets.symmetric(
                    horizontal: Spacing.smPlus,
                    vertical: isCompact ? Spacing.sm : Spacing.smPlus,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: Radii.smRadius,
                    border: Border.all(
                      color: isActive
                          ? theme.colorScheme.primary.withValues(alpha: 0.35)
                          : Colors.transparent,
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      if (showLinkCheckbox) ...[
                        SizedBox(
                          width: 36,
                          height: 36,
                          child: Checkbox(
                            value: isLinked,
                            onChanged: (value) => controller.setScriptLinked(
                              script.name,
                              value ?? false,
                            ),
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                        const SizedBox(width: 2),
                      ],
                      Expanded(
                        child: Stack(
                          children: [
                            AbsorbPointer(
                              absorbing: isDragCopyLoading,
                              child: _ScriptMeta(
                                script: script,
                                compact: isCompact,
                                accentColor: accentColor,
                                powerButton: _PowerButton(
                                  onTogglePower: onTogglePower,
                                ),
                                popupButton: _ActionMenuButton(
                                  onRename: onRename,
                                  onExport: onExport,
                                  onDelete: onDelete,
                                ),
                              ),
                            ),
                            if (isDragCopyLoading)
                              const Positioned.fill(
                                child: _DragCopyLoadingMask(),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        });
      },
    );
  }

  Color _accentColor(BuildContext context, HomeScriptStateFilter value) {
    final scheme = Theme.of(context).colorScheme;
    return SemanticColors.forState(
      context,
      running: value == HomeScriptStateFilter.running,
      abnormal: value == HomeScriptStateFilter.abnormal,
      offline: value == HomeScriptStateFilter.offline,
      fallback: scheme.outline,
    );
  }
}

class _ScriptMeta extends StatelessWidget {
  const _ScriptMeta({
    required this.script,
    required this.compact,
    required this.accentColor,
    required this.powerButton,
    required this.popupButton,
  });

  final ScriptModel script;
  final bool compact;
  final Color accentColor;
  final Widget powerButton;
  final Widget popupButton;

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _RegularAccentBar(
              key: ValueKey<String>('config-accent-bar-${script.name}'),
              color: accentColor,
            ),
            const SizedBox(width: Spacing.smPlus),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Wrap(
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: Spacing.xs,
                    runSpacing: 2,
                    children: [powerButton, popupButton],
                  ),
                  const SizedBox(height: Spacing.xs),
                  ConfigCollectionScriptLabel(script: script, centered: true),
                ],
              ),
            ),
          ],
        ),
      );
    }
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _RegularAccentBar(
            key: ValueKey<String>('config-accent-bar-${script.name}'),
            color: accentColor,
          ),
          const SizedBox(width: Spacing.smPlus),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ConfigCollectionScriptLabel(script: script, centered: false),
                const SizedBox(height: Spacing.xsPlus),
                ConfigCollectionTaskPreview(script: script),
              ],
            ),
          ),
          const SizedBox(width: ConfigCollectionTile._actionSpacing),
          powerButton,
          popupButton,
        ],
      ),
    );
  }
}

class _DragCopyLoadingMask extends StatelessWidget {
  const _DragCopyLoadingMask();

  @override
  Widget build(BuildContext context) {
    return AbsorbPointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.68),
          borderRadius: BorderRadius.circular(Radii.md),
        ),
        child: const Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
        ),
      ),
    );
  }
}

class _RegularAccentBar extends StatelessWidget {
  const _RegularAccentBar({super.key, required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 6,
      height: double.infinity,
      child: Center(
        child: FractionallySizedBox(
          heightFactor: 0.8,
          child: AnimatedContainer(
            duration: Motion.settleOf(context),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(Radii.pill),
            ),
          ),
        ),
      ),
    );
  }
}

class _PowerButton extends StatelessWidget {
  const _PowerButton({required this.onTogglePower});

  final VoidCallback onTogglePower;

  @override
  Widget build(BuildContext context) {
    // 视觉尺寸仍是 32，但用 padding 把命中区撑到 40+
    // （iconSize 23 + padding 2*9 = 41），兼顾紧凑与触屏可点性。
    return IconButton(
      onPressed: onTogglePower,
      tooltip: I18n.run.tr,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints.tightFor(width: 41, height: 41),
      padding: const EdgeInsets.all(Spacing.smMid),
      iconSize: 23,
      icon: const Icon(Icons.power_settings_new_rounded),
    );
  }
}

class _ActionMenuButton extends StatelessWidget {
  const _ActionMenuButton({
    required this.onRename,
    required this.onExport,
    required this.onDelete,
  });

  final VoidCallback onRename;
  final VoidCallback onExport;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox.square(
      // 命中区 40，内部图标仍保持 18 的视觉尺寸。
      dimension: 40,
      child: PopupMenuButton<String>(
        padding: EdgeInsets.zero,
        tooltip: I18n.more.tr,
        icon: const Icon(Icons.more_vert_rounded, size: 18),
        onSelected: (value) async {
          if (value == 'rename') {
            onRename();
            return;
          }
          if (value == 'export') {
            onExport();
            return;
          }
          onDelete();
        },
        itemBuilder: (context) => [
          PopupMenuItem(value: 'rename', child: Text(I18n.rename.tr)),
          PopupMenuItem(value: 'export', child: Text(I18n.configExport.tr)),
          // 破坏性操作：与上面两项用分隔线隔开，并用错误色着色，
          // 拉开视觉距离，降低误删概率。
          const PopupMenuDivider(),
          PopupMenuItem(
            value: 'delete',
            child: Row(
              children: [
                Icon(Icons.delete_outline_rounded, size: 18, color: scheme.error),
                const SizedBox(width: Spacing.sm),
                Text(
                  I18n.delete.tr,
                  style: TextStyle(color: scheme.error),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
