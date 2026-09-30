import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:oasx/service/window_geometry.dart';

void main() {
  const primary = Rect.fromLTWH(0, 0, 1920, 1040);
  const leftMonitor = Rect.fromLTWH(-1920, 0, 1920, 1040);
  const upperMonitor = Rect.fromLTWH(0, -1080, 1920, 1040);
  const minimum = Size(260, 420);
  const normal = Rect.fromLTWH(100, 80, 1200, 800);

  Map<String, Object> stored(Rect rect) => {
    'x': rect.left,
    'y': rect.top,
    'width': rect.width,
    'height': rect.height,
  };

  group('stored window recovery', () {
    test('report minimized geometry requests the default centered window', () {
      expect(
        restoreWindowGeometry(
          '{"x":-32000,"y":-32000,"width":160,"height":28}',
          workAreas: [primary],
          minimumSize: minimum,
        ),
        isNull,
      );
    });

    test('bad JSON and wrong field types cannot abort startup', () {
      for (final value in [
        '{truncated',
        '[]',
        'null',
        3,
        {'x': 100, 'y': 80, 'width': '1200', 'height': 800},
        {'x': 100, 'width': 1200, 'height': 800},
      ]) {
        expect(decodeWindowState(value), isNull, reason: '$value');
      }
    });

    test('non-finite fields and non-positive dimensions are discarded', () {
      for (final field in ['x', 'y', 'width', 'height']) {
        for (final number in [double.nan, double.infinity, -double.infinity]) {
          expect(decodeWindowState({...stored(normal), field: number}), isNull);
        }
      }
      expect(decodeWindowState({...stored(normal), 'width': 0}), isNull);
      expect(decodeWindowState({...stored(normal), 'height': -10}), isNull);
    });

    test('an existing left monitor preserves legitimate negative x', () {
      final state = restoreWindowGeometry(
        stored(const Rect.fromLTWH(-1700, 80, 1200, 800)),
        workAreas: [primary, leftMonitor],
        minimumSize: minimum,
      );
      expect(state?.x, -1700);
      expect(state?.y, 80);
      expect(state?.width, 1200);
    });

    test('an existing upper monitor preserves legitimate negative y', () {
      final state = restoreWindowGeometry(
        stored(const Rect.fromLTWH(100, -1000, 1200, 800)),
        workAreas: [primary, upperMonitor],
        minimumSize: minimum,
      );
      expect(state?.y, -1000);
    });

    test('removed secondary monitor requests the default centered window', () {
      expect(
        restoreWindowGeometry(
          stored(const Rect.fromLTWH(-1700, 80, 1200, 800)),
          workAreas: [primary],
          minimumSize: minimum,
        ),
        isNull,
      );
    });

    test('content visible with unreachable title bar requests recentering', () {
      expect(
        restoreWindowGeometry(
          stored(const Rect.fromLTWH(100, -300, 1200, 800)),
          workAreas: [primary],
          minimumSize: minimum,
        ),
        isNull,
      );
    });

    test('barely overlapping an edge is insufficient to restore a window', () {
      expect(
        restoreWindowGeometry(
          stored(const Rect.fromLTWH(1900, 80, 1200, 800)),
          workAreas: [primary],
          minimumSize: minimum,
        ),
        isNull,
      );
    });

    test('valid tiny saved size is raised to the minimum', () {
      final state = restoreWindowGeometry(
        stored(const Rect.fromLTWH(100, 80, 160, 28)),
        workAreas: [primary],
        minimumSize: minimum,
      );
      expect(state?.width, 260);
      expect(state?.height, 420);
    });

    test('oversized dimensions are bounded by the current work area', () {
      final state = restoreWindowGeometry(
        stored(const Rect.fromLTWH(0, 0, 100000, 100000)),
        workAreas: [primary],
        minimumSize: minimum,
      );
      expect(state?.width, 1920);
      expect(state?.height, 1040);
    });

    test('failed display lookup never restores unverified coordinates', () {
      expect(
        restoreWindowGeometry(
          stored(normal),
          workAreas: [],
          minimumSize: minimum,
        ),
        isNull,
      );
    });

    test('default size fits a laptop work area with a taskbar', () {
      expect(
        fitWindowSize(
          const Size(1200, 800),
          const Rect.fromLTWH(0, 0, 1366, 728),
          minimumSize: minimum,
        ),
        const Size(1200, 728),
      );
    });
  });

  group('normal window persistence', () {
    test('minimized and maximized bounds never overwrite the normal state', () {
      for (final flags in [(true, false), (false, true), (true, true)]) {
        expect(
          windowGeometryToSave(
            normal,
            isMinimized: flags.$1,
            isMaximized: flags.$2,
            workAreas: [primary],
            minimumSize: minimum,
          ),
          isNull,
        );
      }
    });

    test('sentinel, tiny, invalid and unreachable bounds are ignored', () {
      for (final bounds in [
        const Rect.fromLTWH(-32000, -32000, 160, 28),
        const Rect.fromLTWH(100, 80, 160, 28),
        const Rect.fromLTWH(3000, 80, 1200, 800),
        const Rect.fromLTWH(double.nan, 80, 1200, 800),
        const Rect.fromLTWH(100, 80, double.infinity, 800),
      ]) {
        expect(
          windowGeometryToSave(
            bounds,
            isMinimized: false,
            isMaximized: false,
            workAreas: [primary],
            minimumSize: minimum,
          ),
          isNull,
          reason: '$bounds',
        );
      }
    });

    test('normal negative-coordinate multi-monitor bounds are saved', () {
      final state = windowGeometryToSave(
        const Rect.fromLTWH(-1700, 80, 1200, 800),
        isMinimized: false,
        isMaximized: false,
        workAreas: [primary, leftMonitor],
        minimumSize: minimum,
      );
      expect(state?.x, -1700);
      expect(state?.width, 1200);
      expect(state?.height, 800);
    });
  });
}
