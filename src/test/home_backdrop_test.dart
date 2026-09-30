import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oasx/modules/home/widgets/home_backdrop.dart';

/// 主界面底衬的**几何不变量**与**降级可见性**测试。
///
/// 底衬是纯绘制，视觉正确性靠离屏渲染复核；这里只钉住那些
/// 「改坏了不会报错、但会让画面塌掉」的数值关系。
///
/// 测试环境不允许跑 `flutter test`（沙箱禁止 Dart 创建子进程），
/// 这些断言与 `tools/render_home_backdrop.py` 里的复核脚本一一对应。
void main() {
  group('底衬构图常量', () {
    test('画布高度比例落在实测达标区间', () {
      // 第二版素材是头肩特写全高人像：1.1 = 顶部出血 10%、底边贴窗口
      // 下缘，脸落在右上舞台。改动它必须重跑
      // tools/measure_real_geometry.py 逐帧复核。
      expect(backdropDebugHeightRatio(), lessThanOrEqualTo(1.3));
      expect(backdropDebugHeightRatio(), greaterThanOrEqualTo(0.9));
    });

    test('最窄窗口下仍有可见区域', () {
      // 主界面面板之间存在 Spacing.md 的缝隙，底衬至少要在这里露出来。
      // 1200 是双栏布局能启用的最小宽度。
      expect(backdropMinVisibleWidth(1200), greaterThan(120));
      expect(backdropMinVisibleWidth(1920), greaterThan(200));
    });

    test('可见宽度随窗口单调递增', () {
      final widths = <double>[1024, 1280, 1440, 1920, 2560];
      for (var i = 1; i < widths.length; i++) {
        expect(
          backdropMinVisibleWidth(widths[i]),
          greaterThan(backdropMinVisibleWidth(widths[i - 1])),
          reason: '${widths[i]} 的可见宽度应大于 ${widths[i - 1]}',
        );
      }
    });

    test('退化输入不抛异常', () {
      expect(backdropMinVisibleWidth(0), 0);
      expect(backdropMinVisibleWidth(-100), 0);
    });
  });

  group('立绘舞台宽度', () {
    // 舞台是布局侧 Row 末尾的真实占位，painter 用同一公式定位立绘。
    // 这里的断言钉住两个不变量：装饰给功能让路、宽度有界。
    test('理想值夹在 [120, 300]', () {
      expect(backdropStageWidth(4000), 300, reason: '超宽屏封顶 300');
    });

    test('1280 窗口仍有舞台且三栏保得住', () {
      // 1280 窗口 → 工作台 1256：理想 163，富余 164 → 取 163。
      // 剩余 1093 ≥ 三栏最低 1092，三栏不因舞台退化。
      final stage = backdropStageWidth(1256);
      expect(stage, greaterThan(120));
      expect(1256 - stage, greaterThanOrEqualTo(1092));
    });

    test('空间不足时舞台给三栏让路到 0', () {
      // 三栏最低总宽 1092：工作台只有这么多时，一像素舞台都不能要。
      expect(backdropStageWidth(1092), 0);
      expect(backdropStageWidth(1000), 0);
      expect(backdropStageWidth(0), 0);
      expect(backdropStageWidth(-100), 0);
    });

    test('舞台宽度随工作台宽度单调不减', () {
      final widths = <double>[1000, 1100, 1256, 1440 - 24, 1896, 2536, 4000];
      for (var i = 1; i < widths.length; i++) {
        expect(
          backdropStageWidth(widths[i]),
          greaterThanOrEqualTo(backdropStageWidth(widths[i - 1])),
          reason: '${widths[i]} 的舞台宽度不应小于 ${widths[i - 1]}',
        );
      }
    });
  });

  group('左侧渐隐方向', () {
    // 回归的是「立绘整块消失」事故：dstIn 语义是 dst × **src.a**，
    // 透明端 = 被擦掉的那端。方向写反没有任何报错，立绘却在窗口
    // 右半部被整体擦除 —— 而立绘恰恰锚在右缘舞台上。
    test('渐变起点必须比终点更透明（左擦右留）', () {
      final colors = backdropFadeLeftColors();
      expect(colors.start.a, lessThan(colors.end.a),
          reason: 'dstIn 下透明端会被擦除：起点（窗口左缘）必须透明、'
              '终点（舞台方向）必须不透明，反了立绘整块消失');
    });

    test('两端分别是全透与全不透，不做半途渐隐的模糊地带', () {
      final colors = backdropFadeLeftColors();
      expect(colors.start.a, 0.0);
      expect(colors.end.a, 1.0);
    });
  });

  group('资源缺失时的降级', () {
    // 这一组回归的是「改了代码、构建也过、跑起来毫无变化」那次事故：
    // 当时 AssetManifest.bin 没同步 → rootBundle.load 抛异常 → 旧代码
    // `catch (_) {}` 吞掉 → 界面正常但底衬完全不出现，且毫无线索。
    //
    // 降级本身是对的（底衬是装饰，不该阻塞主界面），
    // 但**必须可观测** —— isDegraded 就是那个观测点。

    testWidgets('资源缺失 → 降级为纯表面色，且 isDegraded 为 true', (tester) async {
      // 不提供任何资源，模拟 manifest 里没有这张图。
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMessageHandler(
        'flutter/assets',
        (ByteData? message) async => null,
      );
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMessageHandler('flutter/assets', null);
      });

      await tester.pumpWidget(
        const MaterialApp(
          home: HomeBackdrop(child: Text('内容仍在')),
        ),
      );
      // 让 _load() 的 Future 跑完（它会失败）。
      await tester.pumpAndSettle();

      // 界面没有被阻塞 —— 降级的目的
      expect(find.text('内容仍在'), findsOneWidget);

      // 但失败被记录下来了 —— 这是本次修复的核心
      final state = tester.state<State<HomeBackdrop>>(find.byType(HomeBackdrop));
      // ignore: avoid_dynamic_calls
      expect((state as dynamic).isDegraded, isTrue,
          reason: '资源加载失败必须留下可观测的痕迹，不能静默吞掉');
    });
  });

  group('回退链：动画 → 静态 → 降级', () {
    // 回退链的三级都有语义：
    //   动画 webp 失败/单帧异常 → 静态 jpg → 纯表面色（可观测）。
    // 这里用仓库里的**真实资源字节**喂给 asset channel，
    // 验证「动画不可用时静态仍然撑得住」——这正是部署期最容易出现的
    // 中间态（webp 没同步上、jpg 是旧的但还在）。

    Future<void> mockAssets(Map<String, List<int>> assets) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMessageHandler('flutter/assets', (ByteData? message) async {
        // message 是 UTF-8 编码的 asset key
        final data = message!.buffer.asUint8List();
        final keyStr = String.fromCharCodes(data);
        final bytes = assets[keyStr];
        if (bytes == null) {
          return null;
        }
        return ByteData.view(Uint8List.fromList(bytes).buffer);
      });
    }

    testWidgets('动画缺失但静态可用 → 显示静态，不降级', (tester) async {
      final jpgBytes =
          File('assets/images/main_bg_muse.jpg').readAsBytesSync();
      await mockAssets({
        'assets/images/main_bg_muse.jpg': jpgBytes,
      });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMessageHandler('flutter/assets', null);
      });

      await tester.pumpWidget(
        const MaterialApp(
          home: HomeBackdrop(child: Text('内容仍在')),
        ),
      );
      await tester.pumpAndSettle();

      final state = tester.state<State<HomeBackdrop>>(find.byType(HomeBackdrop));
      // ignore: avoid_dynamic_calls
      expect((state as dynamic).isDegraded, isFalse,
          reason: '静态可用时不应降级为纯表面色');
      // ignore: avoid_dynamic_calls
      expect((state as dynamic).isAnimated, isFalse,
          reason: '动画缺失时应回退为静态而不是降级');
      expect(find.byType(CustomPaint), findsOneWidget);
    });

    testWidgets('动画资源可用 → isAnimated 为 true 且逐帧推进', (tester) async {
      final webpBytes =
          File('assets/images/main_bg_muse_anim.webp').readAsBytesSync();
      await mockAssets({
        'assets/images/main_bg_muse_anim.webp': webpBytes,
      });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMessageHandler('flutter/assets', null);
      });

      await tester.pumpWidget(
        const MaterialApp(
          home: HomeBackdrop(child: Text('内容仍在')),
        ),
      );
      // 动画是无限循环，**不能** pumpAndSettle（永远停不下来会超时）。
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      final state = tester.state<State<HomeBackdrop>>(find.byType(HomeBackdrop));
      // ignore: avoid_dynamic_calls
      expect((state as dynamic).isAnimated, isTrue,
          reason: '动画资源可用时必须真的在播逐帧动画');
      expect(find.byType(CustomPaint), findsOneWidget);
    });
  });
}
