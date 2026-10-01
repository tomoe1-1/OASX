import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oasx/modules/common/widgets/windows_caption_bar.dart';
import 'package:window_manager/window_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('window_manager');
  final calls = <String>[];
  var isMaximized = false;
  var isMinimized = false;

  setUp(() {
    calls.clear();
    isMaximized = false;
    isMinimized = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          return switch (call.method) {
            'isMaximized' => isMaximized,
            'isMinimized' => isMinimized,
            'isFullScreen' => false,
            _ => null,
          };
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  Future<void> showCaption(
    WidgetTester tester, {
    double width = 900,
    Brightness brightness = Brightness.light,
    VoidCallback? onMenu,
    List<Widget> actions = const [],
  }) async {
    tester.view.physicalSize = Size(width, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          brightness: brightness,
          splashFactory: InkRipple.splashFactory,
        ),
        home: Scaffold(
          appBar: WindowsCaptionBar(
            brightness: brightness,
            routePath: '/home',
            onMenuPressed: onMenu,
            trailingActions: actions,
          ),
          body: const SizedBox(key: ValueKey('page-body')),
        ),
      ),
    );
    await tester.pump();
  }

  Finder captionTitle() => find.byWidgetPredicate(
    (widget) =>
        widget is Text &&
        (widget.textSpan?.toPlainText().startsWith('OASX') ?? false),
  );

  for (final brightness in Brightness.values) {
    testWidgets('caption contrast preserves the $brightness page theme', (
      tester,
    ) async {
      await showCaption(tester, brightness: brightness);
      final title = captionTitle();
      expect(title, findsOneWidget);
      final captionTheme = Theme.of(tester.element(title));
      expect(captionTheme.brightness, Brightness.light);
      expect(
        captionTheme.colorScheme.primary.computeLuminance(),
        lessThan(.10),
      );
      expect(
        captionTheme.iconButtonTheme.style?.foregroundColor
            ?.resolve({})
            ?.computeLuminance(),
        lessThan(.10),
      );
      expect(
        Theme.of(
          tester.element(find.byKey(const ValueKey('page-body'))),
        ).brightness,
        brightness,
      );
      for (final button in tester.widgetList<WindowCaptionButton>(
        find.byType(WindowCaptionButton),
      )) {
        expect(button.brightness, Brightness.light);
      }
      expect(tester.getSize(find.byType(WindowsCaptionBar)).height, 50);
      expect(find.byType(Image), findsOneWidget);
      final frame = tester.widget<Container>(
        find
            .descendant(
              of: find.byType(WindowsCaptionBar),
              matching: find.byWidgetPredicate(
                (widget) =>
                    widget is Container &&
                    widget.decoration is BoxDecoration &&
                    (widget.decoration! as BoxDecoration).borderRadius != null,
              ),
            )
            .first,
      );
      final decoration = frame.decoration! as BoxDecoration;
      expect(decoration.color?.a, inInclusiveRange(.25, .35));
      expect(decoration.gradient, isNull);
      expect(frame.clipBehavior, Clip.antiAlias);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'menu, settings and all three window buttons keep their actions',
    (tester) async {
      var menuPressed = false;
      var settingsPressed = false;
      await showCaption(
        tester,
        onMenu: () => menuPressed = true,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => settingsPressed = true,
          ),
        ],
      );
      await tester.tap(find.byIcon(Icons.menu));
      await tester.tap(find.byIcon(Icons.settings));
      expect(menuPressed, isTrue);
      expect(settingsPressed, isTrue);
      calls.clear();
      for (var i = 0; i < 3; i++) {
        await tester.tap(find.byType(WindowCaptionButton).at(i));
        await tester.pump();
      }
      expect(calls, ['isMinimized', 'minimize', 'maximize', 'close']);
    },
  );

  testWidgets('maximized state retains the restore button', (tester) async {
    isMaximized = true;
    await showCaption(tester);
    calls.clear();
    await tester.tap(find.byType(WindowCaptionButton).at(1));
    await tester.pump();
    expect(calls, ['unmaximize']);
  });

  testWidgets('dragging the caption still delegates window movement', (
    tester,
  ) async {
    await showCaption(tester);
    calls.clear();
    await tester.drag(find.byType(DragToMoveArea), const Offset(40, 0));
    await tester.pump(const Duration(milliseconds: 350));
    expect(calls, contains('startDragging'));
  });

  testWidgets('narrow window retains avatar, menu and caption controls', (
    tester,
  ) async {
    await showCaption(
      tester,
      width: 260,
      onMenu: () {},
      actions: [IconButton(icon: const Icon(Icons.settings), onPressed: () {})],
    );
    expect(find.byIcon(Icons.settings), findsNothing);
    expect(find.byIcon(Icons.menu), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
    expect(find.byType(WindowCaptionButton), findsNWidgets(3));
    expect(find.byType(DragToMoveArea), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
