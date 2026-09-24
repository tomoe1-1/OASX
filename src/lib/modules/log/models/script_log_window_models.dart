/// Describes one position inside a script log file.
class ScriptLogPosition {
  /// Creates one log position snapshot.
  const ScriptLogPosition({this.fileName, this.offset, this.lineNo});

  /// Log file name containing the position.
  final String? fileName;

  /// Byte offset in the log file.
  final int? offset;

  /// One-based line number in the log file.
  final int? lineNo;

  /// Builds a position from JSON.
  factory ScriptLogPosition.fromJson(Map<String, dynamic>? json) {
    return ScriptLogPosition(
      fileName: json?['file_name'] as String?,
      offset: _readInt(json?['offset']),
      lineNo: _readInt(json?['line_no']),
    );
  }
}

/// Server echo of one log window limit set.
class ScriptLogWindowLimits {
  /// Creates one limit set.
  const ScriptLogWindowLimits({
    required this.limitLines,
    required this.limitBytes,
    required this.maxLineBytes,
  });

  /// Maximum returned lines for the request.
  final int limitLines;

  /// Maximum returned bytes for the request.
  final int limitBytes;

  /// Maximum display bytes for one line.
  final int maxLineBytes;

  /// Builds limit metadata from JSON.
  factory ScriptLogWindowLimits.fromJson(Map<String, dynamic>? json) {
    return ScriptLogWindowLimits(
      limitLines: _readInt(json?['limit_lines']) ?? 0,
      limitBytes: _readInt(json?['limit_bytes']) ?? 0,
      maxLineBytes: _readInt(json?['max_line_bytes']) ?? 0,
    );
  }
}

/// One renderable script log line.
class ScriptLogLine {
  /// Creates one script log line.
  const ScriptLogLine({
    required this.fileName,
    required this.lineNo,
    required this.offset,
    required this.byteLength,
    required this.text,
    required this.lineTruncated,
  });

  /// Log file name.
  final String fileName;

  /// One-based line number.
  final int lineNo;

  /// Byte offset of the line start.
  final int offset;

  /// Raw byte length including newline.
  final int byteLength;

  /// Display text without trailing newline.
  final String text;

  /// Whether display text was truncated.
  final bool lineTruncated;

  /// Stable key used for anchors and duplicate prevention.
  String get key => '$fileName:$lineNo:$offset';

  /// Builds a log line from JSON.
  factory ScriptLogLine.fromJson(Map<String, dynamic> json) {
    return ScriptLogLine(
      fileName: json['file_name']?.toString() ?? '',
      lineNo: _readInt(json['line_no']) ?? 0,
      offset: _readInt(json['offset']) ?? 0,
      byteLength: _readInt(json['byte_length']) ?? 0,
      text: json['text']?.toString() ?? '',
      lineTruncated: json['line_truncated'] == true,
    );
  }
}

/// A loaded script log window with history and live cursors.
class ScriptLogWindow {
  /// Creates one script log window.
  const ScriptLogWindow({
    required this.scriptName,
    required this.from,
    required this.to,
    required this.olderCursor,
    required this.liveCursor,
    required this.hasOlder,
    required this.reachedStart,
    required this.limits,
    required this.lines,
  });

  /// Normalized script name returned by backend.
  final String scriptName;

  /// First line position.
  final ScriptLogPosition? from;

  /// Last line position.
  final ScriptLogPosition? to;

  /// Cursor for loading older lines.
  final String? olderCursor;

  /// Cursor for subscribing live lines.
  final String liveCursor;

  /// Whether older lines still exist.
  final bool hasOlder;

  /// Whether the script log start has been reached.
  final bool reachedStart;

  /// Applied request limits.
  final ScriptLogWindowLimits limits;

  /// Lines ordered from old to new.
  final List<ScriptLogLine> lines;

  /// Builds a log window from JSON.
  factory ScriptLogWindow.fromJson(Map<String, dynamic> json) {
    final window = json['window'] as Map<String, dynamic>? ?? const {};
    final rawLines = json['lines'] as List? ?? const [];
    return ScriptLogWindow(
      scriptName: json['script_name']?.toString() ?? '',
      from: window['from'] is Map
          ? ScriptLogPosition.fromJson(
              (window['from'] as Map).cast<String, dynamic>(),
            )
          : null,
      to: window['to'] is Map
          ? ScriptLogPosition.fromJson(
              (window['to'] as Map).cast<String, dynamic>(),
            )
          : null,
      olderCursor: json['older_cursor'] as String?,
      liveCursor: json['live_cursor']?.toString() ?? '',
      hasOlder: json['has_older'] == true,
      reachedStart: json['reached_start'] == true,
      limits: ScriptLogWindowLimits.fromJson(
        json['limits'] as Map<String, dynamic>?,
      ),
      lines: rawLines
          .whereType<Map>()
          .map((item) => ScriptLogLine.fromJson(item.cast<String, dynamic>()))
          .toList(),
    );
  }
}

int? _readInt(dynamic value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return int.tryParse(value?.toString() ?? '');
}
