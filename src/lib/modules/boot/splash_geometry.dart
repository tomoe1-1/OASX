/// 启动动画的几何造型定义
///
/// 参考视频的核心视觉是「线框 → 实体化」，但原片角色为 AI 生成的二次元形象，
/// 直接复用有版权风险且与 OASX 调性不符。这里改用**阴阳师题材的几何线框**：
///
/// - 外层：十二等分符咒法阵（同心圆 + 刻度 + 放射线）
/// - 中层：鸟居剪影（阴阳师 / 神社的视觉锚点）
/// - 内层：机械齿轮阵列（呼应「脚本自动化」的工具属性）
///
/// 全部以归一化坐标（0–1）描述，由 [WireGeometry.build] 在运行时按
/// 画布尺寸缩放，因此任意窗口比例下都保持居中不变形。
library;

import 'dart:math' as math;
import 'dart:ui';

/// 归一化坐标系中的一个点
typedef NPoint = Offset;

/// 把归一化坐标点换算到实际画布的辅助工具
class WireGeometry {
  WireGeometry(this.size)
      : _short = math.min(size.width, size.height),
        _cx = size.width / 2,
        _cy = size.height / 2;

  final Size size;
  final double _short;
  final double _cx;
  final double _cy;

  /// 归一化 (0–1) → 画布坐标。以短边为基准，保证等比。
  Offset p(double x, double y) =>
      Offset(_cx + (x - 0.5) * _short, _cy + (y - 0.5) * _short);

  /// 归一化半径 → 画布半径
  double r(double radius) => radius * _short;

  /// 画布坐标下中心点
  Offset get center => Offset(_cx, _cy);

  /// ---- 法阵：同心圆环 ----

  /// 同心圆环半径（归一化）
  static const List<double> ringRadii = <double>[0.34, 0.295, 0.20, 0.165, 0.085];

  /// 外环刻度线数量
  static const int tickCount = 12;

  /// 内环细刻度数量
  static const int fineTickCount = 60;

  /// 生成外环的 12 条刻度（从内向外放射）
  static List<(Offset, Offset)> ticks(WireGeometry g) {
    final out = <(Offset, Offset)>[];
    for (var i = 0; i < tickCount; i++) {
      final a = (i / tickCount) * math.pi * 2 - math.pi / 2;
      final ca = math.cos(a), sa = math.sin(a);
      out.add((
        g.center + Offset(ca, sa) * g.r(0.295),
        g.center + Offset(ca, sa) * g.r(0.34),
      ));
    }
    return out;
  }

  /// 生成内环的 60 条细刻度
  static List<(Offset, Offset)> fineTicks(WireGeometry g) {
    final out = <(Offset, Offset)>[];
    for (var i = 0; i < fineTickCount; i++) {
      final a = (i / fineTickCount) * math.pi * 2 - math.pi / 2;
      final ca = math.cos(a), sa = math.sin(a);
      final inner = i % 5 == 0 ? 0.155 : 0.16;
      out.add((
        g.center + Offset(ca, sa) * g.r(inner),
        g.center + Offset(ca, sa) * g.r(0.165),
      ));
    }
    return out;
  }

  /// 生成 6 条放射交叉线（法阵骨架）
  static List<(Offset, Offset)> radiants(WireGeometry g) {
    final out = <(Offset, Offset)>[];
    for (var i = 0; i < 6; i++) {
      final a = (i / 6) * math.pi;
      final ca = math.cos(a), sa = math.sin(a);
      out.add((
        g.center - Offset(ca, sa) * g.r(0.20),
        g.center + Offset(ca, sa) * g.r(0.20),
      ));
    }
    return out;
  }

  /// ---- 鸟居：立柱 + 笠木 + 贯 + 额束 ----
  ///
  /// 归一化坐标，(x, y)，y 向下为正。整体高度约 0.30。
  static List<List<Offset>> toriiBars() => <List<Offset>>[
        // 左柱（略内倾）
        <Offset>[const Offset(0.435, 0.325), const Offset(0.428, 0.505)],
        // 右柱
        <Offset>[const Offset(0.565, 0.325), const Offset(0.572, 0.505)],
        // 笠木（顶横梁，略上翘）
        <Offset>[
          const Offset(0.395, 0.322),
          const Offset(0.435, 0.308),
          const Offset(0.500, 0.303),
          const Offset(0.565, 0.308),
          const Offset(0.605, 0.322),
        ],
        // 岛木（第二道横梁）
        <Offset>[const Offset(0.420, 0.342), const Offset(0.580, 0.342)],
        // 贯（下横梁）
        <Offset>[const Offset(0.428, 0.408), const Offset(0.572, 0.408)],
        // 额束（中央竖条）
        <Offset>[const Offset(0.500, 0.342), const Offset(0.500, 0.408)],
      ];

  /// ---- 齿轮：齿廓路径 ----
  ///
  /// 返回一个闭合路径的顶点序列（归一化）。
  static List<Offset> gearOutline({
    required double cx,
    required double cy,
    required double outer,
    required double inner,
    required int teeth,
  }) {
    final pts = <Offset>[];
    final step = math.pi * 2 / teeth;
    for (var i = 0; i < teeth; i++) {
      final base = i * step;
      // 齿根 → 齿顶 → 齿顶 → 齿根（梯形齿）
      pts.add(Offset(cx + math.cos(base) * inner, cy + math.sin(base) * inner));
      pts.add(Offset(
        cx + math.cos(base + step * 0.18) * outer,
        cy + math.sin(base + step * 0.18) * outer,
      ));
      pts.add(Offset(
        cx + math.cos(base + step * 0.42) * outer,
        cy + math.sin(base + step * 0.42) * outer,
      ));
      pts.add(Offset(
        cx + math.cos(base + step * 0.60) * inner,
        cy + math.sin(base + step * 0.60) * inner,
      ));
    }
    return pts;
  }

  /// 主齿轮（中心偏下，大）
  static List<Offset> mainGear() => gearOutline(
        cx: 0.5,
        cy: 0.5,
        outer: 0.078,
        inner: 0.060,
        teeth: 12,
      );

  /// 副齿轮（左上，小）
  static List<Offset> subGearA() => gearOutline(
        cx: 0.415,
        cy: 0.415,
        outer: 0.036,
        inner: 0.027,
        teeth: 9,
      );

  /// 副齿轮（右下，小）
  static List<Offset> subGearB() => gearOutline(
        cx: 0.585,
        cy: 0.585,
        outer: 0.030,
        inner: 0.022,
        teeth: 8,
      );

  /// ---- 侧翼：连接法阵与中心的支撑线 ----

  /// 左右各三条斜撑
  static List<(Offset, Offset)> wings() {
    final out = <(Offset, Offset)>[];
    for (final sign in <double>[-1, 1]) {
      out.add((
        Offset(0.5 + sign * 0.165, 0.5),
        Offset(0.5 + sign * 0.295, 0.5 - 0.10 * sign),
      ));
      out.add((
        Offset(0.5 + sign * 0.165, 0.5),
        Offset(0.5 + sign * 0.275, 0.5 + 0.115 * sign),
      ));
      out.add((
        Offset(0.5 + sign * 0.20, 0.5 + 0.055 * sign),
        Offset(0.5 + sign * 0.315, 0.5 + 0.045 * sign),
      ));
    }
    return out;
  }
}
