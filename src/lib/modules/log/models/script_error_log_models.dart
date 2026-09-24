import 'package:oasx/modules/log/models/script_error_image_models.dart';

/// One error log list item.
class ScriptErrorLogItem {
  /// Creates one error list item.
  const ScriptErrorLogItem({
    required this.id,
    required this.directory,
    required this.scriptName,
    required this.timestampMs,
    required this.time,
    required this.legacy,
    required this.logSize,
    required this.imageCount,
  });

  /// Error id used by detail endpoints.
  final String id;

  /// Error directory name.
  final String directory;

  /// Script name if the directory uses the new format.
  final String? scriptName;

  /// Millisecond timestamp.
  final int timestampMs;

  /// Local ISO time text.
  final String time;

  /// Whether the item comes from legacy directory format.
  final bool legacy;

  /// Error log text size.
  final int logSize;

  /// Number of available PNG images.
  final int imageCount;

  /// Builds an error item from JSON.
  factory ScriptErrorLogItem.fromJson(Map<String, dynamic> json) {
    return ScriptErrorLogItem(
      id: json['id']?.toString() ?? '',
      directory: json['directory']?.toString() ?? '',
      scriptName: json['script_name'] as String?,
      timestampMs: _readInt(json['timestamp_ms']) ?? 0,
      time: json['time']?.toString() ?? '',
      legacy: json['legacy'] == true,
      logSize: _readInt(json['log_size']) ?? 0,
      imageCount: _readInt(json['image_count']) ?? 0,
    );
  }
}

/// Paginated error log list response.
class ScriptErrorLogList {
  /// Creates one error list page.
  const ScriptErrorLogList({
    required this.date,
    required this.scriptName,
    required this.items,
    required this.nextCursor,
    required this.hasMore,
  });

  /// Queried date.
  final String date;

  /// Queried script filter.
  final String? scriptName;

  /// Error items in this page.
  final List<ScriptErrorLogItem> items;

  /// Cursor for the next page.
  final String? nextCursor;

  /// Whether another page exists.
  final bool hasMore;

  /// Builds an error list from JSON.
  factory ScriptErrorLogList.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'] as List? ?? const [];
    return ScriptErrorLogList(
      date: json['date']?.toString() ?? '',
      scriptName: json['script_name'] as String?,
      items: rawItems
          .whereType<Map>()
          .map(
            (item) => ScriptErrorLogItem.fromJson(item.cast<String, dynamic>()),
          )
          .toList(),
      nextCursor: json['next_cursor'] as String?,
      hasMore: json['has_more'] == true,
    );
  }
}

/// Error log text payload.
class ScriptErrorLogText {
  /// Creates one error log text payload.
  const ScriptErrorLogText({
    required this.fileName,
    required this.content,
    required this.size,
    required this.limitBytes,
    required this.truncated,
  });

  /// Text file name.
  final String fileName;

  /// Error log content.
  final String content;

  /// Raw file size.
  final int size;

  /// Applied read limit.
  final int limitBytes;

  /// Whether content was truncated.
  final bool truncated;

  /// Builds error text from JSON.
  factory ScriptErrorLogText.fromJson(Map<String, dynamic>? json) {
    return ScriptErrorLogText(
      fileName: json?['file_name']?.toString() ?? 'log.txt',
      content: json?['content']?.toString() ?? '',
      size: _readInt(json?['size']) ?? 0,
      limitBytes: _readInt(json?['limit_bytes']) ?? 0,
      truncated: json?['truncated'] == true,
    );
  }
}

/// Full error log detail.
class ScriptErrorLogDetail {
  /// Creates one error detail.
  const ScriptErrorLogDetail({
    required this.id,
    required this.directory,
    required this.scriptName,
    required this.timestampMs,
    required this.time,
    required this.legacy,
    required this.log,
    required this.images,
  });

  /// Error id.
  final String id;

  /// Error directory.
  final String directory;

  /// Script name if present.
  final String? scriptName;

  /// Error timestamp.
  final int timestampMs;

  /// Error time text.
  final String time;

  /// Whether legacy directory format was used.
  final bool legacy;

  /// Error log text.
  final ScriptErrorLogText log;

  /// Error image metadata.
  final List<ScriptErrorImageInfo> images;

  /// Builds error detail from JSON.
  factory ScriptErrorLogDetail.fromJson(Map<String, dynamic> json) {
    final rawImages = json['images'] as List? ?? const [];
    return ScriptErrorLogDetail(
      id: json['id']?.toString() ?? '',
      directory: json['directory']?.toString() ?? '',
      scriptName: json['script_name'] as String?,
      timestampMs: _readInt(json['timestamp_ms']) ?? 0,
      time: json['time']?.toString() ?? '',
      legacy: json['legacy'] == true,
      log: ScriptErrorLogText.fromJson(json['log'] as Map<String, dynamic>?),
      images: rawImages
          .whereType<Map>()
          .map(
            (item) =>
                ScriptErrorImageInfo.fromJson(item.cast<String, dynamic>()),
          )
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
