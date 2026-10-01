import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:oasx/modules/home/controllers/dashboard_controller.dart';
import 'package:oasx/modules/home/models/home_workbench_layout.dart';
import 'package:oasx/modules/home/widgets/home_backdrop.dart';
import 'package:oasx/config/design_tokens.dart';

/// Hosts the responsive home workbench layout and divider interaction.
class HomeWorkbenchBody extends StatefulWidget {
  const HomeWorkbenchBody({
    super.key,
    required this.controller,
    required this.collectionBuilder,
    required this.detailsBuilder,
    required this.sidebar,
  });

  /// Home dashboard controller providing persisted split state.
  final HomeDashboardController controller;

  /// Builds the script collection pane for the resolved layout.
  final Widget Function(HomeWorkbenchLayoutMode layoutMode) collectionBuilder;

  /// Builds the active workbench pane for the resolved layout.
  final Widget Function(
    HomeWorkbenchLayoutMode layoutMode,
    VoidCallback? onExpandRightSidebar,
  )
  detailsBuilder;

  /// Right sidebar widget reused in three-pane mode.
  final Widget sidebar;

  @override
  State<HomeWorkbenchBody> createState() => _HomeWorkbenchBodyState();
}

class _HomeWorkbenchBodyState extends State<HomeWorkbenchBody> {
  /// Tracks whether drag collapse has temporarily merged the log pane.
  bool _forceTwoPane = false;

  /// Remembers the width at which the right-side collapse was committed.
  double? _forcedTwoPaneWidth;

  /// Remembers the collection width at which the right-side collapse was committed.
  double? _forcedTwoPaneCollectionWidth;

  /// Tracks whether the left divider is actively dragging.
  bool _isDraggingLeftDivider = false;

  /// Constraints used by the previous layout pass, including window height.
  BoxConstraints? _lastConstraints;

  /// Remembers the latest width resolved by the current layout pass.
  double? _lastResolvedWidth;

  /// Remembers the latest collection width resolved by the current layout pass.
  double? _lastResolvedCollectionWidth;

  /// Stores a live collection width while the left divider is actively dragging.
  double? _dragCollectionWidth;

  /// Stores the raw collection width target while the left divider is dragging.
  double? _dragTargetCollectionWidth;

  /// Stores a live split ratio while the divider is actively dragging.
  double? _dragSplitRatio;

  /// Stores the raw detail width target while the divider is actively dragging.
  double? _dragTargetDetailsWidth;

  /// Stores the pane currently highlighted as a pending collapse target.
  HomeWorkbenchCollapseSide? _pendingCollapseSide;

  /// Stores the current pending collapse progress for visual feedback.
  double _pendingCollapseProgress = 0;

