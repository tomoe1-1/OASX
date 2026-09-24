import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:oasx/config/design_tokens.dart';
import 'package:oasx/modules/common/widgets/segmented_tab_strip.dart';
import 'package:oasx/modules/home/controllers/dashboard_controller.dart';
import 'package:oasx/modules/home/models/config_model.dart';
import 'package:oasx/modules/home/models/home_workbench_layout.dart';
import 'package:oasx/modules/home/widgets/log_center_panel.dart';
import 'package:oasx/modules/home/widgets/statistics_panel.dart';
import 'package:oasx/modules/home/widgets/analysis_panel.dart';
import 'package:oasx/modules/home/widgets/task_catalog_panel.dart';
import 'package:oasx/modules/home/widgets/task_status_panel.dart';
import 'package:oasx/translation/i18n_content.dart';

class ActiveConfigPanel extends StatelessWidget {
  const ActiveConfigPanel({
    super.key,
    required this.controller,
    required this.layoutMode,
    required this.onChangeTab,
    required this.onOpenTask,
    required this.onTogglePower,
    required this.onRenameScript,
    required this.onDeleteScript,
    required this.onSetNextRun,
    required this.onQuickRun,
    required this.onQuickWait,
    required this.onBulkQuickRun,
    required this.onBulkQuickWait,
    this.onExpandRightSidebar,
    this.onBackToScripts,
  });

  final HomeDashboardController controller;
  final HomeWorkbenchLayoutMode layoutMode;
  final Future<void> Function(HomeWorkbenchTab tab) onChangeTab;
  final Future<void> Function(
    String taskName,
    HomeTaskParameterEntrySource source,
  )
  onOpenTask;
  final Future<void> Function(String scriptName, bool enable) onTogglePower;
  final Future<void> Function(String scriptName) onRenameScript;
  final Future<void> Function(String scriptName) onDeleteScript;
  final Future<void> Function(String taskName, String nextRun) onSetNextRun;
  final Future<void> Function(String taskName) onQuickRun;
  final Future<void> Function(String taskName) onQuickWait;
  final Future<void> Function() onBulkQuickRun;
  final Future<void> Function() onBulkQuickWait;
  final VoidCallback? onExpandRightSidebar;
  final VoidCallback? onBackToScripts;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Surfaces.panel(context),
        borderRadius: Radii.cardRadius,
        border: Border.all(color: Surfaces.divider(context)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: Obx(() {
          final script = controller.activeScriptModel;
          final currentTab = controller.displayedWorkbenchTabFor(layoutMode);
          final tabs = controller.workbenchTabsFor(layoutMode);
          if (script == null) {
            return Center(child: Text(I18n.homeNoScriptSelected.tr));
          }
          final isRunning = script.state.value == ScriptState.running;
          final bulkMode = controller.bulkQuickScheduleMode.value;
          final hasBulkTasks = controller
              .quickSchedulableTaskNamesFor(script)
              .isNotEmpty;
          final isBulkIdle = bulkMode == HomeBulkQuickScheduleMode.none;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _HeaderBar(
                script: script,
                isRunning: isRunning,
                isBulkIdle: isBulkIdle,
                hasBulkTasks: hasBulkTasks,
                bulkMode: bulkMode,
                onBackToScripts: onBackToScripts,
                onBulkQuickRun: onBulkQuickRun,
                onBulkQuickWait: onBulkQuickWait,
                onTogglePower: () => onTogglePower(script.name, !isRunning),
                onExpandRightSidebar: onExpandRightSidebar,
                state: controller.scriptStateFor(script),
              ),
              const SizedBox(height: Spacing.md),
              SegmentedTabStrip<HomeWorkbenchTab>(
                tabs: tabs,
                currentTab: currentTab,
                labelOf: _tabLabel,
                onSelected: onChangeTab,
              ),
              const SizedBox(height: Spacing.md),
              Expanded(
                child: AnimatedSwitcher(
                  duration: Motion.of(context, Motion.normal),
                  switchInCurve: Motion.standard,
                  switchOutCurve: Motion.standard,
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0, 0.02),
                        end: Offset.zero,
                      ).animate(animation),
                      child: child,
                    ),
                  ),
                  child: KeyedSubtree(
                    key: ValueKey<HomeWorkbenchTab>(currentTab),
                    child: _buildTabContent(script, currentTab),
                  ),
                ),
              ),
            ],
          );
        }),
      ),
    );
  }

  Widget _buildTabContent(ScriptModel script, HomeWorkbenchTab currentTab) {
    return switch (currentTab) {
      HomeWorkbenchTab.status => TaskStatusPanel(
        controller: controller,
        scriptModel: script,
        canQuickScheduleTask: (taskName) =>
            controller.canQuickScheduleTask(script, taskName),
        onSetNextRun: onSetNextRun,
        onQuickRun: onQuickRun,
        onQuickWait: onQuickWait,
        onEditTask: (taskName) =>
            onOpenTask(taskName, HomeTaskParameterEntrySource.overview),
      ),
      HomeWorkbenchTab.tasks => TaskCatalogPanel(
        controller: controller,
        scriptModel: script,
        onOpenTask: (taskName) =>
            onOpenTask(taskName, HomeTaskParameterEntrySource.tasks),
        onQuickRun: onQuickRun,
        onQuickWait: onQuickWait,
      ),
      HomeWorkbenchTab.stats => const ScriptStatisticsPanel(),
      HomeWorkbenchTab.logs => LogCenterPanel(scriptName: script.name),
      HomeWorkbenchTab.analysis => ScriptAnalysisPanel(scriptName: script.name),
    };
  }

  String _tabLabel(HomeWorkbenchTab value) {
    return switch (value) {
      HomeWorkbenchTab.status => I18n.overview.tr,
      HomeWorkbenchTab.tasks => I18n.homeTasksTab.tr,
      HomeWorkbenchTab.stats => I18n.homeStatsTab.tr,
      HomeWorkbenchTab.logs => I18n.log.tr,
      HomeWorkbenchTab.analysis => I18n.homeAnalysisTab.tr,
    };
  }
}

