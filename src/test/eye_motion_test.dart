import 'package:oasx/utils/eye_motion.dart';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('render actual eye landmarks for motion review', (tester) async {
    await tester.runAsync(() async {
      for (final (prefix, closed, open, logical, patches) in [
        (
          'home',
          'assets/images/main_bg_muse_front_closed.png',
          'assets/images/main_bg_muse_front_full.png',
          const Size(1672, 941),
          [
            const Rect.fromLTWH(1040, 340, 112, 82),
            const Rect.fromLTWH(1200, 305, 112, 90),
          ],
        ),
        (
          'splash',
          'assets/splash/girl_closed.jpg',
          'assets/splash/girl_open.jpg',
          const Size(1200, 800),
          [const Rect.fromLTWH(674, 245, 104, 98)],
        ),
      ]) {
        final paths = [
          closed,
          for (final name in ['quarter', 'half', 'three_quarter'])
            prefix == 'home'
                ? 'assets/images/main_bg_muse_front_eye_$name.png'
                : 'assets/splash/girl_eye_$name.png',
          open,
        ];
        final images = <ui.Image>[];
        for (final path in paths) {
          final codec = await ui.instantiateImageCodec(
            File(path).readAsBytesSync(),
          );
          try {
            images.add((await codec.getNextFrame()).image);
          } finally {
            codec.dispose();
          }
        }
        final motion = prefix == 'home'
            ? await EyeMotion.prepareHome(images)
            : await EyeMotion.prepareSplash(images);
        try {
          final record = ui.PictureRecorder();
          final canvas = Canvas(record);
          final atlas = motion.atlas;
          var previous = motion.lids
              .map((l) => motion.lidHeight(l, 0))
              .toList();
          for (var i = 1; i <= 240; i++) {
            final p = i / 240;
            for (var j = 0; j < motion.lids.length; j++) {
              final next = motion.lidHeight(motion.lids[j], p);
              expect(
                next,
                lessThan(previous[j]),
                reason: 'no stationary segment between poses',
              );
              expect((next - previous[j]).abs(), lessThan(0.4));
              previous[j] = next;
            }
            canvas.save();
            canvas.translate(
              (i - 1) % 12 * atlas.width,
              ((i - 1) ~/ 12) * atlas.height,
            );
            canvas.clipRect(Rect.fromLTWH(0, 0, atlas.width, atlas.height));
            canvas.translate(-atlas.left, -atlas.top);
            motion.paint(canvas, p);
            canvas.restore();
          }
          final picture = record.endRecording();
          final contact = await picture.toImage(
            (atlas.width * 12).ceil(),
            (atlas.height * 20).ceil(),
          );
          final contactBytes = await contact.toByteData(
            format: ui.ImageByteFormat.png,
          );
          File(
            'eye-continuity-$prefix.png',
          ).writeAsBytesSync(contactBytes!.buffer.asUint8List());
          contact.dispose();
          picture.dispose();
          expect(motion.frameCount, prefix == 'home' ? 5 : 4);
          for (final stop
              in motion.stops.skip(1).take(motion.stops.length - 2)) {
            for (final lid in motion.lids) {
              const epsilon = 0.00001;
              final at = motion.lidHeight(lid, stop);
              final before =
                  (at - motion.lidHeight(lid, stop - epsilon)) / epsilon;
              final after =
                  (motion.lidHeight(lid, stop + epsilon) - at) / epsilon;
              expect(
                (before - after).abs(),
                lessThan(0.05),
                reason: 'pose boundary must not change lid speed abruptly',
              );
            }
          }
          expect(
            atlas.width * atlas.height * motion.frameCount,
            lessThan(200000),
          );
          for (var j = 0; j < patches.length; j++) {
            final patch = patches[j];
            final recorder = ui.PictureRecorder();
            final canvas = Canvas(recorder);
            for (var i = 0; i < images.length; i++) {
              final image = images[i];
              final src = Rect.fromLTWH(
                patch.left * image.width / logical.width,
                patch.top * image.height / logical.height,
                patch.width * image.width / logical.width,
                patch.height * image.height / logical.height,
              );
              canvas.drawImageRect(
                image,
                src,
                Rect.fromLTWH(
                  i * patch.width * 4,
                  0,
                  patch.width * 4,
                  patch.height * 4,
                ),
                Paint()..filterQuality = FilterQuality.high,
              );
            }
            final pic = recorder.endRecording();
            final result = await pic.toImage(
              (patch.width * 20).round(),
              (patch.height * 4).round(),
            );
            final bytes = await result.toByteData(
              format: ui.ImageByteFormat.png,
            );
            File(
              'eye-landmarks-$prefix-$j.png',
            ).writeAsBytesSync(bytes!.buffer.asUint8List());
            result.dispose();
            pic.dispose();
          }
        } finally {
          motion.dispose();
          for (final image in images) {
            image.dispose();
          }
        }
      }
    });
  });
  testWidgets('real shader alpha blends and pose boundaries have no jumps', (
    tester,
  ) async {
    await tester.runAsync(() async {
      Future<ui.Image> solid(Color color) async {
        final recorder = ui.PictureRecorder();
        Canvas(recorder).drawColor(color, BlendMode.src);
        final picture = recorder.endRecording();
        try {
          return await picture.toImage(1200, 800);
        } finally {
          picture.dispose();
        }
      }

      final red = await solid(const Color(0xFFFF0000));
      final blue = await solid(const Color(0xFF0000FF));
      final motion = await EyeMotion.prepareSplash([
        red,
        blue,
        blue,
        red,
        blue,
      ]);
      Future<List<int>> sample(double p) async {
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder)
          ..translate(-motion.atlas.left, -motion.atlas.top);
        motion.paint(canvas, p);
        final picture = recorder.endRecording();
        final image = await picture.toImage(104, 98);
        try {
          final data = await image.toByteData();
          final bytes = data!.buffer.asUint8List();
          const at = (49 * 104 + 52) * 4;
          return bytes.sublist(at, at + 4);
        } finally {
          image.dispose();
          picture.dispose();
        }
      }

      try {
        final mixed = await sample(0.10);
        expect(mixed[0], inInclusiveRange(126, 129));
        expect(mixed[1], 0);
        expect(mixed[2], inInclusiveRange(126, 129));
        expect(mixed[3], 255);
        for (final stop in motion.stops.skip(1).take(motion.stops.length - 2)) {
          final before = await sample(stop - 0.00001);
          final after = await sample(stop + 0.00001);
          for (var i = 0; i < 4; i++) {
            expect((before[i] - after[i]).abs(), lessThanOrEqualTo(1));
          }
        }
      } finally {
        motion.dispose();
        red.dispose();
        blue.dispose();
      }
    });
  });
}
