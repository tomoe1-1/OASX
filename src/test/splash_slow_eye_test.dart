import 'package:oasx/utils/eye_motion.dart';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oasx/modules/boot/splash_painter.dart';
import 'package:oasx/modules/boot/splash_palette.dart';
import 'package:oasx/modules/boot/splash_screen.dart';
import 'package:oasx/modules/boot/splash_task.dart';

class FinishedTask implements SplashTask {
  FinishedTask({this.hasFailed = false});
  @override
  final bool hasFailed;
  @override
  List<SplashStage> get stages => const [];
  @override
  double get overallProgress => 1;
  @override
  bool get isFinished => true;
  @override
  bool get canSkip => true;
  @override
  Stream<void> get changes => const Stream.empty();
  @override
  void dispose() {}
}

SplashPainter painter(
  double eye, {
  bool reduce = false,
  ui.Image? closed,
  ui.Image? open,
  ui.Image? closedWire,
  ui.Image? openWire,
  List<ui.Image?> eyeFrames = const [],
  EyeMotion? motion,
}) => SplashPainter(
  progress: 1,
  eyeProgress: eye,
  palette: SplashPalette.deepSpace,
  stars: const [],
  starTime: 0,
  titleText: 'OASX',
  dateText: '2026 年 10 月 7 日',
  mottoText: '',
  reduceMotion: reduce,
  textScaler: TextScaler.noScaling,
  artClosed: closed,
  artOpen: open,
  artClosedWire: closedWire,
  artOpenWire: openWire,
  artEyeFrames: eyeFrames,
  eyeMotion: motion,
);
void main() {
  test(
    'eye lift lasts 3.6 seconds and is independent of deployment progress',
    () {
      expect(
        SplashPainter.totalDuration.inMilliseconds * (0.94 - 0.54),
        closeTo(3600, 0.01),
      );
      expect(painter(0.54).eyeOpening, 0);
      expect(painter(0.74).eyeOpening, closeTo(0.5, 0.001));
      expect(painter(0.94).eyeOpening, 1);
      expect(painter(0, reduce: true).eyeOpening, 1);
      expect(painter(0.5).shouldRepaint(painter(0.4)), isTrue);
    },
  );
  testWidgets(
    'instant successful task waits for eyes and still allows skipping',
    (tester) async {
      var done = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: SplashScreen(task: FinishedTask(), onFinished: () => done++),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 5));
      expect(done, 0);
      final paint =
          tester.widget<CustomPaint>(find.byType(CustomPaint).last).painter
              as SplashPainter;
      expect(paint.eyeOpening, lessThan(1));
      await tester.tap(find.byType(SplashScreen));
      await tester.pump();
      expect(done, 1);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 5));
      expect(done, 1);
    },
  );
  testWidgets('successful task finishes once after timed eye lift', (
    tester,
  ) async {
    var done = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: SplashScreen(task: FinishedTask(), onFinished: () => done++),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 9));
    expect(done, 0);
    await tester.pump(const Duration(milliseconds: 500));
    expect(done, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('failed task preserves prompt exit', (tester) async {
    var done = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: SplashScreen(
          task: FinishedTask(hasFailed: true),
          onFinished: () => done++,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(done, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
    'actual startup art renders closed half and open at varied sizes',
    (tester) async {
      await tester.runAsync(() async {
        Future<ui.Image> decode(String path) async {
          final codec = await ui.instantiateImageCodec(
            File(path).readAsBytesSync(),
          );
          try {
            return (await codec.getNextFrame()).image;
          } finally {
            codec.dispose();
          }
        }

        final closed = await decode('assets/splash/girl_closed.jpg');
        final open = await decode('assets/splash/girl_open.jpg');
        final closedWire = await decode(SplashArt.closedWire);
        final openWire = await decode(SplashArt.openWire);
        final eyeFrames = await Future.wait(
          [
            'assets/splash/girl_eye_quarter.png',
            'assets/splash/girl_eye_half.png',
            'assets/splash/girl_eye_three_quarter.png',
          ].map(decode),
        );
        final motion = await EyeMotion.prepareSplash([
          closed,
          ...eyeFrames,
          open,
        ]);
        try {
          for (final pair in [
            (0.54, 'closed'),
            (0.698740105, 'quarter'),
            (0.72, 'transition'),
            (0.74, 'half'),
            (0.781259895, 'three-quarter'),
            (0.94, 'open'),
          ]) {
            final record = ui.PictureRecorder();
            painter(
              pair.$1,
              closed: closed,
              open: open,
              closedWire: closedWire,
              openWire: openWire,
              eyeFrames: eyeFrames,
              motion: motion,
            ).paint(Canvas(record), const Size(1200, 800));
            final picture = record.endRecording();
            final image = await picture.toImage(1200, 800);
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            File(
              'splash-${pair.$2}.png',
            ).writeAsBytesSync(bytes!.buffer.asUint8List());
            image.dispose();
            picture.dispose();
          }
          for (final size in [const Size(800, 1200), const Size(2560, 800)]) {
            final record = ui.PictureRecorder();
            painter(
              0.74,
              closed: closed,
              open: open,
              closedWire: closedWire,
              openWire: openWire,
              eyeFrames: eyeFrames,
              motion: motion,
            ).paint(Canvas(record), size);
            record.endRecording().dispose();
          }
        } finally {
          motion.dispose();
          closed.dispose();
          open.dispose();
          closedWire.dispose();
          openWire.dispose();
          for (final image in eyeFrames) {
            image.dispose();
          }
        }
      });
      expect(tester.takeException(), isNull);
    },
  );
}
