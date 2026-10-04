import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oasx/modules/home/models/script_statistics_models.dart';
import 'package:oasx/modules/home/widgets/interactive_statistics_dashboard.dart';

List<MapEntry<String, ScriptTaskStatistics>> data([int count = 2]) =>
    List.generate(
      count,
      (i) => MapEntry(
        'task$i',
        ScriptTaskStatistics.fromJson({
          'run_count': (i + 1) * 3,
          'total_duration_seconds': (i + 1) * 120,
          'battle': {'count': (i + 1) * 5, 'avg_duration_seconds': 20},
          'runs': [
            {
              'start_time': '2026-10-04 10:00:00',
              'end_time': '2026-10-04 10:02:00',
              'duration_seconds': 120,
            },
          ],
        }),
      ),
    );

Widget dashboard({
  List<String>? order,
  ValueChanged<List<String>>? onOrder,
  ValueChanged<String>? onSelect,
  List<MapEntry<String, ScriptTaskStatistics>>? entries,
  ScriptStatisticsChartMetric metric =
      ScriptStatisticsChartMetric.totalDuration,
}) => MaterialApp(
  home: Scaffold(
    body: InteractiveStatisticsDashboard(
      filters: const SizedBox(height: 36, child: Text('global filters')),
      entries: entries ?? data(),
      metric: metric,
      dateKey: '2026-10-04',
      onSelectTask: onSelect ?? (_) {},
      initialOrder: order ?? dashboardModuleIds,
      onOrderChanged: onOrder,
    ),
  ),
);

void main() {
  testWidgets(
    'drag previews move neighbors and release persists snapped order',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      List<String>? saved;
      await tester.pumpWidget(dashboard(onOrder: (value) => saved = value));
      final originalRuns = tester.getTopLeft(
        find.byKey(const ValueKey('module-runs')),
      );
      final target = tester.getCenter(
        find.byKey(const ValueKey('module-battles')),
      );
      final start = tester.getCenter(find.byKey(const ValueKey('drag-runs')));
      final gesture = await tester.startGesture(start);
      await gesture.moveBy(const Offset(20, 0));
      await gesture.moveTo(target + const Offset(-100, -80));
      await tester.pump(const Duration(milliseconds: 350));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(saved, isNotNull);
      expect(saved!.toSet(), dashboardModuleIds.toSet());
      expect(saved, isNot(dashboardModuleIds));
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('module-runs'))),
        isNot(originalRuns),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'expand switches through thumbnail strip and restores original slot',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(dashboard());
      final original = tester.getRect(
        find.byKey(const ValueKey('module-primary')),
      );
      await tester.tap(find.byKey(const ValueKey('expand-primary')));
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.byKey(const ValueKey('module-primary'))).height,
        greaterThan(original.height),
      );
      await tester.tap(find.byKey(const ValueKey('thumbnail-runs')));
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.byKey(const ValueKey('module-runs'))).height,
        greaterThan(236),
      );
      await tester.tap(find.byTooltip('收回模块').last);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('thumbnail-runs')), findsNothing);
      expect(
        tester.getRect(find.byKey(const ValueKey('module-primary'))),
        original,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('hover links all three charts and clears on pointer exit', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(dashboard());
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(
      tester.getCenter(find.byKey(const ValueKey('module-primary'))),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('shared-hover-guide')), findsNWidgets(3));
    await mouse.moveTo(const Offset(1, 1));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('shared-hover-guide')), findsNothing);
    await mouse.removePointer();
  });

  testWidgets(
    'metrics pin and restore continuously while global filters stay fixed',
    (tester) async {
      await tester.pumpWidget(dashboard());
      final filters = tester.getTopLeft(find.text('global filters'));
      final expanded = tester
          .getSize(find.byKey(const ValueKey('dashboard-metrics')))
          .height;
      await tester.drag(
        find.byKey(const ValueKey('dashboard-scroll')),
        const Offset(0, -240),
      );
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.text('global filters')), filters);
      expect(
        tester.getSize(find.byKey(const ValueKey('dashboard-metrics'))).height,
        lessThan(expanded),
      );
      await tester.drag(
        find.byKey(const ValueKey('dashboard-scroll')),
        const Offset(0, 400),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.byKey(const ValueKey('dashboard-metrics'))).height,
        expanded,
      );
    },
  );

  testWidgets('drawer compresses list, navigates in place and closes', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1100, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final selected = <String>[];
    await tester.pumpWidget(
      dashboard(
        order: const ['tasks', 'primary', 'runs', 'battles'],
        onSelect: selected.add,
      ),
    );
    final listWidth = tester
        .getSize(find.byKey(const ValueKey('module-tasks')))
        .width;
    await tester.tap(find.byKey(const ValueKey('task-task0')));
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byKey(const ValueKey('module-tasks'))).width,
      lessThan(listWidth),
    );
    final listState = tester.element(
      find.byKey(const ValueKey('dashboard-task-list')),
    );
    await tester.tap(find.byKey(const ValueKey('detail-next')));
    await tester.pumpAndSettle();
    expect(selected, ['task0', 'task1']);
    expect(
      tester.element(find.byKey(const ValueKey('dashboard-task-list'))),
      same(listState),
    );
    expect(find.byKey(const ValueKey('detail-content-task1')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('detail-close')));
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byKey(const ValueKey('module-tasks'))).width,
      listWidth,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'data and metric updates retain mounted dashboard and animate values',
    (tester) async {
      await tester.pumpWidget(dashboard());
      final before = tester.state(find.byType(InteractiveStatisticsDashboard));
      await tester.pumpWidget(
        dashboard(
          entries: data(3),
          metric: ScriptStatisticsChartMetric.runCount,
        ),
      );
      await tester.pump(const Duration(milliseconds: 160));
      expect(
        tester.state(find.byType(InteractiveStatisticsDashboard)),
        same(before),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  for (final width in [320.0, 480.0, 760.0]) {
    testWidgets('responsive layout and drawer have no overflow at $width', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(Size(width, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        dashboard(order: const ['tasks', 'primary', 'runs', 'battles']),
      );
      await tester.tap(find.byKey(const ValueKey('task-task0')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const ValueKey('detail-close')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('expand-tasks')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
