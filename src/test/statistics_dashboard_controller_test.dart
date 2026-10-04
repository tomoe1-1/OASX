import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:oasx/modules/home/controllers/dashboard_controller.dart';
import 'package:oasx/modules/home/controllers/statistics_controller.dart';
import 'package:oasx/modules/home/models/script_statistics_models.dart';
import 'package:oasx/modules/home/widgets/statistics_panel.dart';
import 'package:oasx/translation/i18n.dart';

class _MemoryStorage implements HomeDashboardStorage {
  final values = <String, dynamic>{};
  @override
  dynamic read(String key) => values[key];
  @override
  void write(String key, dynamic value) => values[key] = value;
}

class _OfflineDashboard extends HomeDashboardController {
  _OfflineDashboard(HomeDashboardStorage storage) : super(storage: storage);
  @override
  // ignore: must_call_super
  void onInit() {}
  @override
  // ignore: must_call_super
  void onClose() {}
}

class _OfflineStatistics extends HomeStatisticsController {
  @override
  // ignore: must_call_super
  void onInit() {}
}

ScriptStatisticsDay day(int runCount) => ScriptStatisticsDay.fromSnapshotJson({
  'script_name': 'tomoe',
  'total_runtime_seconds': 600,
  'tasks': {
    'Yuhun': {
      'run_count': runCount,
      'total_duration_seconds': 600,
      'battle': {'count': 20, 'avg_duration_seconds': 30},
      'runs': [],
    },
  },
}, dateKey: '2026-10-04');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _MemoryStorage storage;
  late HomeDashboardController dashboard;
  late HomeStatisticsController statistics;
  setUp(() {
    Get.testMode = true;
    storage = _MemoryStorage();
    dashboard = Get.put<HomeDashboardController>(_OfflineDashboard(storage));
    statistics = Get.put<HomeStatisticsController>(_OfflineStatistics());
  });
  tearDown(() => Get.reset());

  test('module order persists without overwriting workbench dimensions', () {
    final originalWidth = dashboard.workbenchCollectionWidth.value;
    statistics.saveDashboardModuleOrder([
      'tasks',
      'battles',
      'runs',
      'primary',
    ]);
    expect(statistics.dashboardModuleOrder, [
      'tasks',
      'battles',
      'runs',
      'primary',
    ]);
    expect(dashboard.workbenchCollectionWidth.value, originalWidth);
  });

  test('same-runtime snapshots refresh derived counts', () {
    statistics.statistics.value = day(3);
    expect(statistics.historyTaskEntries.single.value.runCount, 3);
    statistics.statistics.value = day(9);
    expect(statistics.historyTaskEntries.single.value.runCount, 9);
  });

  test('metric filtering updates task selection synchronously', () async {
    statistics.statistics.value = day(3);
    await statistics.selectHistoryMetric(
      ScriptStatisticsChartMetric.battleCount,
    );
    expect(statistics.historyChartLoading.value, false);
    expect(statistics.selectedTaskName.value, 'Yuhun');
  });

  testWidgets('capture real statistics panel for visual inspection', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1080, 1180));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    Get.addTranslations(Messages().keys);
    Get.locale = const Locale('zh', 'CN');
    statistics.availableDateKeys.assignAll(['2026-10-04', '2026-10-03']);
    statistics.selectedDateKey.value = '2026-10-04';
    statistics.statistics.value = ScriptStatisticsDay.fromSnapshotJson({
      'script_name': 'tomoe',
      'total_runtime_seconds': 3600,
      'tasks': {
        for (var i = 0; i < 5; i++)
          ['Yuhun', 'Awakening', 'Duel', 'Daily', 'RealmRaid'][i]: {
            'run_count': 4 + i * 3,
            'total_duration_seconds': 300 + i * 180,
            'battle': {'count': 10 + i * 4, 'avg_duration_seconds': 24},
            'runs': [
              {
                'start_time': '2026-10-04 10:00:00',
                'end_time': '2026-10-04 10:05:00',
                'duration_seconds': 300,
              },
            ],
          },
      },
    }, dateKey: '2026-10-04');
    await tester.runAsync(() async {
      final font = FontLoader('DashboardPreview');
      font.addFont(
        File(
          'C:/Windows/Fonts/msyh.ttc',
        ).readAsBytes().then((bytes) => ByteData.sublistView(bytes)),
      );
      await font.load();
      final icons = FontLoader('MaterialIcons');
      icons.addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
      await icons.load();
    });
    final capture = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(fontFamily: 'DashboardPreview'),
        home: RepaintBoundary(
          key: capture,
          child: const Scaffold(body: ScriptStatisticsPanel()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final boundary =
        capture.currentContext!.findRenderObject() as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await File(
        'build/dashboard-preview.png',
      ).writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
    expect(tester.takeException(), isNull);
  }, skip: !const bool.fromEnvironment('DASHBOARD_CAPTURE'));
}