class _HeaderBar extends StatelessWidget {
  const _HeaderBar({
    required this.script,
    required this.isRunning,
    required this.isBulkIdle,
    required this.hasBulkTasks,
    required this.bulkMode,
    required this.state,
    required this.onTogglePower,
    required this.onBulkQuickRun,
    required this.onBulkQuickWait,
    this.onBackToScripts,
    this.onExpandRightSidebar,
  });

  final ScriptModel script;
  final bool isRunning;
  final bool isBulkIdle;
  final bool hasBulkTasks;
  final HomeBulkQuickScheduleMode bulkMode;
  final HomeScriptStateFilter state;
  final VoidCallback onTogglePower;
  final VoidCallback onBulkQuickRun;
  final VoidCallback onBulkQuickWait;
  final VoidCallback? onBackToScripts;
  final VoidCallback? onExpandRightSidebar;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = _stateColor(context, scheme, state);
    return Row(
      children: [
        if (onBackToScripts != null)
          Padding(
            padding: const EdgeInsets.only(right: Spacing.xs),
            child: IconButton(
              tooltip: I18n.scriptList.tr,
              onPressed: onBackToScripts,
              icon: const Icon(Icons.arrow_back_rounded),
            ),
          ),
        // 状态光点 + 脚本名，形成一个视觉锚点。
        // 光点是纯装饰（状态文字紧接其后），读屏时应跳过，
        // 否则会先念一个无名图形再念状态文字，产生冗余噪音。
        ExcludeSemantics(
          child: Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: accent,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: accent.withValues(alpha: 0.45),
                  blurRadius: 8,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: Spacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                script.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TypeScale.pageTitle(context),
              ),
              const SizedBox(height: 1),
              Text(
                _stateLabel(state),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TypeScale.caption(context)?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        _BulkQuickScheduleButton(
          icon: Icons.flash_on_rounded,
          tooltip: I18n.homeQuickRunAll.tr,
          loading: bulkMode == HomeBulkQuickScheduleMode.runNow,
          onPressed: isBulkIdle && hasBulkTasks ? onBulkQuickRun : null,
        ),
        _BulkQuickScheduleButton(
          icon: Icons.schedule_rounded,
          tooltip: I18n.homeQuickWaitAll.tr,
          loading: bulkMode == HomeBulkQuickScheduleMode.waitNow,
          onPressed: isBulkIdle && hasBulkTasks ? onBulkQuickWait : null,
        ),
        const SizedBox(width: Spacing.sm),
        _PowerButton(isRunning: isRunning, onPressed: onTogglePower),
        if (onExpandRightSidebar != null) ...[
          const SizedBox(width: Spacing.sm),
          IconButton.filledTonal(
            key: const ValueKey<String>(
              'home-workbench-expand-right-sidebar',
            ),
            tooltip: I18n.homeRestoreSidebar.tr,
            onPressed: onExpandRightSidebar,
            icon: const Icon(Icons.keyboard_double_arrow_left_rounded),
          ),
        ],
      ],
    );
  }

  static Color _stateColor(
    BuildContext context,
    ColorScheme scheme,
    HomeScriptStateFilter state,
  ) {
    return SemanticColors.forState(
      context,
      running: state == HomeScriptStateFilter.running,
      abnormal: state == HomeScriptStateFilter.abnormal,
      offline: state == HomeScriptStateFilter.offline,
      fallback: scheme.outline,
    );
  }

  static String _stateLabel(HomeScriptStateFilter state) {
    return switch (state) {
      HomeScriptStateFilter.running => I18n.trayRunningConfigs.tr,
      HomeScriptStateFilter.abnormal => I18n.trayAbnormalConfigs.tr,
      HomeScriptStateFilter.stopped => I18n.trayStoppedConfigs.tr,
      HomeScriptStateFilter.offline => I18n.networkError.tr,
      HomeScriptStateFilter.all => I18n.scheduler.tr,
    };
  }
}

/// 运行/停止主开关：带状态的 emphasized 按钮
class _PowerButton extends StatelessWidget {
  const _PowerButton({required this.isRunning, required this.onPressed});

  final bool isRunning;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final foreground =
        isRunning ? scheme.onErrorContainer : scheme.onPrimaryContainer;
    final background =
        isRunning ? scheme.errorContainer : scheme.primaryContainer;
    return Tooltip(
      message: isRunning ? I18n.stop.tr : I18n.run.tr,
      child: Material(
        color: background,
        borderRadius: Radii.chipRadius,
        child: InkWell(
          borderRadius: Radii.chipRadius,
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: Spacing.md,
              vertical: Spacing.sm,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isRunning
                      ? Icons.stop_circle_outlined
                      : Icons.play_circle_outline_rounded,
                  size: 18,
                  color: foreground,
                ),
                const SizedBox(width: Spacing.xsPlus),
                Text(
                  isRunning ? I18n.stop.tr : I18n.run.tr,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: foreground,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 顶部分段式页签已抽到 [SegmentedTabStrip] 供主工作台与右侧栏共用。

class _BulkQuickScheduleButton extends StatelessWidget {
  const _BulkQuickScheduleButton({
    required this.icon,
    required this.tooltip,
    required this.loading,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final bool loading;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: loading ? null : onPressed,
      icon: loading
          ? SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Theme.of(context).colorScheme.primary,
              ),
            )
          : Icon(icon),
    );
  }
}
