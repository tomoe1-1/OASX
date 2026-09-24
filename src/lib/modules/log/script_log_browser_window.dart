part of 'script_log_browser_controller.dart';

/// Cursor schema used by the log browser API.
const int _logCursorVersion = 1;

extension ScriptLogBrowserWindowX on ScriptLogBrowserController {
  /// Clears currently displayed info lines.
  void clearInfoLogs() {
    lines.clear();
    _lineKeys.clear();
    maxLineWidthScore = 0;
    savedScrollOffset = 0;
    savedAnchorKey = '';
    savedAnchorDelta = 0;
    retainedLogLineLimit = kAutoScrollLogWindowLineLimit;
  }

  /// Releases excessive history before returning to live tail.
  void trimToLiveWindow() {
    if (lines.length <= retainedLogLineLimit) {
      return;
    }
    if (autoScroll.value) {
      _trimOldestLines();
    } else {
      _trimNewestLines();
    }
    _recomputeMaxLineWidthScore();
  }

  /// Trims old lines while following the live tail.
  void _trimOldestLines() {
    final removedCount = lines.length - retainedLogLineLimit;
    final removedLines = lines.take(removedCount).toList();
    lines.removeRange(0, removedCount);
    _removeLineKeys(removedLines);
    if (lines.isNotEmpty) {
      olderCursor = _buildOlderCursor(lines.first);
      reachedStart = false;
    }
  }

  /// Trims newest lines while the user is reading an older viewport.
  void _trimNewestLines() {
    final start = retainedLogLineLimit;
    final removedLines = lines.skip(start).toList();
    lines.removeRange(start, lines.length);
    _removeLineKeys(removedLines);
    if (lines.isNotEmpty) {
      liveCursor = _buildLiveCursor(lines.last);
    }
  }

  /// Removes dedupe keys for discarded lines.
  void _removeLineKeys(Iterable<ScriptLogLine> removedLines) {
    for (final line in removedLines) {
      _lineKeys.remove(line.key);
    }
  }

  /// Refreshes the retention limit from the current auto-scroll mode.
  void syncWindowLimitForMode() {
    retainedLogLineLimit = autoScroll.value
        ? kAutoScrollLogWindowLineLimit
        : kManualScrollLogWindowLineLimit;
  }

  /// Applies a fresh latest window.
  void applyFreshWindow(ScriptLogWindow window) {
    lines.assignAll(window.lines);
    _lineKeys
      ..clear()
      ..addAll(window.lines.map((line) => line.key));
    _recomputeMaxLineWidthScore();
    olderCursor = window.olderCursor;
    liveCursor = window.liveCursor;
    reachedStart = window.reachedStart || !window.hasOlder;
  }

  /// Prepends older lines and asks UI to preserve viewport.
  void prependOlderWindow(ScriptLogWindow window) {
    if (window.lines.isEmpty) {
      olderCursor = window.olderCursor;
      reachedStart = window.reachedStart || !window.hasOlder;
      return;
    }
    final olderLines = window.lines
        .where((line) => !_lineKeys.contains(line.key))
        .toList();
    if (olderLines.isNotEmpty) {
      lines.insertAll(0, olderLines);
      _lineKeys.addAll(olderLines.map((line) => line.key));
      _recomputeMaxLineWidthScore();
      preserveViewportAfterPrepend?.call(olderLines.length);
    }
    olderCursor = window.olderCursor;
    reachedStart = window.reachedStart || !window.hasOlder;
  }

  /// Recomputes the widest line score after bulk changes.
  void _recomputeMaxLineWidthScore() {
    maxLineWidthScore = 0;
    for (final line in lines) {
      final score = _scoreScriptLogLineWidth(line.text);
      if (score > maxLineWidthScore) {
        maxLineWidthScore = score;
      }
    }
  }

  /// Builds an API-compatible older cursor for a retained first line.
  String _buildOlderCursor(ScriptLogLine line) {
    final cursorPayload = {
      'v': _logCursorVersion,
      'script_name': scriptName,
      'direction': 'older',
      'file_name': line.fileName,
      'offset': line.offset,
      'line_no': line.lineNo,
    };
    final json = jsonEncode(cursorPayload);
    return base64Url.encode(utf8.encode(json)).replaceAll('=', '');
  }

  /// Builds an API-compatible live cursor for a retained last line.
  String _buildLiveCursor(ScriptLogLine line) {
    final cursorPayload = {
      'v': _logCursorVersion,
      'script_name': scriptName,
      'direction': 'newer',
      'file_name': line.fileName,
      'offset': line.offset,
      'line_no': line.lineNo,
    };
    final json = jsonEncode(cursorPayload);
    return base64Url.encode(utf8.encode(json)).replaceAll('=', '');
  }
}
