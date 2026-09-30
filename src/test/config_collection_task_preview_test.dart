import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:oasx/modules/home/controllers/dashboard_controller.dart';
import 'package:oasx/modules/home/models/config_model.dart';
import 'package:oasx/modules/home/models/taskitem_model.dart';
import 'package:oasx/modules/home/widgets/config_collection_task_preview.dart';
import 'package:oasx/modules/home/widgets/config_collection_tile.dart';
import 'package:oasx/translation/i18n_content.dart';

class _MemoryStorage implements HomeDashboardStorage {
  @override
  dynamic read(String key) => null;
  @override
  void write(String key, dynamic value) {}
}

void main() {
  setUp(() {
    Get.addTranslations({
      'zh_CN': {
        I18n.homeCurrentTask: '当前任务',
        I18n.homeNextTask: '下个任务',
        I18n.homeNoRunningTask: '暂无运行任务',
        I18n.homeCurrentTaskLoading: '正在获取',
        I18n.homeNoTask: '暂无任务',
        'Duel': '斗技',
        'DuelGuess': '对弈竞猜',
        'RealmRaid': '寮突破',
      },
    });
    Get.locale = const Locale('zh', 'CN');
  });
  tearDown(Get.reset);

  Future<void> pumpPreview(
    WidgetTester tester,
    ScriptModel script, {
    bool showWaitingTime = true,
  }) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 300,
            child: ConfigCollectionTaskPreview(
              script: script,
              showWaitingTime: showWaitingTime,
            ),
          ),
        ),
      ),
    ),
  );

  ScriptModel runningScript() => ScriptModel('tomoe')
    ..update(
      state: ScriptState.running,
      runningTask: TaskItemModel('tomoe', 'Duel', ''),
      pendingTaskList: [TaskItemModel('tomoe', 'DuelGuess', '')],
      waitingTaskList: [
        TaskItemModel('tomoe', 'RealmRaid', '2026-09-30 22:15:00'),
      ],
    );

  testWidgets('current task and queued next task have separate labels', (
    tester,
  ) async {
    await pumpPreview(tester, runningScript());
    expect(find.text('当前任务：斗技'), findsOneWidget);
    expect(find.text('下个任务：对弈竞猜'), findsOneWidget);
    expect(find.textContaining('寮突破'), findsNothing);
  });

  testWidgets('next task skips blank and duplicated running entries', (
    tester,
  ) async {
    final script = runningScript()
      ..pendingTaskList.insertAll(0, [
        TaskItemModel('tomoe', ' ', ''),
        TaskItemModel('tomoe', 'Duel', ''),
      ]);
    await pumpPreview(tester, script);
    expect(find.text('下个任务：对弈竞猜'), findsOneWidget);
  });

  testWidgets('waiting next task keeps its scheduled time', (tester) async {
    final script = runningScript()..pendingTaskList.clear();
    await pumpPreview(tester, script);
    expect(find.text('下个任务：寮突破 22:15:00'), findsOneWidget);
    await pumpPreview(tester, script, showWaitingTime: false);
    expect(find.text('下个任务：寮突破'), findsOneWidget);
  });

  testWidgets('stopped script does not show a stale running task', (
    tester,
  ) async {
    final script = runningScript()..state.value = ScriptState.inactive;
    await pumpPreview(tester, script);
    expect(find.text('当前任务：暂无运行任务'), findsOneWidget);
    expect(find.text('下个任务：对弈竞猜'), findsOneWidget);
  });

  testWidgets('unknown running task never borrows the next task name', (
    tester,
  ) async {
    final script = runningScript()..runningTask.value = TaskItemModel.empty();
    await pumpPreview(tester, script);
    expect(find.text('当前任务：正在获取'), findsOneWidget);
    expect(find.text('下个任务：对弈竞猜'), findsOneWidget);
  });

  testWidgets('empty config still shows both task rows', (tester) async {
    await pumpPreview(
      tester,
      ScriptModel('tomoe')..state.value = ScriptState.inactive,
    );
    expect(find.text('当前任务：暂无运行任务'), findsOneWidget);
    expect(find.text('下个任务：暂无任务'), findsOneWidget);
  });

  testWidgets('confirmed scheduler idle is distinct from unknown execution', (
    tester,
  ) async {
    final script = runningScript()
      ..runningTask.value = TaskItemModel.empty()
      ..currentTaskKnown.value = true;
    await pumpPreview(tester, script);
    expect(find.text('当前任务：暂无运行任务'), findsOneWidget);
    expect(find.text('下个任务：对弈竞猜'), findsOneWidget);
  });

  testWidgets('task switch and queue refresh update the card live', (
    tester,
  ) async {
    final script = runningScript();
    await pumpPreview(tester, script);
    script.update(
      runningTask: TaskItemModel('tomoe', 'RealmRaid', ''),
      pendingTaskList: [TaskItemModel('tomoe', 'Duel', '')],
    );
    await tester.pump();
    expect(find.text('当前任务：寮突破'), findsOneWidget);
    expect(find.text('下个任务：斗技'), findsOneWidget);
    script.state.value = ScriptState.inactive;
    await tester.pump();
    expect(find.text('当前任务：暂无运行任务'), findsOneWidget);
  });

  for (final width in [180.0, 260.0, 400.0]) {
    testWidgets('both rows fit config tile width $width with enlarged text', (
      tester,
    ) async {
      final script = runningScript();
      final controller = HomeDashboardController(storage: _MemoryStorage());
      controller.activeScriptName.value = script.name;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(1.6)),
              child: Center(
                child: SizedBox(
                  width: width,
                  child: ConfigCollectionTile(
                    controller: controller,
                    script: script,
                    onTap: () {},
                    onTogglePower: () {},
                    onRename: () {},
                    onExport: () {},
                    onDelete: () {},
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.text('当前任务：斗技'), findsOneWidget);
      expect(find.text('下个任务：对弈竞猜'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
