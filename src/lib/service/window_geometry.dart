import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui';

import 'package:oasx/modules/common/models/window_state.dart';

/// Invalid or old storage must never prevent the application's window showing.
WindowStateModel? decodeWindowState(Object? storedValue) {
  try {
    final value = storedValue is String ? jsonDecode(storedValue) : storedValue;
    if (value is! Map) return null;
    final coordinates = ['x', 'y', 'width', 'height'].map((key) => value[key]);
    if (coordinates.any((value) => value is! num || !value.isFinite)) {
      return null;
    }
    final state = WindowStateModel.fromJson(Map<String, dynamic>.from(value));
    return state.width > 0 && state.height > 0 ? state : null;
  } catch (_) {
    return null;
  }
}

bool isValidWindowRect(Rect bounds) =>
    bounds.left.isFinite &&
    bounds.top.isFinite &&
    bounds.right.isFinite &&
    bounds.bottom.isFinite &&
    bounds.width > 0 &&
    bounds.height > 0;

/// A visible content sliver is insufficient: the title bar must be reachable.
/// Negative coordinates are normal for monitors left of or above the primary.
bool hasReachableWindowTitleBar(Rect bounds, Rect workArea) {
  if (!isValidWindowRect(bounds) || !isValidWindowRect(workArea)) return false;
  final titleBar = Rect.fromLTWH(
    bounds.left,
    bounds.top,
    bounds.width,
    math.min(48.0, bounds.height),
  );
  final visibleTitle = titleBar.intersect(workArea);
  return visibleTitle.width >= math.min(100.0, bounds.width) &&
      visibleTitle.height >= math.min(24.0, bounds.height);
}

Size fitWindowSize(Size size, Rect workArea, {required Size minimumSize}) =>
    Size(
      size.width.clamp(
        math.min(minimumSize.width, workArea.width),
        workArea.width,
      ),
      size.height.clamp(
        math.min(minimumSize.height, workArea.height),
        workArea.height,
      ),
    );

/// Null requests the default centered window, including when a monitor was
/// disconnected or Windows saved its minimized (-32000, -32000) coordinates.
WindowStateModel? restoreWindowGeometry(
  Object? storedValue, {
  required List<Rect> workAreas,
  required Size minimumSize,
}) {
  final state = decodeWindowState(storedValue);
  if (state == null) return null;
  final bounds = Rect.fromLTWH(state.x, state.y, state.width, state.height);
  for (final workArea in workAreas) {
    if (!hasReachableWindowTitleBar(bounds, workArea)) continue;
    final size = fitWindowSize(bounds.size, workArea, minimumSize: minimumSize);
    final fitted = Rect.fromLTWH(state.x, state.y, size.width, size.height);
    if (!hasReachableWindowTitleBar(fitted, workArea)) continue;
    return WindowStateModel(
      x: fitted.left,
      y: fitted.top,
      width: fitted.width,
      height: fitted.height,
    );
  }
  return null;
}

/// Persist only usable normal-window bounds, never a minimized/maximized frame.
WindowStateModel? windowGeometryToSave(
  Rect bounds, {
  required bool isMinimized,
  required bool isMaximized,
  required List<Rect> workAreas,
  required Size minimumSize,
}) {
  if (isMinimized || isMaximized || !isValidWindowRect(bounds)) return null;
  if (bounds.width < minimumSize.width || bounds.height < minimumSize.height) {
    return null;
  }
  if (!workAreas.any((area) => hasReachableWindowTitleBar(bounds, area))) {
    return null;
  }
  return WindowStateModel(
    x: bounds.left,
    y: bounds.top,
    width: bounds.width,
    height: bounds.height,
  );
}
