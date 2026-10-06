import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oasx/modules/home/widgets/home_backdrop.dart';

void main() {
  test('slow wake timeline is continuous and has a long open hold', () {
    expect(backdropEyeOpening(0), 0);
    expect(backdropEyeOpening(0.7), 0);
    expect(backdropEyeOpening(2.5), closeTo(0.5, 0.03));
    expect(backdropEyeOpening(4.3), 1);
    expect(backdropEyeOpening(16.8), 1);
    expect(backdropEyeOpening(18), 0);
    for (var i = 1; i <= 1800; i++) {
      final previous = backdropEyeOpening((i - 1) / 100);
      final next = backdropEyeOpening(i / 100);
      expect((next - previous).abs(), lessThan(0.03));
    }
  });
  testWidgets(
    'actual eye assets render closed partial open and reduced motion',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1672, 941);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMessageHandler('flutter/assets', (message) async {
            final asset = String.fromCharCodes(message!.buffer.asUint8List());
            final file = File(asset);
            if (!file.existsSync()) return null;
            final bytes = file.readAsBytesSync();
            return ByteData.sublistView(bytes);
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMessageHandler('flutter/assets', null),
      );
      final key = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          home: RepaintBoundary(key: key, child: const HomeBackdrop()),
        ),
      );
      for (var i = 0; i < 30; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 200)),
        );
        await tester.pump();
        final painter =
            tester.widget<CustomPaint>(find.byType(CustomPaint).last).painter
                as dynamic;
        if (painter.eyeMotion?.frameCount == 5) break;
      }
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final paint =
          tester.widget<CustomPaint>(find.byType(CustomPaint).last).painter
              as dynamic;
      expect(paint.eyeMotion.frameCount, 5);
      Future<void> capture(String name) async {
        await tester.runAsync(() async {
          final image = await boundary.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          File('../$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }

      await capture('closed');
      await tester.pump(const Duration(milliseconds: 2500));
      await capture('half');
      var previousOpening = paint.eyeOpening as double;
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(microseconds: 16667));
        final nextPainter =
            tester.widget<CustomPaint>(find.byType(CustomPaint).last).painter
                as dynamic;
        expect(
          identical(nextPainter, paint),
          isTrue,
          reason: 'motion repaints without rebuilding the widget',
        );
        final nextOpening = nextPainter.eyeOpening as double;
        expect(
          nextOpening,
          greaterThan(previousOpening),
          reason: 'every display frame must advance the eyelid',
        );
        previousOpening = nextOpening;
      }
      await tester.pump(const Duration(milliseconds: 2200));
      await capture('open');
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: RepaintBoundary(key: key, child: const HomeBackdrop()),
          ),
        ),
      );
      for (var i = 0; i < 3; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 200)),
        );
        await tester.pump();
      }
      final state = tester.state(find.byType(HomeBackdrop)) as dynamic;
      expect(state.isAnimated, false);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);
    },
  );
}
