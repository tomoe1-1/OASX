import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:oasx/modules/server/widgets/deploy_import_dialog.dart';
import 'package:oasx/modules/server/widgets/deploy_yaml_editor.dart';
import 'package:oasx/translation/i18n.dart';

void main() {
  testWidgets('deploy yaml editor avoids overflow on narrow width', (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DeployYamlEditor(
            content: _sampleYaml,
            maxHeight: 600,
            onSave: (_) {},
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(tester.takeException(), isNull);
    expect(find.text('Git'), findsOneWidget);
    expect(find.text('Repository'), findsOneWidget);
  });

  testWidgets('deploy yaml editor stacks fields on very narrow width',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(240, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DeployYamlEditor(
            content: _sampleYaml,
            maxHeight: 600,
            onSave: (_) {},
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(tester.takeException(), isNull);
    final repositoryTop = tester.getTopLeft(find.text('Repository')).dy;
    final repositoryFieldTop =
        tester.getTopLeft(_textFieldForValue(_repositoryValue)).dy;
    expect(repositoryFieldTop, greaterThan(repositoryTop));
    final autoUpdateLeft = tester.getTopLeft(find.text('AutoUpdate')).dx;
    final switchLeft = tester.getTopLeft(find.byType(Switch)).dx;
    expect(switchLeft, closeTo(autoUpdateLeft, 8));
  });

  testWidgets('deploy yaml editor keeps short values compact on wide width',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DeployYamlEditor(
            content: _sampleYaml,
            maxHeight: 600,
            onSave: (_) {},
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(tester.takeException(), isNull);
    final branchField = _textFieldForValue('mine');
    expect(tester.getSize(branchField).width, lessThan(260));
    expect(find.text('Repository'), findsOneWidget);
  });

  testWidgets('deploy yaml help popup stays visible until outside tap',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DeployYamlEditor(
            content: _sampleYaml,
            maxHeight: 600,
            onSave: (_) {},
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.byIcon(Icons.help_outline).first);
    await tester.pump();

    expect(find.byType(SelectableText), findsOneWidget);
    expect(find.text('URL of AzurLaneAutoScript repository'), findsOneWidget);

    await tester.tapAt(const Offset(10, 10));
    await tester.pump();

    expect(find.text('URL of AzurLaneAutoScript repository'), findsNothing);
  });

  testWidgets('deploy import dialog shows file drop area', (tester) async {
    addTearDown(Get.reset);

    await tester.pumpWidget(
      GetMaterialApp(
        translations: Messages(),
        locale: const Locale('zh', 'CN'),
        home: const Scaffold(body: DeployImportDialog()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('导入部署文件'), findsOneWidget);
    expect(find.text('点击选择或拖拽 YAML 文件到这里'), findsOneWidget);
  });
}

Finder _textFieldForValue(String value) {
  return find.byWidgetPredicate(
    (widget) {
      return widget is TextField && widget.controller?.text == value;
    },
  );
}

const _sampleYaml = '''
Deploy:
  Git:
    # URL of AzurLaneAutoScript repository
    Repository: $_repositoryValue
    # Branch of Alas
    Branch: mine
    AutoUpdate: false
''';

const _repositoryValue = 'https://github.com/AzurTian/OnmyojiAutoScript.git';
