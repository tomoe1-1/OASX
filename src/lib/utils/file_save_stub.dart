import 'dart:typed_data';

import 'package:flutter/foundation.dart' show TargetPlatform;

/// No-op writer for platforms where direct file paths are unavailable.
Future<void> saveBytesToPath(String path, Uint8List bytes) async {}

/// Returns whether a picked save path should be written with dart:io.
bool shouldWritePickedSavePath({TargetPlatform? platform}) => false;
