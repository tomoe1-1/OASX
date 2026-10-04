import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:oasx/modules/home/models/script_statistics_models.dart';
import 'package:oasx/modules/home/widgets/statistics_detail_section.dart';
import 'package:oasx/modules/home/widgets/statistics_formatters.dart';

const _motion = Duration(milliseconds: 320);
const dashboardModuleIds = ['primary', 'runs', 'battles', 'tasks'];

/// A persistent dashboard surface: filters update data without replacing it.
class InteractiveStatisticsDashboard extends StatefulWidget {
  const InteractiveStatisticsDashboard({
    super.key,
    required this.filters,
    required this.entries,
    required this.metric,
    required this.dateKey,
    required this.onSelectTask,
    this.loading = false,
    this.message = '',
    this.initialOrder = dashboardModuleIds,
    this.onOrderChanged,
  });

  final Widget filters;
  final List<MapEntry<String, ScriptTaskStatistics>> entries;
  final ScriptStatisticsChartMetric metric;
  final String dateKey;
  final ValueChanged<String> onSelectTask;
  final bool loading;
  final String message;
  final List<String> initialOrder;
  final ValueChanged<List<String>>? onOrderChanged;

  @override
  State<InteractiveStatisticsDashboard> createState() => _DashboardState();
}

class _DashboardState extends State<InteractiveStatisticsDashboard> {
  final _scroll = ScrollController();
  late List<String> _order;
  String? _expanded;
  String? _dragged;
  String? _hovered;
  String? _detail;
  Offset _dragOffset = Offset.zero;
  Offset _dragOrigin = Offset.zero;
  Map<String, Rect> _slots = {};
  double _restoreScrollOffset = 0;

