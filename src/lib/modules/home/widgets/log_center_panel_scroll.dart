part of 'log_center_panel.dart';

/// Toggles line wrapping while keeping current bottom/manual behavior stable.
void _handleLogCenterLineWrapToggle(_LogCenterPanelState state) {
  final controller = state._controller;
  if (controller == null) {
    return;
  }
  if (controller.activeTab.value == ScriptLogBrowserTab.error) {
    controller.toggleLineWrap();
    return;
  }
  final shouldFollow =
      controller.autoScroll.value || _isLogCenterAtBottom(state);
  _suppressLogCenterScrollHandling(state, frames: shouldFollow ? 4 : 2);
  controller.toggleLineWrap();
  if (!shouldFollow) {
    return;
  }
  controller.autoScroll.value = true;
  controller.trimToLiveWindow();
  _scrollLogCenterToBottom(state, jumpOnly: true);
}

/// Activates a controller once the panel viewport is attached.
void _activateLogCenterControllerAfterFrame(
  _LogCenterPanelState state,
  ScriptLogBrowserController controller,
) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!state.mounted || state._controller != controller) {
      return;
    }
    if (controller.viewportOwner != state._viewportOwner) {
      return;
    }
    if (controller.activeTab.value == ScriptLogBrowserTab.error) {
      controller.activate();
      return;
    }
    if (controller.shouldRefreshLatestOnInfoResume) {
      controller.activate();
      return;
    }
    if (controller.autoScroll.value) {
      controller.trimToLiveWindow();
      _scrollLogCenterToBottom(state, jumpOnly: true);
    } else {
      controller.restoreManualPosition();
    }
    controller.activate();
  });
}

/// Releases the viewport callbacks owned by this panel.
void _releaseLogCenterController(
  _LogCenterPanelState state, {
  required bool suspend,
}) {
  final controller = state._controller;
  if (controller == null || controller.viewportOwner != state._viewportOwner) {
    return;
  }
  if (controller.activeTab.value == ScriptLogBrowserTab.info) {
    controller.handleInfoViewHidden();
  }
  controller.scrollToBottom = null;
  controller.restoreScrollOffset = null;
  controller.preserveViewportAfterPrepend = null;
  controller.resetErrorDetailViewport = null;
  controller.viewportOwner = null;
  if (suspend) {
    controller.suspend();
  }
}

/// Resets the error detail viewport to the initial position.
void _resetErrorDetailViewport(_LogCenterPanelState state) {
  final vertical = state._errorDetailScrollController;
  final horizontal = state._errorDetailHorizontalScrollController;
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (vertical != null && vertical.hasClients) {
      vertical.jumpTo(0);
    }
    if (horizontal != null && horizontal.hasClients) {
      horizontal.jumpTo(0);
    }
  });
}

/// Handles one scroll notification from the info log list.
void _handleLogCenterScrollPosition(_LogCenterPanelState state) {
  final controller = state._controller;
  final scrollController = state._scrollController;
  if (controller == null ||
      scrollController == null ||
      !scrollController.hasClients) {
    return;
  }
  final position = scrollController.position;
  final offset = scrollController.offset;
  final isAtBottom =
      offset >=
      position.maxScrollExtent - _LogCenterPanelState._bottomThreshold;
  controller.handleViewportPosition(isAtBottom: isAtBottom);
  _saveLogCenterViewport(state);
  final linesBeforeViewport = _firstVisibleLogIndex(offset);
  if (linesBeforeViewport <= _LogCenterPanelState._prefetchRemainingLines) {
    controller.prefetchOlder();
  }
}

/// Persists the current info log viewport for script revisit recovery.
void _saveLogCenterViewport(_LogCenterPanelState state) {
  final controller = state._controller;
  final scrollController = state._scrollController;
  if (controller == null ||
      scrollController == null ||
      !scrollController.hasClients) {
    return;
  }
  final offset = scrollController.offset;
  final index = _firstVisibleLogIndex(offset).clamp(0, controller.lines.length);
  final anchorKey = index < controller.lines.length
      ? controller.lines[index].key
      : '';
  final anchorDelta =
      offset - index * _LogCenterPanelState._estimatedLineExtent;
  controller.saveViewport(
    offset: offset,
    anchorKey: anchorKey,
    anchorDelta: anchorDelta,
  );
}

/// Scrolls the info log list to the current bottom after layout settles.
void _scrollLogCenterToBottom(
  _LogCenterPanelState state, {
  bool jumpOnly = false,
}) {
  final token = ++state._bottomScrollToken;
  _suppressLogCenterScrollHandling(state, frames: 3);
  _scheduleLogCenterBottomJump(state, token, jumpOnly: jumpOnly);
}

