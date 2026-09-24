part of 'script_log_browser_controller.dart';

/// Number of error log lines shown immediately after parsing completes.
const int _errorLogInitialBatchSize = 200;

/// Number of error log lines appended in each follow-up batch.
const int _errorLogAppendBatchSize = 400;

/// Width threshold after which one log line skips rich highlighting.
const int kErrorLogPlainTextThreshold = 4096;

/// Parsed error log payload prepared outside the widget tree.
class ScriptErrorLogRenderPayload {
  /// Creates one parsed error log payload.
  const ScriptErrorLogRenderPayload({
    required this.lines,
    required this.maxWidthScore,
  });

  /// Prepared log lines.
  final List<String> lines;

  /// Widest line width score.
  final int maxWidthScore;
}

/// Parses raw error log text into virtual-rendering payload.
ScriptErrorLogRenderPayload parseScriptErrorLogPayload(String content) {
  final normalized = _trimErrorLogTrailingBreaks(content);
  if (normalized.isEmpty) {
    return const ScriptErrorLogRenderPayload(lines: <String>[], maxWidthScore: 0);
  }
  final lines = const LineSplitter().convert(normalized);
  var maxWidthScore = 0;
  for (final line in lines) {
    final score = _scoreScriptLogLineWidth(line);
    if (score > maxWidthScore) {
      maxWidthScore = score;
    }
  }
  return ScriptErrorLogRenderPayload(
    lines: lines,
    maxWidthScore: maxWidthScore,
  );
}

/// Removes trailing CR/LF characters from one error log payload.
String _trimErrorLogTrailingBreaks(String value) {
  var end = value.length;
  while (end > 0) {
    final codeUnit = value.codeUnitAt(end - 1);
    if (codeUnit != 10 && codeUnit != 13) {
      break;
    }
    end--;
  }
  return end == value.length ? value : value.substring(0, end);
}
