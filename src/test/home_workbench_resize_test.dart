import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_nb_net/flutter_net.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart' hide Response;
import 'package:get_storage/get_storage.dart';
import 'package:oasx/api/api_client.dart';
import 'package:oasx/api/sse_client.dart';
import 'package:oasx/modules/args/index.dart';
import 'package:oasx/modules/home/controllers/dashboard_controller.dart';
import 'package:oasx/modules/home/controllers/statistics_controller.dart';
import 'package:oasx/modules/home/models/config_model.dart';
import 'package:oasx/modules/home/models/home_workbench_layout.dart';
import 'package:oasx/modules/home/models/taskitem_model.dart';
import 'package:oasx/modules/home/widgets/active_config_panel.dart';
import 'package:oasx/modules/home/widgets/config_collection_panel.dart';
import 'package:oasx/modules/home/widgets/home_workbench_body.dart';
import 'package:oasx/modules/home/widgets/log_center_panel.dart';
import 'package:oasx/modules/home/widgets/statistics_panel.dart';
import 'package:oasx/modules/home/widgets/task_parameter_panel.dart';
import 'package:oasx/modules/home/widgets/workbench_sidebar_panel.dart';
import 'package:oasx/modules/log/log_browser_models.dart';
import 'package:oasx/modules/log/script_log_browser_controller.dart';
import 'package:oasx/service/script_service.dart';
import 'package:oasx/service/websocket_service.dart';
import 'package:oasx/translation/i18n.dart';

class _MemoryStorage implements HomeDashboardStorage {
  final values = <String, dynamic>{};
  @override
  dynamic read(String key) => values[key];
  @override
  void write(String key, dynamic value) => values[key] = value;
}

class _UnusedStorage implements GetStorage {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected persistent storage access');
}

class _ScriptService extends ScriptService {
  _ScriptService() : super(storage: _UnusedStorage());
  // The service's production onInit reloads the user's backend and storage.
  @override
  // ignore: must_call_super
  Future<void> onInit() async {}
  @override
  // The fake service owns no production subscriptions or sockets.
  // ignore: must_call_super
  Future<void> onClose() async {}
}

class _IdleSseClient extends ApiSseClient {
  _IdleSseClient()
    : super(
        url: Uri.parse('http://unused.test/stream'),
        onEvent: (_) {},
        onStateChanged: (_, _) {},
      );
  @override
  Future<void> connect() async {}
  @override
  Future<void> dispose() async {}
}

// Keep the real log controller and scroll ownership logic while removing SSE
// transport. The test does not contact the user's running OAS service.
class _LogController extends ScriptLogBrowserController {
  _LogController() : super(scriptName: 'tomoe');
  final ApiSseClient _idleClient = _IdleSseClient();
  @override
  ApiSseClient? get streamClient => _idleClient;
  @override
  set streamClient(ApiSseClient? value) {}
}

