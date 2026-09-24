import 'package:flutter_test/flutter_test.dart';
import 'package:oasx/modules/home/models/script_analysis_models.dart';
import 'package:oasx/modules/log/log_browser_models.dart';

ScriptLogLine line(
  int number,
  String text, {
  String fileName = '2026-09-03_demo.txt',
}) =>
    ScriptLogLine(
      fileName: fileName,
      lineNo: number,
      offset: number * 100,
      byteLength: text.length,
      text: text,
      lineTruncated: false,
    );

void main() {
  test('parses clicks, swipes, tasks, and four-hour click density', () {
    final result = parseScriptAnalysis([
      line(1, '2026-09-03 08:24:44.378 | logger.py | INFO | [Task] AreaBoss (Enable, 5, now)'),
      line(2, '2026-09-03 08:25:05.667 | control.py | INFO | [0.05s] Click ( 664,  409) @ SAFE_RANDOM_CLICK'),
      line(3, '2026-09-03 08:25:20.000 | control.py | INFO | [0.05s] Click ( 100,  200) @ CONFIRM'),
      line(4, '2026-09-03 08:26:20.000 | control.py | INFO | [0.20s] Swipe (100, 200) -> (300, 400)'),
      line(
        5,
        '2026-09-02 08:26:20.000 | control.py | INFO | [0.05s] Click (1, 2) @ OLD',
        fileName: '2026-09-02_demo.txt',
      ),
    ], '2026-09-03');

    expect(result.clickCount, 2);
    expect(result.randomClickCount, 1);
    expect(result.taskCount, 1);
    expect(result.clicksByTask['AreaBoss'], 2);
    expect(result.events.last.kind, ScriptActionKind.swipe);
    expect(result.clicksPerFourHours, [0, 0, 2, 0, 0, 0]);
    expect(result.randomClicksPerFourHours, [0, 0, 1, 0, 0, 0]);
  });

  test('parses compact timestamps returned by the log API', () {
    final result = parseScriptAnalysis([
      line(
        1,
        '09-03 12:46:12.194 |     INFO | [Task] KekkaiUtilize (Enable, 2, now)',
      ),
      line(
        2,
        '09-03 12:46:13.224 |     INFO | [0.05s] Click ( 579,  628) @ PAGE_MAIN_GOTO_GUILD',
      ),
      line(
        3,
        '09-03 12:46:20.989 |     INFO | [0.35s] Swipe ( 175,  180) -> ( 184,  518)',
      ),
    ], '2026-09-03');

    expect(result.events, hasLength(2));
    expect(result.clicksByTask['KekkaiUtilize'], 1);
    expect(result.events.first.time.year, 2026);
    expect(result.events.last.kind, ScriptActionKind.swipe);
  });
}
