import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:oasx/api/sse_client.dart';
import 'package:oasx/modules/home/widgets/log_center_panel.dart';
import 'package:oasx/modules/log/log_browser_models.dart';
import 'package:oasx/modules/log/script_log_browser_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final clipboardCalls = <MethodCall>[];

  setUp(() {
    clipboardCalls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          clipboardCalls.add(call);
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
    Get.reset();
  });

  Future<void> pumpShell(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(
      GetMaterialApp(
        home: Scaffold(body: child),
        translations: _TestTranslations(),
        locale: const Locale('zh', 'CN'),
      ),
    );
    await tester.pump();
  }

  List<MethodCall> clipboardOnly() {
    return clipboardCalls
        .where((call) => call.method == 'Clipboard.setData')
        .toList();
  }

  testWidgets('copyCurrentView copies info logs with preserved line breaks',
      (tester) async {
    await pumpShell(tester, Container());
    final controller = ScriptLogBrowserController(scriptName: 'demo');
    controller.lines.addAll(const [
      ScriptLogLine(
        fileName: 'demo.log',
        lineNo: 1,
        offset: 0,
        byteLength: 6,
        text: 'line-1',
        lineTruncated: false,
      ),
      ScriptLogLine(
        fileName: 'demo.log',
        lineNo: 2,
        offset: 6,
        byteLength: 0,
        text: '',
        lineTruncated: false,
      ),
      ScriptLogLine(
        fileName: 'demo.log',
        lineNo: 3,
        offset: 6,
        byteLength: 6,
        text: 'line-2',
        lineTruncated: false,
      ),
    ]);

    controller.copyCurrentView();
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));

    final calls = clipboardOnly();
    expect(calls, hasLength(1));
    expect(calls.single.arguments['text'], 'line-1\n\nline-2');
  });

  testWidgets('copyCurrentView copies prepared error logs with line breaks',
      (tester) async {
    await pumpShell(tester, Container());
    final controller = ScriptLogBrowserController(scriptName: 'demo');
    controller.activeTab.value = ScriptLogBrowserTab.error;
    controller.errorDetailVisible.value = true;
    controller.selectedErrorLogLines.assignAll(const ['A', '', 'B']);

    controller.copyCurrentView();
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));

    final calls = clipboardOnly();
    expect(calls, hasLength(1));
    expect(calls.single.arguments['text'], 'A\n\nB');
  });

  testWidgets('long press opens copy dialog for info logs', (tester) async {
    final controller = Get.put(
      ScriptLogBrowserController(scriptName: 'demo'),
      tag: 'demo',
      permanent: true,
    );
    controller.lines.addAll(const [
      ScriptLogLine(
        fileName: 'demo.log',
        lineNo: 1,
        offset: 0,
        byteLength: 5,
        text: 'alpha',
        lineTruncated: false,
      ),
      ScriptLogLine(
        fileName: 'demo.log',
        lineNo: 2,
        offset: 5,
        byteLength: 4,
        text: 'beta',
        lineTruncated: false,
      ),
    ]);
    controller.streamClient = ApiSseClient(
      url: Uri.parse('http://127.0.0.1'),
      onEvent: (_) {},
      onStateChanged: (_, __) {},
    );

    await pumpShell(tester, const LogCenterPanel(scriptName: 'demo'));
    await tester.pumpAndSettle();
    await tester.longPress(find.byType(ListView));
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsOneWidget);
    expect(find.byType(SelectableText), findsOneWidget);
    expect(find.text('alpha\nbeta'), findsOneWidget);
    expect(find.text('复制'), findsWidgets);
  });
}

class _TestTranslations extends Translations {
  @override
  Map<String, Map<String, String>> get keys => {
        'zh_CN': {
          'Tip': 'Tip',
          'Copy success': 'Copy success',
          'Cancel': '取消',
          'Copy': '复制',
          'home_log_info_tab': '信息',
          'home_log_error_tab': '错误',
          'home_log_auto_scroll': '自动滚动',
          'home_log_wrap_lines': '自动换行',
          'Clear Log': '清空日志',
          'home_no_script_selected': '请先选择一个配置',
          'home_no_log': '暂无日志',
        },
      };
}