Widget _workbench(HomeDashboardController controller) => MaterialApp(
  home: Scaffold(
    body: Padding(
      padding: const EdgeInsets.all(12),
      child: HomeWorkbenchBody(
        controller: controller,
        collectionBuilder: (mode) => ConfigCollectionPanel(
          controller: controller,
          fillHeight: mode != HomeWorkbenchLayoutMode.singlePane,
          loadingAddScript: false,
          refreshingScripts: false,
          onAddScriptTap: () {},
          onRefreshScriptsTap: () {},
          onActivateScript: (_) async {},
          onTogglePower: (_, _) async {},
          onRenameScript: (_) async {},
          onExportScript: (_) async {},
          onDeleteScript: (_) async {},
        ),
        detailsBuilder: (mode, expand) => ActiveConfigPanel(
          key: const ValueKey('active-pane'),
          controller: controller,
          layoutMode: mode,
          onChangeTab: (tab) async =>
              controller.setActiveWorkbenchTabValue(tab),
          onOpenTask: (task, source) async =>
              controller.openTaskParameters(task, source: source),
          onTogglePower: (_, _) async {},
          onRenameScript: (_) async {},
          onDeleteScript: (_) async {},
          onSetNextRun: (_, _) async {},
          onQuickRun: (_) async {},
          onQuickWait: (_) async {},
          onBulkQuickRun: () async {},
          onBulkQuickWait: () async {},
          onExpandRightSidebar: expand,
        ),
        sidebar: WorkbenchSidebarPanel(
          key: const ValueKey('sidebar-pane'),
          controller: controller,
          scriptName: 'tomoe',
        ),
      ),
    ),
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory storageDirectory;
  setUpAll(() async {
    storageDirectory = Directory.systemTemp.createTempSync('oasx-resize-test-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => storageDirectory.path,
        );
    await GetStorage.init();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('dev.fluttercommunity.plus/connectivity'),
          (_) async => 'wifi',
        );
  });
  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('dev.fluttercommunity.plus/connectivity'),
          null,
        );
    try {
      storageDirectory.deleteSync(recursive: true);
    } on FileSystemException catch (error) {
      // GetStorage 2.x holds its RandomAccessFile until the test VM exits and
      // exposes no close API. Windows may keep this isolated temp file locked.
      if (error.osError?.errorCode != 32) rethrow;
    }
  });
  late HomeDashboardController controller;
  late _LogController logs;
  late ArgsController args;
  setUp(() {
    Get.testMode = true;
    Get.addTranslations(Messages().keys);
    Get.locale = const Locale('zh', 'CN');
    Get.put(WebSocketService());
    final scripts = Get.put<ScriptService>(_ScriptService());
    scripts.addScriptModel(
      ScriptModel('tomoe')..update(
        state: ScriptState.inactive,
        waitingTaskList: [
          TaskItemModel('tomoe', 'Duel', '2026-10-01 12:00:00'),
        ],
      ),
    );
    controller = Get.put(HomeDashboardController(storage: _MemoryStorage()));
    expect(controller.activeScriptName.value, 'tomoe');
    controller.showWorkspacePage();
    args = ArgsController();
    Get.put<ArgsController>(args);
    // Install an in-memory HTTP response adapter before statistics workers or
    // task catalog futures run. It keeps the real controllers and widgets.
    ApiClient();
    NetOptions.instance.dio.interceptors.clear();
    NetOptions.instance.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          final dynamic payload = options.path == '/script_menu'
              ? {
                  'tasks': ['Duel'],
                }
              : options.path.endsWith('/dates')
              ? {'dates': <String>[]}
              : options.path.endsWith('/args')
              ? {
                  'scheduler': [
                    {'name': 'enable', 'type': 'boolean', 'value': true},
                  ],
                }
              : <String, dynamic>{};
          handler.resolve(
            Response(requestOptions: options, statusCode: 200, data: payload),
          );
        },
      ),
    );
    Get.put(HomeStatisticsController());
    logs = _LogController()
      ..autoScroll.value = false
      ..reachedStart = true;
    logs.lines.assignAll(
      List.generate(
        60,
        (index) => ScriptLogLine(
          fileName: 'memory.log',
          lineNo: index + 1,
          offset: index * 30,
          byteLength: 30,
          text: 'INFO resize regression log line $index',
          lineTruncated: false,
        ),
      ),
    );
    Get.put<ScriptLogBrowserController>(logs, tag: 'tomoe', permanent: true);
  });
  tearDown(Get.reset);

  Future<void> resize(WidgetTester tester, double width, double height) async {
    await tester.binding.setSurfaceSize(Size(width, height));
    await tester.pump();
    // Include several intermediate animation frames while the tabs move
    // between the primary and sidebar panes, then reach the final layout.
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull, reason: 'resize $width x $height');
    await tester.pump(const Duration(milliseconds: 250));
    expect(tester.takeException(), isNull, reason: 'settled $width x $height');
    if (controller.activeTaskName.value.isNotEmpty) {
      // HTTP interception schedules fake-clock work; decoding uses a real
      // isolate. Alternate the clocks so neither blocks the other's progress.
      for (
        var attempt = 0;
        attempt < 40 && find.byType(Args).evaluate().isEmpty;
        attempt++
      ) {
        await tester.pump(const Duration(milliseconds: 20));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
      }
      await tester.pump();
      expect(tester.takeException(), isNull, reason: 'loaded $width x $height');
    }
  }

  testWidgets(
    'actual workbench restores all panes over repeated native-size breakpoints',
    (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.binding.setSurfaceSize(const Size(1500, 800));
      await tester.pumpWidget(_workbench(controller));
      await tester.pump(const Duration(milliseconds: 250));
      expect(tester.takeException(), isNull);

      for (final tab in [
        HomeWorkbenchTab.logs,
        HomeWorkbenchTab.stats,
        HomeWorkbenchTab.tasks,
      ]) {
        controller.setActiveWorkbenchTabValue(tab);
        if (tab == HomeWorkbenchTab.tasks) {
          controller.openTaskParameters(
            'Duel',
            source: HomeTaskParameterEntrySource.tasks,
          );
        }
        await tester.pump(const Duration(milliseconds: 250));
        for (var round = 0; round < 3; round++) {
          for (final size in const [
            Size(1500, 800),
            Size(900, 720),
            Size(500, 600),
            Size(900, 720),
            Size(1500, 800),
          ]) {
            await resize(tester, size.width, size.height);
            final expectedMode = size.width == 1500
                ? HomeWorkbenchLayoutMode.threePane
                : size.width == 900
                ? HomeWorkbenchLayoutMode.twoPane
                : HomeWorkbenchLayoutMode.singlePane;
            expect(controller.workbenchLayoutMode.value, expectedMode);
            switch (tab) {
              case HomeWorkbenchTab.logs:
                expect(find.byType(LogCenterPanel), findsOneWidget);
                expect(logs.viewportOwner, isNotNull);
                expect(logs.restoreScrollOffset, isNotNull);
              case HomeWorkbenchTab.stats:
                expect(find.byType(ScriptStatisticsPanel), findsOneWidget);
              case HomeWorkbenchTab.tasks:
                expect(controller.activeTaskName.value, 'Duel');
                expect(find.byType(TaskParameterPanel), findsOneWidget);
                expect(find.byType(Args), findsOneWidget);
                expect(args.groupsName.value, ['scheduler']);
              default:
                fail('Uncovered tab $tab');
            }
            final pane = find.byType(ActiveConfigPanel);
            expect(pane, findsOneWidget);
            final rect = tester.getRect(pane);
            expect(rect.right, lessThanOrEqualTo(size.width));
            expect(rect.bottom, lessThanOrEqualTo(size.height));
            expect(rect.height, closeTo(size.height - 24, 0.01));
            expect(
              find.byType(WorkbenchSidebarPanel),
              expectedMode == HomeWorkbenchLayoutMode.threePane
                  ? findsOneWidget
                  : findsNothing,
            );
            if (expectedMode == HomeWorkbenchLayoutMode.threePane) {
              final right = tester.getRect(find.byType(WorkbenchSidebarPanel));
              expect(right.height, closeTo(size.height - 24, 0.01));
              expect(right.left, greaterThan(rect.right));
              expect(right.right, lessThanOrEqualTo(size.width - 12));
            }
          }
        }
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  testWidgets(
    'removed divider cannot preserve a stale live split after resizing',
    (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.binding.setSurfaceSize(const Size(1500, 800));
      await tester.pumpWidget(_workbench(controller));
      await tester.pump();
      final originalDetails = tester
          .getSize(find.byType(ActiveConfigPanel))
          .width;
      final divider = find.byKey(
        const ValueKey('home-workbench-right-divider'),
      );
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.down(tester.getCenter(divider));
      await gesture.moveBy(const Offset(100, 0));
      await tester.pump();
      expect(
        tester.getSize(find.byType(ActiveConfigPanel)).width,
        greaterThan(originalDetails + 50),
      );
      await resize(tester, 900, 720);
      // The right divider and its recognizer are now unmounted by the external
      // resize. A later pointer cancel cannot deliver its normal drag-end event.
      await gesture.cancel();
      await resize(tester, 500, 600);
      await resize(tester, 1500, 800);
      expect(controller.workbenchSplitRatio.value, 0.5);
      expect(
        tester.getSize(find.byType(ActiveConfigPanel)).width,
        closeTo(originalDetails, 0.01),
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  testWidgets('removed left divider discards its unfinished collection width', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(1500, 800));
    await tester.pumpWidget(_workbench(controller));
    await tester.pump(const Duration(milliseconds: 250));
    final original = tester.getSize(find.byType(ConfigCollectionPanel)).width;
    final divider = find.byKey(const ValueKey('home-workbench-left-divider'));
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.down(tester.getCenter(divider));
    await gesture.moveBy(const Offset(70, 0));
    await tester.pump();
    expect(
      tester.getSize(find.byType(ConfigCollectionPanel)).width,
      greaterThan(original + 40),
    );
    await resize(tester, 500, 600);
    await gesture.cancel();
    await resize(tester, 900, 720);
    await resize(tester, 1500, 800);
    expect(controller.workbenchCollectionWidth.value, original);
    expect(
      tester.getSize(find.byType(ConfigCollectionPanel)).width,
      closeTo(original, 0.01),
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets(
    'native resize invalidates a divider gesture still receiving events',
    (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.binding.setSurfaceSize(const Size(1500, 800));
      await tester.pumpWidget(_workbench(controller));
      await tester.pump(const Duration(milliseconds: 250));
      final original = tester.getSize(find.byType(ActiveConfigPanel)).width;
      final divider = find.byKey(
        const ValueKey('home-workbench-right-divider'),
      );
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.down(tester.getCenter(divider));
      await gesture.moveBy(const Offset(70, 0));
      await tester.pump();
      expect(
        tester.getSize(find.byType(ActiveConfigPanel)).width,
        greaterThan(original + 40),
      );
      // A height-only native resize leaves this recognizer mounted. Subsequent
      // events from the old gesture must not write a preview for old geometry.
      await resize(tester, 1500, 650);
      await gesture.moveBy(const Offset(30, 0));
      await gesture.up();
      await tester.pump();
      expect(controller.workbenchSplitRatio.value, 0.5);
      expect(
        tester.getSize(find.byType(ActiveConfigPanel)).width,
        closeTo(original, 0.01),
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  testWidgets('completed divider drags still persist user dimensions', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(1500, 800));
    await tester.pumpWidget(_workbench(controller));
    await tester.pump(const Duration(milliseconds: 250));
    final left = find.byKey(const ValueKey('home-workbench-left-divider'));
    await tester.drag(left, const Offset(60, 0));
    await tester.pump();
    final width = tester.getSize(find.byType(ConfigCollectionPanel)).width;
    expect(controller.workbenchCollectionWidth.value, closeTo(width, 0.01));
    final right = find.byKey(const ValueKey('home-workbench-right-divider'));
    await tester.drag(right, const Offset(60, 0));
    await tester.pump();
    final detailsWidth = tester.getSize(find.byType(ActiveConfigPanel)).width;
    expect(controller.workbenchSplitRatio.value, greaterThan(0.5));
    await resize(tester, 500, 600);
    await resize(tester, 900, 720);
    await resize(tester, 1500, 800);
    expect(
      tester.getSize(find.byType(ConfigCollectionPanel)).width,
      closeTo(width, 0.01),
    );
    expect(
      tester.getSize(find.byType(ActiveConfigPanel)).width,
      closeTo(detailsWidth, 0.01),
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}
