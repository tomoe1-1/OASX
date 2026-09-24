import 'package:flutter/foundation.dart' show TargetPlatform;
import 'package:flutter_test/flutter_test.dart';
import 'package:oasx/utils/file_save_io.dart';

void main() {
  group('shouldWritePickedSavePath', () {
    test('skips direct file writes on mobile platforms', () {
      expect(
        shouldWritePickedSavePath(platform: TargetPlatform.android),
        isFalse,
      );
      expect(shouldWritePickedSavePath(platform: TargetPlatform.iOS), isFalse);
    });

    test('keeps direct file writes on desktop platforms', () {
      expect(
        shouldWritePickedSavePath(platform: TargetPlatform.windows),
        isTrue,
      );
      expect(shouldWritePickedSavePath(platform: TargetPlatform.macOS), isTrue);
      expect(shouldWritePickedSavePath(platform: TargetPlatform.linux), isTrue);
      expect(
        shouldWritePickedSavePath(platform: TargetPlatform.fuchsia),
        isTrue,
      );
    });
  });
}
