import 'dart:typed_data';

/// One error image metadata item.
class ScriptErrorImageInfo {
  /// Creates one image metadata item.
  const ScriptErrorImageInfo({
    required this.name,
    required this.size,
    required this.modifiedTime,
    required this.url,
  });

  /// Image file name.
  final String name;

  /// Image byte size.
  final int size;

  /// Image modified time.
  final String modifiedTime;

  /// Relative image URL.
  final String url;

  /// Builds image metadata from JSON.
  factory ScriptErrorImageInfo.fromJson(Map<String, dynamic> json) {
    return ScriptErrorImageInfo(
      name: json['name']?.toString() ?? '',
      size: _readInt(json['size']) ?? 0,
      modifiedTime: json['modified_time']?.toString() ?? '',
      url: json['url']?.toString() ?? '',
    );
  }
}

/// Downloaded binary image payload.
class ScriptErrorImageBytes {
  /// Creates one downloaded image payload.
  const ScriptErrorImageBytes({required this.fileName, required this.bytes});

  /// Suggested image file name.
  final String fileName;

  /// Downloaded PNG bytes.
  final Uint8List bytes;
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
