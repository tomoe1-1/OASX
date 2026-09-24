import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;

/// Writes downloaded bytes to a local path on IO platforms.
Future<void> saveBytesToPath(String path, Uint8List bytes) async {
  await File(path).writeAsBytes(bytes);
}

/// Returns whether a picked save path should be written with dart:io.
bool shouldWritePickedSavePath({TargetPlatform? platform}) {
  final targetPlatform = platform ?? defaultTargetPlatform;
  return targetPlatform != TargetPlatform.android &&
      targetPlatform != TargetPlatform.iOS;
}