  void _setExpanded(String? id) {
    if (_expanded == null && _scroll.hasClients) {
      _restoreScrollOffset = _scroll.offset;
    }
    setState(() => _expanded = id);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final target = id == null ? _restoreScrollOffset : 0.0;
      _scroll.animateTo(
        target.clamp(0.0, _scroll.position.maxScrollExtent),
        duration: _motion,
        curve: Curves.easeInOutCubic,
      );
    });
  }

  @override
  void initState() {
    super.initState();
    _order = widget.initialOrder
        .where(dashboardModuleIds.contains)
        .toSet()
        .toList();
    _order.addAll(dashboardModuleIds.where((id) => !_order.contains(id)));
  }

  @override
  void didUpdateWidget(covariant InteractiveStatisticsDashboard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.dateKey != widget.dateKey) {
      _hovered = null;
      _detail = null;
    }
    if (!widget.entries.any((e) => e.key == _hovered)) _hovered = null;
    if (!widget.entries.any((e) => e.key == _detail)) _detail = null;
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _openTask(String name) {
    if (widget.loading) return;
    setState(() => _detail = name);
    widget.onSelectTask(name);
  }

  void _moveDetail(int delta) {
    final index = widget.entries.indexWhere((e) => e.key == _detail);
    final next = index + delta;
    if (next >= 0 && next < widget.entries.length) {
      _openTask(widget.entries[next].key);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Outside the scroll view so every module shares the same fixed filter.
        Padding(padding: const EdgeInsets.all(12), child: widget.filters),
        if (widget.loading) const LinearProgressIndicator(minHeight: 2),
        if (widget.message.isNotEmpty)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(widget.message),
          ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final drawerWidth = _detail == null
                  ? 0.0
                  : math.min(340.0, constraints.maxWidth * .48);
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: CustomScrollView(
                      key: const ValueKey('dashboard-scroll'),
                      controller: _scroll,
                      slivers: [
                        SliverPersistentHeader(
                          pinned: true,
                          delegate: _MetricsHeader(
                            entries: widget.entries,
                            dateKey: widget.dateKey,
                          ),
                        ),
                        SliverPadding(
                          padding: const EdgeInsets.all(12),
                          sliver: SliverToBoxAdapter(
                            child: LayoutBuilder(
                              builder: (context, gridConstraints) {
                                return _buildGrid(
                                  context,
                                  gridConstraints.maxWidth,
                                  constraints.maxHeight,
                                );
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  AnimatedContainer(
                    key: const ValueKey('dashboard-drawer'),
                    width: drawerWidth,
                    duration: _motion,
                    curve: Curves.easeInOutCubic,
                    clipBehavior: Clip.hardEdge,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      border: Border(
                        left: BorderSide(color: Theme.of(context).dividerColor),
                      ),
                    ),
                    child: OverflowBox(
                      alignment: Alignment.topRight,
                      minWidth: drawerWidth,
                      maxWidth: drawerWidth,
                      child: drawerWidth > 0
                          ? _buildDrawer()
                          : const SizedBox.shrink(),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        AnimatedSize(
          duration: _motion,
          child: _expanded == null
              ? const SizedBox.shrink()
              : SizedBox(
                  height: 64,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    children: _order
                        .map(
                          (id) => Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ActionChip(
                              key: ValueKey('thumbnail-$id'),
                              avatar: Icon(
                                id == _expanded
                                    ? Icons.check_circle
                                    : Icons.dashboard_outlined,
                                size: 18,
                              ),
                              label: Text(_title(id)),
                              onPressed: () => _setExpanded(id),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildGrid(BuildContext context, double width, double viewportHeight) {
    const gap = 12.0;
    final columns = width >= 620 ? 2 : 1;
    final unit = (width - gap * (columns - 1)) / columns;
    var x = 0;
    var y = 0.0;
    var rowHeight = 0.0;
    final slots = <String, Rect>{};
    for (final id in _order) {
      final span = id == 'primary' || id == 'tasks' ? columns : 1;
      final height = id == 'tasks'
          ? 340.0
          : id == 'primary'
          ? 300.0
          : 236.0;
      if (x + span > columns) {
        y += rowHeight + gap;
        x = 0;
        rowHeight = 0;
      }
      slots[id] = Rect.fromLTWH(
        x * (unit + gap),
        y,
        span * unit + (span - 1) * gap,
        height,
      );
      x += span;
      rowHeight = math.max(rowHeight, height);
      if (x == columns) {
        y += rowHeight + gap;
        x = 0;
        rowHeight = 0;
      }
    }
    _slots = slots;
    final fullHeight = y + (x > 0 ? rowHeight : 0);
    final expandedHeight = math.max(360.0, viewportHeight - 100);
    final ordered = [
      ..._order.where((id) => id != _expanded && id != _dragged),
      if (_expanded != null) _expanded!,
      if (_dragged != null) _dragged!,
    ];
    return SizedBox(
      height: _expanded == null ? fullHeight : expandedHeight,
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: ordered.map((id) {
          final rect = id == _expanded
              ? Rect.fromLTWH(0, 0, width, expandedHeight)
              : slots[id]!;
          final dragging = id == _dragged;
          final position = dragging ? _dragOrigin + _dragOffset : rect.topLeft;
          return AnimatedPositioned(
            key: ValueKey('module-$id'),
            duration: dragging ? Duration.zero : _motion,
            curve: Curves.easeInOutCubic,
            left: position.dx,
            top: position.dy,
            width: rect.width,
            height: rect.height,
            child: IgnorePointer(
              ignoring: _expanded != null && id != _expanded,
              child: AnimatedOpacity(
                opacity: _expanded == null || id == _expanded ? 1 : 0,
                duration: _motion,
                child: _module(id, dragging),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  String _title(String id) => switch (id) {
    'primary' => '任务指标',
    'runs' => '运行次数',
    'battles' => '战斗次数',
    _ => '任务列表',
  };

  Widget _module(String id, bool dragging) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      elevation: dragging ? 12 : 0,
      color: scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Row(
            children: [
              if (_expanded == null)
                GestureDetector(
                  key: ValueKey('drag-$id'),
                  onPanStart: (_) => setState(() {
                    _dragged = id;
                    _dragOrigin = _slots[id]!.topLeft;
                    _dragOffset = Offset.zero;
                  }),
                  onPanUpdate: (event) {
                    setState(() {
                      _dragOffset += event.delta;
                      final center =
                          _dragOrigin +
                          _dragOffset +
                          Offset(_slots[id]!.width / 2, _slots[id]!.height / 2);
                      final nearest = _slots.entries
                          .reduce(
                            (a, b) =>
                                (a.value.center - center).distance <
                                    (b.value.center - center).distance
                                ? a
                                : b,
                          )
                          .key;
                      if (nearest != id) {
                        final target = _order.indexOf(nearest);
                        _order.remove(id);
                        _order.insert(target, id);
                      }
                    });
                  },
                  onPanEnd: (_) => _finishDrag(),
                  onPanCancel: _finishDrag,
                  child: const MouseRegion(
                    cursor: SystemMouseCursors.grab,
                    child: Padding(
                      padding: EdgeInsets.all(12),
                      child: Icon(Icons.drag_indicator, size: 20),
                    ),
                  ),
                ),
              Expanded(
                child: InkWell(
                  key: ValueKey('expand-$id'),
                  onTap: () => _setExpanded(_expanded == id ? null : id),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(_title(id)),
                  ),
                ),
              ),
              IconButton(
                tooltip: _expanded == id ? '收回模块' : '放大模块',
                onPressed: () => _setExpanded(_expanded == id ? null : id),
                icon: Icon(
                  _expanded == id ? Icons.close : Icons.open_in_full,
                  size: 18,
                ),
              ),
            ],
          ),
          Expanded(
            child: IgnorePointer(
              ignoring: widget.loading,
              child: id == 'tasks'
                  ? _taskList()
                  : _LinkedChart(
                      entries: widget.entries,
                      metric: id == 'primary'
                          ? widget.metric
                          : id == 'runs'
                          ? ScriptStatisticsChartMetric.runCount
                          : ScriptStatisticsChartMetric.battleCount,
                      hovered: _hovered,
                      onHover: (name) {
                        if (_hovered != name) setState(() => _hovered = name);
                      },
                      onSelect: _openTask,
                    ),
            ),
          ),
        ],
      ),
    );
  }

  void _finishDrag() {
    setState(() {
      _dragged = null;
      _dragOffset = Offset.zero;
    });
    widget.onOrderChanged?.call(List.unmodifiable(_order));
  }

  Widget _taskList() {
    if (widget.entries.isEmpty) return const Center(child: Text('当前筛选没有任务数据'));
    return ListView.builder(
      key: const ValueKey('dashboard-task-list'),
      itemCount: widget.entries.length,
      itemBuilder: (context, index) {
        final entry = widget.entries[index];
        return ListTile(
          key: ValueKey('task-${entry.key}'),
          selected: entry.key == _detail,
          title: Text(
            entry.key.tr,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            '${entry.value.runCount} 次 · ${formatStatisticsDuration(entry.value.totalDurationSeconds)}',
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _openTask(entry.key),
        );
      },
    );
  }

  Widget _buildDrawer() {
    final index = widget.entries.indexWhere((e) => e.key == _detail);
    final runs =
        index < 0
              ? <ScriptTaskRunRecord>[]
              : [...widget.entries[index].value.runs]
          ..sort(
            (a, b) => (b.endTime ?? b.startTime ?? DateTime(0)).compareTo(
              a.endTime ?? a.startTime ?? DateTime(0),
            ),
          );
    return Column(
      children: [
        Row(
          children: [
            IconButton(
              key: const ValueKey('detail-previous'),
              tooltip: '上一项',
              onPressed: index > 0 ? () => _moveDetail(-1) : null,
              icon: const Icon(Icons.keyboard_arrow_up),
            ),
            IconButton(
              key: const ValueKey('detail-next'),
              tooltip: '下一项',
              onPressed: index < widget.entries.length - 1
                  ? () => _moveDetail(1)
                  : null,
              icon: const Icon(Icons.keyboard_arrow_down),
            ),
            const Spacer(),
            IconButton(
              key: const ValueKey('detail-close'),
              tooltip: '关闭详情',
              onPressed: () => setState(() => _detail = null),
              icon: const Icon(Icons.close),
            ),
          ],
        ),
        Expanded(
          child: SingleChildScrollView(
            key: ValueKey('detail-content-$_detail'),
            padding: const EdgeInsets.all(12),
            child: ScriptStatisticsDetailSection(
              taskName: _detail ?? '',
              runs: runs,
            ),
          ),
        ),
      ],
    );
  }
}

class _MetricsHeader extends SliverPersistentHeaderDelegate {
  _MetricsHeader({required this.entries, required this.dateKey});
  final List<MapEntry<String, ScriptTaskStatistics>> entries;
  final String dateKey;
  @override
  double get minExtent => 52;
  @override
  double get maxExtent => 132;
  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final t = (shrinkOffset / (maxExtent - minExtent)).clamp(0.0, 1.0);
    final values = [
      entries.fold<double>(0, (v, e) => v + e.value.totalDurationSeconds),
      entries.fold<double>(0, (v, e) => v + e.value.runCount),
      entries.fold<double>(0, (v, e) => v + e.value.battleCount),
    ];
    return Material(
      key: const ValueKey('dashboard-metrics'),
      color: Theme.of(context).colorScheme.surface,
      elevation: overlapsContent ? 3 : 0,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Column(
          children: [
            ClipRect(
              child: Align(
                heightFactor: 1 - t,
                child: Opacity(
                  opacity: 1 - t,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text('$dateKey · 当前筛选汇总', maxLines: 1),
                  ),
                ),
              ),
            ),
            Expanded(
              child: Row(
                children: List.generate(
                  3,
                  (i) => Expanded(
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(end: values[i]),
                      duration: _motion,
                      builder: (context, value, _) => FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Opacity(
                              opacity: 1 - t,
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    ['累计时长', '运行次数', '战斗次数'][i],
                                    style: Theme.of(
                                      context,
                                    ).textTheme.labelSmall,
                                  ),
                                  _RollingValue(
                                    i == 0
                                        ? formatStatisticsDuration(value)
                                        : value.round().toString(),
                                    style: TextStyle(
                                      fontSize: 24 - 8 * t,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Opacity(
                              opacity: t,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    ['时长', '运行', '战斗'][i],
                                    style: Theme.of(
                                      context,
                                    ).textTheme.labelSmall,
                                  ),
                                  const SizedBox(width: 6),
                                  _RollingValue(
                                    i == 0
                                        ? formatStatisticsDuration(value)
                                        : value.round().toString(),
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _MetricsHeader oldDelegate) => true;
}

class _RollingValue extends StatelessWidget {
  const _RollingValue(this.value, {required this.style});
  final String value;
  final TextStyle style;
  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
    duration: const Duration(milliseconds: 120),
    transitionBuilder: (child, animation) => ClipRect(
      child: FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween(
            begin: const Offset(0, .35),
            end: Offset.zero,
          ).animate(animation),
          child: child,
        ),
      ),
    ),
    child: Text(value, key: ValueKey(value), style: style),
  );
}

/// All charts use identical task positions, so the hover guide is shared.
class _LinkedChart extends StatelessWidget {
  const _LinkedChart({
    required this.entries,
    required this.metric,
    required this.hovered,
    required this.onHover,
    required this.onSelect,
  });
  final List<MapEntry<String, ScriptTaskStatistics>> entries;
  final ScriptStatisticsChartMetric metric;
  final String? hovered;
  final ValueChanged<String?> onHover;
  final ValueChanged<String> onSelect;
  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) return const Center(child: Text('当前筛选没有任务数据'));
    final maxValue = entries.fold<double>(
      1,
      (v, e) => math.max(v, e.value.metricValueFor(metric)),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final step = constraints.maxWidth / entries.length;
          final hoverIndex = entries.indexWhere((e) => e.key == hovered);
          return MouseRegion(
            onExit: (_) => onHover(null),
            onHover: (event) {
              final index = (event.localPosition.dx / step).floor().clamp(
                0,
                entries.length - 1,
              );
              onHover(entries[index].key);
            },
            child: Stack(
              children: [
                Positioned.fill(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: entries.map((entry) {
                      final value = entry.value.metricValueFor(metric);
                      final selected = hovered == entry.key;
                      return Expanded(
                        child: AnimatedOpacity(
                          opacity: hovered == null || selected ? 1 : .25,
                          duration: const Duration(milliseconds: 140),
                          child: Tooltip(
                            message:
                                '${entry.key.tr}: ${formatStatisticsMetricByType(value, metric)}',
                            child: InkWell(
                              onTap: () => onSelect(entry.key),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  if (selected)
                                    Text(
                                      formatStatisticsMetricByType(
                                        value,
                                        metric,
                                      ),
                                      maxLines: 1,
                                      style: const TextStyle(fontSize: 10),
                                    ),
                                  Flexible(
                                    child: AnimatedContainer(
                                      duration: _motion,
                                      curve: Curves.easeInOutCubic,
                                      height: math.max(
                                        3,
                                        (constraints.maxHeight - 48) *
                                            value /
                                            maxValue,
                                      ),
                                      margin: EdgeInsets.symmetric(
                                        horizontal: math.min(4, step / 8),
                                      ),
                                      decoration: BoxDecoration(
                                        color: statisticsTaskColor(
                                          context,
                                          entry.key,
                                        ),
                                        borderRadius: BorderRadius.circular(5),
                                      ),
                                    ),
                                  ),
                                  SizedBox(
                                    height: 30,
                                    child: Center(
                                      child: Text(
                                        entry.key.tr,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontSize: 10),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
                if (hoverIndex >= 0)
                  Positioned(
                    key: const ValueKey('shared-hover-guide'),
                    left: (hoverIndex + .5) * step,
                    top: 0,
                    bottom: 30,
                    child: IgnorePointer(
                      child: Container(
                        width: 1,
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withValues(alpha: .5),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