  /// Tracks whether releasing the pointer should commit the collapse.
  bool _collapseOnRelease = false;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final persistedCollectionWidth =
          widget.controller.workbenchCollectionWidth.value;
      final persistedSplitRatio = widget.controller.workbenchSplitRatio.value;
      return LayoutBuilder(
        builder: (context, constraints) {
          if (_lastConstraints != null && _lastConstraints != constraints) {
            // Native window resizing can remove the active divider before its
            // recognizer delivers drag-end. Discard that unfinished preview
            // before resolving the new panes; keep the persisted dimensions.
            _clearDividerDragState();
          }
          _lastConstraints = constraints;
          // 右缘立绘舞台：底衬的少女脸落在这条无面板区里全亮显示。
          // 舞台宽度由 [backdropStageWidth] 统一给出 —— 这里的
          // `constraints.maxWidth` 就是它要求的「工作台内容宽」，
          // painter 侧用 `size.width - 2×Spacing.md` 换算成同一个值。
          final stageWidth = backdropStageWidth(constraints.maxWidth);
          // 面板几何全部在「扣掉舞台后」的宽度里解 —— 舞台是 Row
          // 末尾的真实占位，不是面板下面透出来的。
          final usableWidth = constraints.maxWidth - stageWidth;
          final unrestrictedLayout = resolveHomeWorkbenchLayout(
            maxWidth: usableWidth,
            collectionWidth: persistedCollectionWidth,
            splitRatio: persistedSplitRatio,
          );
          final layout = _resolveLayout(
            maxWidth: usableWidth,
            persistedCollectionWidth: persistedCollectionWidth,
            persistedSplitRatio: persistedSplitRatio,
            unrestrictedLayout: unrestrictedLayout,
          );
          final layoutMode = layout.mode;
          widget.controller.setWorkbenchLayoutMode(layoutMode);
          final collection = widget.collectionBuilder(layoutMode);
          final canExpandRightSidebar =
              _forceTwoPane &&
              unrestrictedLayout.mode == HomeWorkbenchLayoutMode.threePane;
          final details = _buildPaneFrame(
            child: widget.detailsBuilder(
              layoutMode,
              canExpandRightSidebar ? _handleRightSidebarExpand : null,
            ),
            highlighted:
                _pendingCollapseSide == HomeWorkbenchCollapseSide.workbench,
            progress: _pendingCollapseProgress,
          );
          if (layoutMode != HomeWorkbenchLayoutMode.singlePane) {
            return _buildDesktopLayout(
              layout: layout,
              collection: collection,
              details: details,
              stageWidth: stageWidth,
            );
          }
          return Obx(() {
            final showWorkspace =
                widget.controller.workbenchPage.value ==
                    HomeWorkbenchPage.workspace &&
                widget.controller.activeScriptName.value.trim().isNotEmpty;
            return showWorkspace ? details : collection;
          });
        },
      );
    });
  }

  /// Builds the shared desktop skeleton so left-divider drags survive layout changes.
  ///
  /// [stageWidth] 是右缘立绘舞台占位：底衬的少女脸落在这条无面板区
  /// 里全亮显示，所以详情/日志面板的右缘收进到这里为止。宽度由
  /// [backdropStageWidth] 统一给出（painter 侧用同一公式定位立绘），
  /// 三栏空间不足时它会自己让步到 0，此时 Row 退回旧几何。
  Widget _buildDesktopLayout({
    required HomeWorkbenchLayout layout,
    required Widget collection,
    required Widget details,
    required double stageWidth,
  }) {
    final isThreePane = layout.mode == HomeWorkbenchLayoutMode.threePane;
    return Row(
      key: const ValueKey<String>('home-workbench-desktop'),
      children: [
        SizedBox(width: layout.collectionWidth, child: collection),
        _WorkbenchDivider(
          key: const ValueKey<String>('home-workbench-left-divider'),
          onDragStart: () => _handleLeftDragStart(layout),
          onDragUpdate: (details) => _handleLeftDragUpdate(details, layout),
          onDragEnd: _handleLeftDragEnd,
          onDragCancel: _handleDividerDragCancel,
          collapseSide: null,
          collapseProgress: 0,
        ),
        SizedBox(width: layout.detailsWidth, child: details),
        if (isThreePane) ...[
          _WorkbenchDivider(
            key: const ValueKey<String>('home-workbench-right-divider'),
            onDragStart: () => _handleRightDragStart(layout),
            onDragUpdate: (details) => _handleRightDragUpdate(details, layout),
            onDragEnd: _handleRightDragEnd,
            onDragCancel: _handleDividerDragCancel,
            collapseSide: _pendingCollapseSide,
            collapseProgress: _pendingCollapseProgress,
          ),
          SizedBox(
            width: layout.logWidth,
            child: _buildPaneFrame(
              child: widget.sidebar,
              highlighted:
                  _pendingCollapseSide == HomeWorkbenchCollapseSide.logs,
              progress: _pendingCollapseProgress,
            ),
          ),
        ],
        // 舞台占位必须留在最后：它不参与拖拽与折叠，只在空间富余时
        // 给底衬让出一条「看得见少女」的呼吸区。
        if (stageWidth > 0) SizedBox(width: stageWidth),
      ],
    );
  }

  /// Resolves the active layout and restores three-pane mode when legal again.
  HomeWorkbenchLayout _resolveLayout({
    required double maxWidth,
    required double persistedCollectionWidth,
    required double persistedSplitRatio,
    required HomeWorkbenchLayout unrestrictedLayout,
  }) {
    final currentCollectionWidth =
        _dragCollectionWidth ?? persistedCollectionWidth;
    final currentSplitRatio = _dragSplitRatio ?? persistedSplitRatio;
    _lastResolvedWidth = maxWidth;
    _lastResolvedCollectionWidth = currentCollectionWidth;
    _scheduleThreePaneRestoreIfNeeded(unrestrictedLayout.mode);
    return resolveHomeWorkbenchLayout(
      maxWidth: maxWidth,
      collectionWidth: currentCollectionWidth,
      splitRatio: currentSplitRatio,
      forceTwoPane: _forceTwoPane,
    );
  }

  /// Schedules three-pane restoration once the layout becomes legal again.
  void _scheduleThreePaneRestoreIfNeeded(
    HomeWorkbenchLayoutMode unrestrictedMode,
  ) {
    if (!_forceTwoPane ||
        _isDraggingLeftDivider ||
        !_hasRestoreTriggerChanged() ||
        unrestrictedMode != HomeWorkbenchLayoutMode.threePane) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !_forceTwoPane ||
          _isDraggingLeftDivider ||
          !_hasRestoreTriggerChanged()) {
        return;
      }
      setState(() {
        _forceTwoPane = false;
        _forcedTwoPaneWidth = null;
        _forcedTwoPaneCollectionWidth = null;
      });
    });
  }

  /// Returns whether width or left-divider changes should restore three panes.
  bool _hasRestoreTriggerChanged() {
    final forcedWidth = _forcedTwoPaneWidth;
    final forcedCollectionWidth = _forcedTwoPaneCollectionWidth;
    final lastResolvedWidth = _lastResolvedWidth;
    final lastResolvedCollectionWidth = _lastResolvedCollectionWidth;
    if (forcedWidth == null ||
        forcedCollectionWidth == null ||
        lastResolvedWidth == null ||
        lastResolvedCollectionWidth == null) {
      return false;
    }
    final widthChanged = (lastResolvedWidth - forcedWidth).abs() > 0.5;
    final collectionChanged =
        (lastResolvedCollectionWidth - forcedCollectionWidth).abs() > 0.5;
    return widthChanged || collectionChanged;
  }

  /// Starts tracking left-divider movement from the current desktop width.
  void _handleLeftDragStart(HomeWorkbenchLayout layout) {
    _isDraggingLeftDivider = true;
    _dragCollectionWidth = layout.collectionWidth;
    _dragTargetCollectionWidth = layout.collectionWidth;
  }

  /// Updates the live collection width while keeping at least a two-pane desktop.
  void _handleLeftDragUpdate(
    DragUpdateDetails details,
    HomeWorkbenchLayout layout,
  ) {
    if (!_isDraggingLeftDivider) {
      return;
    }
    final currentTargetWidth =
        _dragTargetCollectionWidth ?? layout.collectionWidth;
    final nextTargetWidth = currentTargetWidth + details.delta.dx;
    final nextCollectionWidth = clampHomeWorkbenchCollectionWidth(
      layout: layout,
      targetCollectionWidth: nextTargetWidth,
    );
    setState(() {
      _dragTargetCollectionWidth = nextTargetWidth;
      _dragCollectionWidth = nextCollectionWidth;
    });
  }

  /// Persists the last valid collection width after dragging the left divider.
  void _handleLeftDragEnd(DragEndDetails details) {
    if (!mounted || !_isDraggingLeftDivider) {
      return;
    }
    final dragCollectionWidth = _dragCollectionWidth;
    if (dragCollectionWidth != null) {
      widget.controller.setWorkbenchCollectionWidth(dragCollectionWidth);
    }
    setState(() {
      _isDraggingLeftDivider = false;
      _dragCollectionWidth = null;
      _dragTargetCollectionWidth = null;
    });
  }

  /// Starts tracking right-divider movement from the current three-pane width.
  void _handleRightDragStart(HomeWorkbenchLayout layout) {
    _dragSplitRatio = layout.appliedSplitRatio;
    _dragTargetDetailsWidth = layout.detailsWidth;
    _pendingCollapseSide = null;
    _pendingCollapseProgress = 0;
    _collapseOnRelease = false;
  }

  /// Updates the live split ratio while exposing a buffered collapse state.
  void _handleRightDragUpdate(
    DragUpdateDetails details,
    HomeWorkbenchLayout layout,
  ) {
    if (_dragSplitRatio == null) {
      return;
    }
    final currentTargetWidth = _dragTargetDetailsWidth ?? layout.detailsWidth;
    final nextTargetWidth = currentTargetWidth + details.delta.dx;
    final dragState = resolveHomeWorkbenchDragState(
      layout: layout,
      targetDetailsWidth: nextTargetWidth,
    );
    setState(() {
      _forceTwoPane = false;
      _dragTargetDetailsWidth = nextTargetWidth;
      _dragSplitRatio = dragState.splitRatio;
      _pendingCollapseSide = dragState.collapseSide;
      _pendingCollapseProgress = dragState.collapseProgress;
      _collapseOnRelease = dragState.shouldCollapseOnRelease;
    });
  }

  /// Persists the last valid split or commits a buffered collapse on release.
  void _handleRightDragEnd(DragEndDetails details) {
    if (!mounted || _dragSplitRatio == null) {
      return;
    }
    final dragSplitRatio = _dragSplitRatio;
    final collapseSide = _pendingCollapseSide;
    if (dragSplitRatio != null) {
      widget.controller.setWorkbenchSplitRatio(dragSplitRatio);
    }
    if (_collapseOnRelease && collapseSide != null) {
      final preservedTab = switch (collapseSide) {
        HomeWorkbenchCollapseSide.workbench =>
          widget.controller.displayedWorkbenchSidebarTabFor(
            HomeWorkbenchLayoutMode.threePane,
          ),
        HomeWorkbenchCollapseSide.logs =>
          widget.controller.displayedWorkbenchTabFor(
            HomeWorkbenchLayoutMode.threePane,
          ),
      };
      widget.controller.setActiveWorkbenchTabValue(preservedTab);
    }
    setState(() {
      _forceTwoPane = _collapseOnRelease;
      _forcedTwoPaneWidth = _collapseOnRelease ? _lastResolvedWidth : null;
      _forcedTwoPaneCollectionWidth = _collapseOnRelease
          ? _lastResolvedCollectionWidth
          : null;
      _dragSplitRatio = null;
      _dragTargetDetailsWidth = null;
      _pendingCollapseSide = null;
      _pendingCollapseProgress = 0;
      _collapseOnRelease = false;
    });
  }

  /// Clears transient divider previews without changing stored pane sizes.
  void _clearDividerDragState() {
    _isDraggingLeftDivider = false;
    _dragCollectionWidth = null;
    _dragTargetCollectionWidth = null;
    _dragSplitRatio = null;
    _dragTargetDetailsWidth = null;
    _pendingCollapseSide = null;
    _pendingCollapseProgress = 0;
    _collapseOnRelease = false;
  }

  void _handleDividerDragCancel() {
    if (!mounted) {
      return;
    }
    setState(_clearDividerDragState);
  }

  /// Restores the desktop right sidebar without changing window width.
  void _handleRightSidebarExpand() {
    if (!_forceTwoPane || !mounted) {
      return;
    }
    setState(() {
      _forceTwoPane = false;
      _forcedTwoPaneWidth = null;
      _forcedTwoPaneCollectionWidth = null;
    });
  }

  /// Builds a subtle pane highlight while a collapse is pending.
  Widget _buildPaneFrame({
    required Widget child,
    required bool highlighted,
    required double progress,
  }) {
    if (!highlighted) {
      return child;
    }
    final primary = Theme.of(context).colorScheme.primary;
    return AnimatedContainer(
      duration: Motion.of(context, Motion.fast),
      curve: Motion.standard,
      padding: const EdgeInsets.all(Spacing.xxs),
      decoration: BoxDecoration(
        borderRadius: Radii.cardRadius,
        border: Border.all(
          color: primary.withValues(alpha: 0.45 + progress * 0.35),
          width: 1.5,
        ),
      ),
      child: child,
    );
  }
}

