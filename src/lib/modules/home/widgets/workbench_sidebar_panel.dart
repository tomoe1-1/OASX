import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:oasx/config/design_tokens.dart';
import 'package:oasx/modules/common/widgets/segmented_tab_strip.dart';
import 'package:oasx/modules/home/controllers/dashboard_controller.dart';
import 'package:oasx/modules/home/models/home_workbench_layout.dart';
import 'package:oasx/modules/home/widgets/log_center_panel.dart';
import 'package:oasx/modules/home/widgets/statistics_panel.dart';
import 'package:oasx/modules/home/widgets/analysis_panel.dart';
import 'package:oasx/translation/i18n_content.dart';

/// Hosts the desktop right sidebar for statistics and logs.
class WorkbenchSidebarPanel extends StatelessWidget {
  /// Creates the right workbench sidebar.
  const WorkbenchSidebarPanel({
    super.key,
    required this.controller,
    required this.scriptName,
  });

  /// Dashboard controller that owns sidebar tab state.
  final HomeDashboardController controller;

  /// Active script rendered by the sidebar.
  final String scriptName;

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
          final tabs = controller.workbenchSidebarTabsFor(
            HomeWorkbenchLayoutMode.threePane,
          );
          final currentTab = controller.displayedWorkbenchSidebarTabFor(
            HomeWorkbenchLayoutMode.threePane,
          );
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SegmentedTabStrip<HomeWorkbenchTab>(
                tabs: tabs,
                currentTab: currentTab,
                labelOf: _tabLabel,
                iconOf: _tabIcon,
                onSelected: controller.setActiveWorkbenchSidebarTabValue,
              ),
              const SizedBox(height: Spacing.md),
              Expanded(
                child: AnimatedSwitcher(
                  duration: Motion.of(context, Motion.normal),
                  switchInCurve: Motion.standard,
                  switchOutCurve: Motion.standard,
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: child,
                  ),
                  child: KeyedSubtree(
                    key: ValueKey<HomeWorkbenchTab>(currentTab),
                    child: switch (currentTab) {
                      HomeWorkbenchTab.stats => const ScriptStatisticsPanel(),
                      HomeWorkbenchTab.logs =>
                        LogCenterPanel(scriptName: scriptName),
                      HomeWorkbenchTab.analysis =>
                        ScriptAnalysisPanel(scriptName: scriptName),
                      _ => const SizedBox.shrink(),
                    },
                  ),
                ),
              ),
            ],
          );
        }),
      ),
    );
  }

  /// Resolves a localized label for one sidebar tab.
  String _tabLabel(HomeWorkbenchTab value) {
    return switch (value) {
      HomeWorkbenchTab.stats => I18n.homeStatsTab.tr,
      HomeWorkbenchTab.logs => I18n.log.tr,
      HomeWorkbenchTab.analysis => I18n.homeAnalysisTab.tr,
      _ => '',
    };
  }

  /// Resolves an icon for one sidebar tab.
  IconData? _tabIcon(HomeWorkbenchTab value) {
    return switch (value) {
      HomeWorkbenchTab.stats => Icons.insights_rounded,
      HomeWorkbenchTab.logs => Icons.receipt_long_rounded,
      HomeWorkbenchTab.analysis => Icons.auto_graph_rounded,
      _ => null,
    };
  }
}
