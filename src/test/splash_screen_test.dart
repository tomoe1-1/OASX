import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oasx/config/theme.dart';
import 'package:oasx/modules/boot/splash_decor.dart';
import 'package:oasx/modules/boot/splash_geometry.dart';
import 'package:oasx/modules/boot/splash_motto.dart';
import 'package:oasx/modules/boot/splash_painter.dart';
import 'package:oasx/modules/boot/splash_palette.dart';
import 'package:oasx/modules/boot/splash_screen.dart';

void main() {
  group('SplashPalette', () {
    test('默认深空配色是蓝青色相', () {
      final hsl = HSLColor.fromColor(SplashPalette.deepSpace.wire);
      expect(hsl.hue, greaterThan(190));
      expect(hsl.hue, lessThan(240));
    });

    test('按种子推导时保留色相偏移', () {
      final pink = SplashPalette.fromSeed(const Color(0xFFE91E63));
      final hsl = HSLColor.fromColor(pink.wire);
      // 樱粉种子约 340°，推导出的线框色相应落在附近
      expect(hsl.hue, greaterThan(300));
      expect(hsl.hue, lessThan(360));
    });

    test('任意种子都能生成高对比文字色', () {
      for (final seed in ColorSeed.values) {
        final p = SplashPalette.fromSeed(seed.color);
        final textL = HSLColor.fromColor(p.text).lightness;
        final backdropL = HSLColor.fromColor(p.backdropBottom).lightness;
        expect(textL - backdropL, greaterThan(0.5),
            reason: '${seed.labelZh} 的文字与底色对比不足');
      }
    });
  });

  group('WireGeometry', () {
    const size = Size(1200, 800);

    test('归一化坐标映射到画布中心', () {
      final g = WireGeometry(size);
      expect(g.p(0.5, 0.5).dx, closeTo(600, 0.001));
      expect(g.p(0.5, 0.5).dy, closeTo(400, 0.001));
    });

    test('短边为基准做等比缩放', () {
      final g = WireGeometry(size);
      // 短边 800，归一化半径 0.5 → 画布 400
      expect(g.r(0.5), closeTo(400, 0.001));
    });

    test('刻度数量与常量一致', () {
      final g = WireGeometry(size);
      expect(WireGeometry.ticks(g).length, WireGeometry.tickCount);
      expect(WireGeometry.fineTicks(g).length, WireGeometry.fineTickCount);
    });

    test('刻度起点比终点更靠近圆心', () {
      final g = WireGeometry(size);
      for (final (a, b) in WireGeometry.ticks(g)) {
        final da = (a - g.center).distance;
        final db = (b - g.center).distance;
        expect(da, lessThan(db));
      }
    });
    test('鸟居轮廓在画布内且高度合理', () {
      final bars = WireGeometry.toriiBars();
      expect(bars.length, 6);
      for (final bar in bars) {
        for (final p in bar) {
          expect(p.dx, inInclusiveRange(0.30, 0.70));
          expect(p.dy, inInclusiveRange(0.28, 0.55));
        }
      }
    });

    test('齿轮是闭合多边形且顶点数正确', () {
      final main = WireGeometry.mainGear();
      // 12 齿 × 每齿 4 顶点
      expect(main.length, 48);
      final subA = WireGeometry.subGearA();
      expect(subA.length, 9 * 4);
    });

    test('齿轮齿顶比齿根离中心更远', () {
      final pts = WireGeometry.mainGear();
      var maxR = 0.0, minR = double.infinity;
      for (final p in pts) {
        final d = (p - const Offset(0.5, 0.5)).distance;
        maxR = d > maxR ? d : maxR;
        minR = d < minR ? d : minR;
      }
      expect(maxR, closeTo(0.078, 0.006));
      expect(minR, closeTo(0.060, 0.006));
    });

    test('侧翼斜撑左右对称', () {
      final wings = WireGeometry.wings();
      expect(wings.length, 6);
      for (var i = 0; i < 3; i++) {
        final left = wings[i].$1;
        final right = wings[i + 3].$1;
        expect(left.dx + right.dx, closeTo(1.0, 0.001));
      }
    });
  });

  group('SplashPainter', () {
    Widget host(CustomPainter p, {double scale = 1.0}) => MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: CustomPaint(painter: p, size: const Size(900, 640)),
          ),
        );

    SplashPainter make({
      double progress = 0.5,
      double starTime = 1.2,
      bool reduceMotion = false,
      double scale = 1.0,
      String? motto,
    }) =>
        SplashPainter(
          progress: progress,
          palette: SplashPalette.deepSpace,
          stars: const <Star>[],
          starTime: starTime,
          titleText: 'OASX',
          dateText: '2026 年 9 月 29 日 · 周二',
          // 默认取最长的一句，把「文字会不会戳出左栏」这件事
          // 在常规用例里就压到；显式覆盖时才用别的。
          mottoText: motto ?? kSplashMottos.reduce(
            (a, b) => a.length >= b.length ? a : b,
          ),
          reduceMotion: reduceMotion,
          textScaler: TextScaler.linear(scale),
          // 测试不加载立绘资源 → 走几何线框兜底分支，
          // 保证绘制逻辑在资源缺失时也不崩。
          artClosed: null,
          artOpen: null,
          artClosedWire: null,
          artOpenWire: null,
        );

    testWidgets('各进度节点都能绘制不抛异常', (tester) async {
      for (final p in <double>[0.0, 0.1, 0.25, 0.4, 0.55, 0.7, 0.85, 1.0]) {
        await tester.pumpWidget(host(make(progress: p)));
        expect(tester.takeException(), isNull, reason: 'progress=$p 绘制失败');
      }
    });

    testWidgets('减少动态效果时不因动画状态抛错', (tester) async {
      await tester.pumpWidget(host(make(progress: 0.0, reduceMotion: true)));
      expect(tester.takeException(), isNull);
    });

    testWidgets('文字放大 1.6 倍不溢出', (tester) async {
      await tester.pumpWidget(host(make(progress: 0.95, scale: 1.6)));
      expect(tester.takeException(), isNull);
    });

    testWidgets('极小画布不崩溃', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: CustomPaint(
            painter: make(),
            size: const Size(80, 60),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });

    test('progress 或 starTime 变化触发重绘', () {
      final a = make(progress: 0.3);
      expect(a.shouldRepaint(make(progress: 0.6)), isTrue);
      expect(a.shouldRepaint(make(progress: 0.3, starTime: 9)), isTrue);
      expect(a.shouldRepaint(make(progress: 0.3, starTime: 1.2)), isFalse);
    });

    test('语录变化触发重绘', () {
      final a = make(motto: '把该做的事做完，剩下的交给时间');
      expect(a.shouldRepaint(make(motto: '慢慢来，比较快')), isTrue);
    });
  });

  group('日期 + 每日语录', () {
    test('语录池无重复、长度受控', () {
      expect(kSplashMottos.toSet().length, kSplashMottos.length,
          reason: '池子里有重复句');
      for (final m in kSplashMottos) {
        expect(m.trim(), isNotEmpty);
        expect(m.characters.length, lessThanOrEqualTo(26),
            reason: '「$m」过长，会在字标下方放不下');
      }
    });

    test('同一天恒定，不受调用时刻影响', () {
      final morning = DateTime(2026, 9, 29, 6);
      final night = DateTime(2026, 9, 29, 23, 59);
      expect(mottoFor(morning), mottoFor(night));
    });

    test('相邻两天基本不撞句', () {
      final base = DateTime(2026, 1, 1);
      for (var i = 0; i < 30; i++) {
        final d1 = base.add(Duration(days: i));
        final d2 = base.add(Duration(days: i + 1));
        expect(mottoFor(d1), isNot(mottoFor(d2)),
            reason: '${formatSplashDate(d1)} 与次日撞句');
      }
    });

    test('跨年连续：12/31 与次年 1/1 是相邻两句', () {
      final a = mottoIndexFor(DateTime(2026, 12, 31));
      final b = mottoIndexFor(DateTime(2027, 1, 1));
      expect((a + 1) % kSplashMottos.length, b);
    });

    test('全年每天都能取到句子', () {
      for (var i = 0; i < 366; i++) {
        final d = DateTime(2026, 1, 1).add(Duration(days: i));
        expect(mottoFor(d), isNotEmpty);
        expect(kSplashMottos, contains(mottoFor(d)));
      }
    });

    test('日期格式含年月日与星期', () {
      final s = formatSplashDate(DateTime(2026, 9, 29));
      expect(s, contains('2026'));
      expect(s, contains('9'));
      expect(s, contains('29'));
      expect(s, contains('周二'));
    });

    test('字号下限保护生效', () {
      expect(clampMottoFontSize(4), 11.0);
      expect(clampMottoFontSize(20), 20.0);
    });

    test('超宽文本判定需要截断', () {
      expect(needsEllipsis('短句', 200, 14), isFalse);
      expect(needsEllipsis('把该做的事做完，剩下的交给时间', 40, 14), isTrue);
    });
  });

  group('SplashScreen 交互', () {
    testWidgets('动画跑完会回调 onFinished', (tester) async {
      var done = false;
      await tester.pumpWidget(
        MaterialApp(
          home: SplashScreen(
            duration: const Duration(milliseconds: 600),
            onFinished: () => done = true,
          ),
        ),
      );
      expect(done, isFalse);
      // 动画 600ms + 尾部驻留 720ms，留足余量
      await tester.pumpAndSettle(const Duration(milliseconds: 2000));
      expect(done, isTrue);
    });

    testWidgets('点击可立即跳过', (tester) async {
      var done = false;
      await tester.pumpWidget(
        MaterialApp(
          home: SplashScreen(
            duration: const Duration(seconds: 10),
            onFinished: () => done = true,
          ),
        ),
      );
      await tester.pump();
      expect(done, isFalse);
      await tester.tap(find.byType(SplashScreen));
      await tester.pump();
      expect(done, isTrue);
    });

    testWidgets('减少动态效果时立即交棒', (tester) async {
      var done = false;
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: SplashScreen(
              duration: const Duration(seconds: 10),
              onFinished: () => done = true,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(done, isTrue);
    });

    testWidgets('重复完成只回调一次', (tester) async {
      var count = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: SplashScreen(
            duration: const Duration(milliseconds: 400),
            onFinished: () => count++,
          ),
        ),
      );
      await tester.pumpAndSettle(const Duration(milliseconds: 600));
      // 结束后再点一次，不应重复触发
      await tester.tap(find.byType(SplashScreen), warnIfMissed: false);
      await tester.pump();
      expect(count, 1);
    });
  });

  group('SplashGate', () {
    testWidgets('启动层结束后仍保留主界面', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: SplashGate(
            duration: Duration(milliseconds: 400),
            child: Scaffold(body: Text('主界面')),
          ),
        ),
      );
      expect(find.text('主界面'), findsOneWidget);
      await tester.pumpAndSettle(const Duration(milliseconds: 900));
      expect(find.text('主界面'), findsOneWidget);
      expect(find.byType(SplashScreen), findsNothing);
    });

    test('总时长常量可用', () {
      expect(splashTotalDuration.inMilliseconds, greaterThan(1000));
    });
  });
}