class _WorkbenchDivider extends StatelessWidget {
  const _WorkbenchDivider({
    super.key,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
    required this.onDragCancel,
    required this.collapseSide,
    required this.collapseProgress,
  });

  /// Callback fired when the user starts dragging the divider.
  final VoidCallback onDragStart;

  /// Callback fired for each horizontal drag delta.
  final ValueChanged<DragUpdateDetails> onDragUpdate;

  /// Callback fired when the drag gesture ends.
  final ValueChanged<DragEndDetails> onDragEnd;

  /// Callback fired if the recognizer cancels before completing a drag.
  final VoidCallback onDragCancel;

  /// Side currently highlighted as the pending collapse target.
  final HomeWorkbenchCollapseSide? collapseSide;

  /// Normalized progress within the pending collapse buffer.
  final double collapseProgress;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dividerColor = Surfaces.divider(context);
    // 待折叠侧的高亮：不铺色块，只把「将要被折叠的那条边」
    // 用一根细的强调色杆标出来。
    //
    // 旧实现是在分隔条里铺一个 `width/2` 宽的圆角色块（primary @12~34%）。
    // 问题是色块的面积和「谁要被折叠」这件事没有对应关系 —— 用户看到
    // 的是一团彩色，而不是一个会执行的动作。改成贴着目标侧画一根 2px
    // 竖杆：面积足够小，位置本身就是信息（左杆 = 折叠左面板）。
    final highlightColor = scheme.primary.withValues(
      alpha: 0.55 + collapseProgress * 0.45,
    );
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: (_) => onDragStart(),
        onHorizontalDragUpdate: onDragUpdate,
        onHorizontalDragEnd: onDragEnd,
        onHorizontalDragCancel: onDragCancel,
        child: SizedBox(
          width: kHomeWorkbenchDividerWidth,
          child: Stack(
            children: [
              if (collapseSide != null)
                Align(
                  alignment: collapseSide == HomeWorkbenchCollapseSide.workbench
                      ? Alignment.centerLeft
                      : Alignment.centerRight,
                  child: Container(
                    width: 2,
                    decoration: BoxDecoration(
                      color: highlightColor,
                      borderRadius: BorderRadius.circular(Radii.pill),
                    ),
                  ),
                ),
              Center(
                child: AnimatedContainer(
                  duration: Motion.of(context, Motion.fast),
                  curve: Motion.standard,
                  width: collapseSide == null ? 2 : 3,
                  decoration: BoxDecoration(
                    color: collapseSide == null ? dividerColor : scheme.primary,
                    borderRadius: BorderRadius.circular(Radii.pill),
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
