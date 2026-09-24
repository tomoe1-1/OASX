import 'package:flutter_test/flutter_test.dart';
import 'package:oasx/modules/log/script_log_browser_controller.dart';

void main() {
  test('parseScriptErrorLogPayload splits lines and trims trailing breaks', () {
    const content = 'INFO line\r\nERROR line\r\n\r\n';
    final payload = parseScriptErrorLogPayload(content);

    expect(payload.lines, <String>['INFO line', 'ERROR line']);
    expect(payload.maxWidthScore > 0, isTrue);
  });

  test('plain text threshold keeps large single line detectable', () {
    final content = 'A' * (kErrorLogPlainTextThreshold + 5);
    final payload = parseScriptErrorLogPayload(content);

    expect(payload.lines, <String>[content]);
    expect(payload.maxWidthScore, content.length);
  });
}