/// Jumps to bottom once layout is ready.
void _scheduleLogCenterBottomJump(
  _LogCenterPanelState state,
  int token, {
  required bool jumpOnly,
}) {
  final scrollController = state._scrollController;
  if (!state.mounted || scrollController == null) {
    return;
  }
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!state.mounted ||
        token != state._bottomScrollToken ||
        !scrollController.hasClients) {
      return;
    }
    final target = scrollController.position.maxScrollExtent;
    if (jumpOnly || (scrollController.offset - target).abs() > 400) {
      scrollController.jumpTo(target);
    } else {
      scrollController.animateTo(
        target,
        // 走令牌，尊重系统「减少动态效果」偏好。
        duration: Motion.of(state.context, Motion.settle),
        curve: Motion.scrollCurve,
      );
    }
  });
}

/// Ignores scroll updates produced by programmatic jumps for a few frames.
void _suppressLogCenterScrollHandling(
  _LogCenterPanelState state, {
  required int frames,
}) {
  final token = ++state._scrollSuppressionToken;
  state._suppressScrollHandling = true;
  _scheduleLogCenterScrollHandlingRelease(state, token, frames);
}

/// Releases programmatic scroll suppression after layout has settled.
void _scheduleLogCenterScrollHandlingRelease(
  _LogCenterPanelState state,
  int token,
  int frames,
) {
  if (frames <= 0) {
    if (state.mounted && token == state._scrollSuppressionToken) {
      state._suppressScrollHandling = false;
    }
    return;
  }
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!state.mounted || token != state._scrollSuppressionToken) {
      return;
    }
    _scheduleLogCenterScrollHandlingRelease(state, token, frames - 1);
  });
}

/// Returns whether the vertical info viewport is already near bottom.
bool _isLogCenterAtBottom(_LogCenterPanelState state) {
  final scrollController = state._scrollController;
  if (scrollController == null || !scrollController.hasClients) {
    return false;
  }
  final position = scrollController.position;
  return scrollController.offset >=
      position.maxScrollExtent - _LogCenterPanelState._bottomThreshold;
}

/// Restores a previously saved info log scroll offset.
void _restoreLogCenterScrollOffset(_LogCenterPanelState state, double offset) {
  final scrollController = state._scrollController;
  final controller = state._controller;
  if (!state.mounted || scrollController == null) {
    return;
  }
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!state.mounted || !scrollController.hasClients) {
      return;
    }
    final target = _resolveLogCenterOffset(
      controller,
      scrollController,
      fallbackOffset: offset,
    );
    scrollController.jumpTo(target);
  });
}

/// Preserves the visible info log window after older lines are prepended.
void _preserveLogCenterViewportAfterPrepend(
  _LogCenterPanelState state,
  int insertedCount,
) {
  final scrollController = state._scrollController;
  final controller = state._controller;
  if (!state.mounted || scrollController == null || insertedCount <= 0) {
    return;
  }
  final previousOffset = scrollController.hasClients
      ? scrollController.offset
      : 0.0;
  final delta = insertedCount * _LogCenterPanelState._estimatedLineExtent;
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!state.mounted || !scrollController.hasClients) {
      return;
    }
    final target = _resolveLogCenterOffset(
      controller,
      scrollController,
      fallbackOffset: previousOffset + delta,
    ).clamp(0.0, scrollController.position.maxScrollExtent);
    scrollController.jumpTo(target);
  });
}

/// Estimates the first visible line index from scroll offset.
int _firstVisibleLogIndex(double offset) {
  return (offset / _LogCenterPanelState._estimatedLineExtent).floor();
}

/// Resolves one best-effort scroll target from the saved anchor state.
double _resolveLogCenterOffset(
  ScriptLogBrowserController? controller,
  ScrollController scrollController, {
  required double fallbackOffset,
}) {
  if (controller == null || controller.savedAnchorKey.isEmpty) {
    return fallbackOffset.clamp(0.0, scrollController.position.maxScrollExtent);
  }
  final anchorIndex = controller.lines.indexWhere(
    (line) => line.key == controller.savedAnchorKey,
  );
  if (anchorIndex < 0) {
    return fallbackOffset.clamp(0.0, scrollController.position.maxScrollExtent);
  }
  final target =
      anchorIndex * _LogCenterPanelState._estimatedLineExtent +
      controller.savedAnchorDelta;
  return target.clamp(0.0, scrollController.position.maxScrollExtent);
}
