import 'package:oasx/modules/log/log_browser_models.dart';

enum ScriptActionKind { click, swipe }

class ScriptActionEvent {
  const ScriptActionEvent({
    required this.time,
    required this.kind,
    required this.startX,
    required this.startY,
    required this.endX,
    required this.endY,
    required this.task,
    required this.control,
  });

  final DateTime time;
  final ScriptActionKind kind;
  final double startX;
  final double startY;
  final double endX;
  final double endY;
  final String task;
  final String control;

  bool get isRandomClick =>
      kind == ScriptActionKind.click && control.toLowerCase().contains('random');
}

class ScriptAnalysisSnapshot {
  const ScriptAnalysisSnapshot(this.events);

  final List<ScriptActionEvent> events;

  int get clickCount =>
      events.where((event) => event.kind == ScriptActionKind.click).length;
  int get randomClickCount => events.where((event) => event.isRandomClick).length;
  int get taskCount => clicksByTask.length;

  Map<String, int> get clicksByTask {
    final values = <String, int>{};
    for (final event in events.where((e) => e.kind == ScriptActionKind.click)) {
      values.update(event.task, (value) => value + 1, ifAbsent: () => 1);
    }
    return values;
  }

  List<int> get clicksPerFourHours {
    return _clicksPerFourHours(
      events.where((event) => event.kind == ScriptActionKind.click),
    );
  }

  List<int> get randomClicksPerFourHours {
    return _clicksPerFourHours(events.where((event) => event.isRandomClick));
  }

  List<int> _clicksPerFourHours(Iterable<ScriptActionEvent> source) {
    final values = List<int>.filled(6, 0);
    for (final event in source) {
      values[event.time.hour ~/ 4]++;
    }
    return values;
  }
}

ScriptAnalysisSnapshot parseScriptAnalysis(
  Iterable<ScriptLogLine> lines,
  String dateKey,
) {
  final fullTimestamp = RegExp(
    r'^(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{3})',
  );
  final compactTimestamp = RegExp(
    r'^(\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{3})',
  );
  final taskPattern = RegExp(r'\[Task\]\s+([A-Za-z0-9_]+)\s+\(');
  final clickPattern = RegExp(r'Click\s+\(\s*(\d+),\s*(\d+)\)\s+@\s+(.+?)\s*$');
  final swipePattern = RegExp(
    r'Swipe\s+\(\s*(\d+),\s*(\d+)\)\s*->\s*\(\s*(\d+),\s*(\d+)\)',
  );
  var task = 'Unknown';
  final events = <ScriptActionEvent>[];
  for (final line in lines) {
    final fileDate = line.fileName.length >= 10
        ? line.fileName.substring(0, 10)
        : '';
    if (fileDate != dateKey) continue;
    final taskMatch = taskPattern.firstMatch(line.text);
    if (taskMatch != null) task = taskMatch.group(1)!;
    final fullTimeMatch = fullTimestamp.firstMatch(line.text);
    final compactTimeMatch = compactTimestamp.firstMatch(line.text);
    final timestampText = fullTimeMatch?.group(1) ??
        (compactTimeMatch == null
            ? null
            : '${dateKey.substring(0, 4)}-${compactTimeMatch.group(1)}');
    final time = timestampText == null
        ? null
        : DateTime.tryParse(timestampText.replaceFirst(' ', 'T'));
    if (time == null) continue;
    final click = clickPattern.firstMatch(line.text);
    if (click != null) {
      events.add(ScriptActionEvent(
        time: time,
        kind: ScriptActionKind.click,
        startX: double.parse(click.group(1)!),
        startY: double.parse(click.group(2)!),
        endX: double.parse(click.group(1)!),
        endY: double.parse(click.group(2)!),
        task: task,
        control: click.group(3)!.trim(),
      ));
      continue;
    }
    final swipe = swipePattern.firstMatch(line.text);
    if (swipe != null) {
      events.add(ScriptActionEvent(
        time: time,
        kind: ScriptActionKind.swipe,
        startX: double.parse(swipe.group(1)!),
        startY: double.parse(swipe.group(2)!),
        endX: double.parse(swipe.group(3)!),
        endY: double.parse(swipe.group(4)!),
        task: task,
        control: 'Swipe',
      ));
    }
  }
  return ScriptAnalysisSnapshot(events);
}
