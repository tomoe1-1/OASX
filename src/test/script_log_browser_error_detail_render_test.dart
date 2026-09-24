import 'package:flutter_test/flutter_test.dart';
import 'package:oasx/modules/log/log_browser_models.dart';
import 'package:oasx/modules/log/script_log_browser_controller.dart';

void main() {
  test('prepareSelectedErrorLog fills lines and clears loading flags', () async {
    final controller = ScriptLogBrowserController(scriptName: 'demo');
    const detail = ScriptErrorLogDetail(
      id: 'error-1',
      directory: '20260601',
      scriptName: 'demo',
      timestampMs: 0,
      time: '2026-06-01 12:00:00',
      legacy: false,
      log: ScriptErrorLogText(
        fileName: 'log.txt',
        content: 'line-1\nline-2\n',
        size: 14,
        limitBytes: 262144,
        truncated: false,
      ),
      images: <ScriptErrorImageInfo>[],
    );

    controller.selectedErrorId.value = detail.id;
    controller.errorDetailVisible.value = true;
    controller.errorLogPreparing.value = true;

    await controller.prepareSelectedErrorLog(detail: detail, renderToken: 0);

    expect(controller.selectedErrorLogLines, <String>['line-1', 'line-2']);
    expect(controller.selectedErrorLogMaxWidthScore.value, greaterThan(0));
    expect(controller.errorLogPreparing.value, isFalse);
    expect(controller.errorLogAppending.value, isFalse);
    expect(controller.errorMessage.value, isEmpty);
  });

  test('prepareSelectedErrorLog handles empty content without loading residue',
      () async {
    final controller = ScriptLogBrowserController(scriptName: 'demo');
    const detail = ScriptErrorLogDetail(
      id: 'error-2',
      directory: '20260601',
      scriptName: 'demo',
      timestampMs: 0,
      time: '2026-06-01 12:00:01',
      legacy: false,
      log: ScriptErrorLogText(
        fileName: 'log.txt',
        content: '',
        size: 0,
        limitBytes: 262144,
        truncated: false,
      ),
      images: <ScriptErrorImageInfo>[],
    );

    controller.selectedErrorId.value = detail.id;
    controller.errorDetailVisible.value = true;
    controller.errorLogPreparing.value = true;

    await controller.prepareSelectedErrorLog(detail: detail, renderToken: 0);

    expect(controller.selectedErrorLogLines, isEmpty);
    expect(controller.selectedErrorLogMaxWidthScore.value, 0);
    expect(controller.errorLogPreparing.value, isFalse);
    expect(controller.errorLogAppending.value, isFalse);
    expect(controller.errorMessage.value, isEmpty);
  });
}
