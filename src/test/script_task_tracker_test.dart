import 'package:flutter_test/flutter_test.dart';
import 'dart:convert';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:oasx/modules/log/log_browser_models.dart';
import 'package:oasx/service/script_service.dart';
import 'package:oasx/service/script_task_tracker.dart';
import 'package:oasx/service/websocket_service.dart';

void main() {
  late ScriptTaskTracker tracker;
  setUp(() {
    tracker = ScriptTaskTracker()..setRunning(true);
  });

  test('initial running state is unknown until a scheduler boundary', () {
    expect(tracker.currentTaskKnown, isFalse);
    tracker.consumeLog('No task pending');
    expect(tracker.currentTaskKnown, isTrue);
    expect(tracker.currentTask, isEmpty);
  });

  test('history idle is confirmed and a new session becomes unknown', () {
    tracker.recoverFromHistory([
      'Scheduler: End task `Duel`',
    ], expectedRevision: tracker.revision);
    expect(tracker.currentTaskKnown, isTrue);
    tracker.setRunning(false);
    tracker.setRunning(true);
    expect(tracker.currentTaskKnown, isFalse);
  });

  test('only connecting to an existing run requests historical recovery', () {
    final initial = ScriptTaskTracker();
    expect(initial.observeServerRunning(true), isTrue);
    initial.connectionLost();
    expect(initial.observeServerRunning(true), isTrue);
    initial.observeServerRunning(false);
    expect(initial.observeServerRunning(true), isFalse);
    initial.prepareFreshStart();
    expect(initial.observeServerRunning(true), isFalse);
  });

  test(
    'active fresh start does not resurrect a forcibly stopped old task',
    () async {
      Get.testMode = true;
      Get.put<WebSocketService>(_StartOnlyWebSocketService());
      addTearDown(Get.reset);
      var historyRequests = 0;
      final service = ScriptService(
        storage: _UnusedStorage(),
        taskHistoryLoader:
            (name, {cursor, required limitLines, required limitBytes}) async {
              historyRequests++;
              return _historyWindow('Scheduler: Start task `OldTask`');
            },
      );
      service.addScriptModel('tomoe');
      await service.startScript('tomoe');
      await Future<void>.delayed(Duration.zero);
      expect(historyRequests, 0);
      expect(
        service.findScriptModel('tomoe')!.runningTask.value.taskName.value,
        isEmpty,
      );
      service.wsListener('Scheduler: Start task `Duel`', 'tomoe');
      expect(
        service.findScriptModel('tomoe')!.runningTask.value.taskName.value,
        'Duel',
      );
    },
  );

  test(
    'initial connection to a running process still restores its task',
    () async {
      Get.testMode = true;
      Get.put(WebSocketService());
      addTearDown(Get.reset);
      var historyRequests = 0;
      final service = ScriptService(
        storage: _UnusedStorage(),
        taskHistoryLoader:
            (name, {cursor, required limitLines, required limitBytes}) async {
              historyRequests++;
              return _historyWindow('Scheduler: Start task `Duel`');
            },
      );
      service.addScriptModel('tomoe');
      service.wsListener(jsonEncode({'state': 1}), 'tomoe');
      await Future<void>.delayed(Duration.zero);
      expect(historyRequests, 1);
      expect(
        service.findScriptModel('tomoe')!.runningTask.value.taskName.value,
        'Duel',
      );
    },
  );

  test(
    'confirmed inactive to running transition does not read old history',
    () async {
      Get.testMode = true;
      Get.put(WebSocketService());
      addTearDown(Get.reset);
      var historyRequests = 0;
      final service = ScriptService(
        storage: _UnusedStorage(),
        taskHistoryLoader:
            (name, {cursor, required limitLines, required limitBytes}) async {
              historyRequests++;
              return _historyWindow('Scheduler: Start task `OldTask`');
            },
      );
      service.addScriptModel('tomoe');
      service.wsListener(jsonEncode({'state': 0}), 'tomoe');
      service.wsListener(jsonEncode({'state': 1}), 'tomoe');
      await Future<void>.delayed(Duration.zero);
      expect(historyRequests, 0);
      expect(
        service.findScriptModel('tomoe')!.runningTask.value.taskName.value,
        isEmpty,
      );
    },
  );

  test(
    'WebSocket listener publishes actual current and queued next separately',
    () async {
      Get.testMode = true;
      Get.put(WebSocketService());
      final service = ScriptService(
        storage: _UnusedStorage(),
        taskHistoryLoader:
            (name, {cursor, required limitLines, required limitBytes}) async =>
                const ScriptLogWindow(
                  scriptName: 'tomoe',
                  from: null,
                  to: null,
                  olderCursor: null,
                  liveCursor: '',
                  hasOlder: false,
                  reachedStart: true,
                  limits: ScriptLogWindowLimits(
                    limitLines: 2000,
                    limitBytes: 1048576,
                    maxLineBytes: 4096,
                  ),
                  lines: [],
                ),
      );
      service.addScriptModel('tomoe');
      final schedule = {
        'running': {'name': 'FrogBoss', 'next_run': '2026-09-29 20:15:59'},
        'pending': [
          {'name': 'RyouToppa', 'next_run': '2026-09-30 21:41:40'},
        ],
        'waiting': [],
      };
      service.wsListener(
        jsonEncode({'state': 1, 'schedule': schedule}),
        'tomoe',
      );
      service.wsListener(
        'INFO | 2026-09-30 21:35:09 | Scheduler: Start task `Duel`',
        'tomoe',
      );
      service.wsListener(jsonEncode({'schedule': schedule}), 'tomoe');
      await Future<void>.delayed(Duration.zero);
      final model = service.findScriptModel('tomoe')!;
      expect(model.runningTask.value.taskName.value, 'Duel');
      expect(model.currentTaskKnown.value, isTrue);
      expect(model.pendingTaskList.first.taskName.value, 'FrogBoss');
      service.wsListener('Scheduler: End task `Duel`', 'tomoe');
      expect(model.runningTask.value.taskName.value, isEmpty);
      expect(model.currentTaskKnown.value, isTrue);
      service.wsListener(jsonEncode({'state': 0}), 'tomoe');
      service.wsListener('Scheduler: Start task `FrogBoss`', 'tomoe');
      expect(model.runningTask.value.taskName.value, isEmpty);
      Get.reset();
    },
  );

  test('a queued candidate is not the current execution', () {
    tracker.updateSchedule(
      candidate: const ScheduledScriptTask('FrogBoss', '2026-09-29 20:15:59'),
      pending: const [ScheduledScriptTask('RyouToppa', '')],
      waiting: const [],
    );
    expect(tracker.currentTask, isEmpty);
    expect(tracker.pending.map((task) => task.name), ['FrogBoss', 'RyouToppa']);
  });

  test('live task start overrides an unrelated legacy running candidate', () {
    tracker.consumeLog(
      'INFO | 2026-09-30 21:35:09 | Scheduler: Start task `Duel`',
    );
    tracker.updateSchedule(
      candidate: const ScheduledScriptTask('FrogBoss', ''),
      pending: const [
        ScheduledScriptTask('Duel', ''),
        ScheduledScriptTask('RyouToppa', ''),
      ],
      waiting: const [],
    );
    expect(tracker.currentTask, 'Duel');
    expect(tracker.pending.map((task) => task.name), ['FrogBoss', 'RyouToppa']);
  });

  test('pending preserves server order and removes duplicate names', () {
    tracker.updateSchedule(
      candidate: const ScheduledScriptTask(
        'PriorityTask',
        '2026-10-01 12:00:00',
      ),
      pending: const [
        ScheduledScriptTask('PriorityTask', ''),
        ScheduledScriptTask('OlderTask', '2026-09-28 00:00:00'),
      ],
      waiting: const [],
    );
    expect(tracker.pending.map((task) => task.name), [
      'PriorityTask',
      'OlderTask',
    ]);
  });

  test('the current candidate is excluded from the upcoming queue', () {
    tracker.consumeLog('Scheduler: Start task `Duel`');
    tracker.updateSchedule(
      candidate: const ScheduledScriptTask('Duel', ''),
      pending: const [ScheduledScriptTask('FrogBoss', '')],
      waiting: const [ScheduledScriptTask('GoldYoukai', '2026-10-01 00:00:00')],
    );
    expect(tracker.pending.single.name, 'FrogBoss');
    expect(tracker.waiting.single.name, 'GoldYoukai');
  });

  test('task end clears current and removes stale queued copy', () {
    tracker.updateSchedule(
      candidate: const ScheduledScriptTask('Duel', ''),
      pending: const [],
      waiting: const [],
    );
    tracker.consumeLog('Scheduler: Start task `Duel`');
    tracker.consumeLog('Scheduler: End task `Duel`');
    expect(tracker.currentTask, isEmpty);
    expect(tracker.pending, isEmpty);
  });

  test('late unrelated end does not clear a newer current task', () {
    tracker.consumeLog('Scheduler: Start task `Duel`');
    expect(tracker.consumeLog('Scheduler: End task `FrogBoss`'), isFalse);
    expect(tracker.currentTask, 'Duel');
  });

  test('an incomplete task has stopped executing', () {
    tracker.consumeLog('Scheduler: Start task `Duel`');
    tracker.consumeLog(
      'Scheduler: task `Duel` incomplete; next task is blocked',
    );
    expect(tracker.currentTask, isEmpty);
    expect(tracker.pending.single.name, 'Duel');
  });

  test(
    'incomplete task stays first while unrelated schedule candidates arrive',
    () {
      tracker.consumeLog('Scheduler: Start task `Duel`');
      tracker.consumeLog(
        'Scheduler: task `Duel` incomplete; next task is blocked',
      );
      tracker.updateSchedule(
        candidate: const ScheduledScriptTask('FrogBoss', ''),
        pending: const [ScheduledScriptTask('RyouToppa', '')],
        waiting: const [],
      );
      tracker.consumeLog('Start scheduler loop: tomoe');
      expect(tracker.currentTask, isEmpty);
      expect(tracker.pending.map((task) => task.name), [
        'Duel',
        'FrogBoss',
        'RyouToppa',
      ]);
      tracker.consumeLog('Scheduler: Start task `Duel`');
      expect(tracker.pending.map((task) => task.name), [
        'FrogBoss',
        'RyouToppa',
      ]);
    },
  );

  test('historical incomplete boundary restores the retry as next', () {
    tracker.updateSchedule(
      candidate: const ScheduledScriptTask('FrogBoss', ''),
      pending: const [],
      waiting: const [],
    );
    tracker.recoverFromHistory([
      'Scheduler: Start task `Duel`',
      'Scheduler: task `Duel` incomplete; next task is blocked',
    ], expectedRevision: tracker.revision);
    expect(tracker.currentTask, isEmpty);
    expect(tracker.pending.map((task) => task.name), ['Duel', 'FrogBoss']);
    tracker.setRunning(false);
    expect(tracker.pending.single.name, 'FrogBoss');
  });

  test(
    'rescheduled legacy candidate does not outrank the next waiting task',
    () {
      tracker.updateSchedule(
        candidate: const ScheduledScriptTask('Duel', '2026-09-30 21:00:00'),
        pending: const [],
        waiting: const [
          ScheduledScriptTask('GoldYoukai', '2026-10-01 00:00:00'),
          ScheduledScriptTask('Duel', '2026-10-01 10:00:00'),
        ],
      );
      expect(tracker.pending, isEmpty);
      expect(tracker.waiting.first.name, 'GoldYoukai');
    },
  );

  test('scheduler idle clears execution but battle waiting does not', () {
    tracker.consumeLog('Scheduler: Start task `Duel`');
    tracker.consumeLog('<<< DUEL BATTLE WAITING >>>');
    expect(tracker.currentTask, 'Duel');
    tracker.consumeLog(
      'Scheduler entered task waiting state; reset continuous task timer',
    );
    expect(tracker.currentTask, isEmpty);
  });

  test('stopped scripts ignore buffered start logs', () {
    tracker.consumeLog('Scheduler: Start task `Duel`');
    tracker.setRunning(false);
    expect(tracker.consumeLog('Scheduler: Start task `FrogBoss`'), isFalse);
    expect(tracker.currentTask, isEmpty);
  });

  test('history recovers the latest boundary from file log format', () {
    expect(
      tracker.recoverFromHistory([
        '2026-09-30 21:20:00 | script.py:706 | INFO | Scheduler: Start task `Duel`',
        '2026-09-30 21:35:09 | script.py:706 | INFO | Scheduler: Start task `FrogBoss`',
        '2026-09-30 21:35:10 | INFO | Click result captured',
      ], expectedRevision: tracker.revision),
      isTrue,
    );
    expect(tracker.currentTask, 'FrogBoss');
  });

  test('history end does not resurrect a completed task', () {
    tracker.recoverFromHistory([
      'Scheduler: Start task `Duel`',
      'Scheduler: End task `Duel`',
    ], expectedRevision: tracker.revision);
    expect(tracker.currentTask, isEmpty);
  });

  test('history without a boundary asks for an older page', () {
    expect(
      tracker.recoverFromHistory([
        'Click result',
        'Battle waiting',
      ], expectedRevision: tracker.revision),
      isFalse,
    );
    expect(tracker.currentTask, isEmpty);
  });

  test('live boundary arriving during history fetch wins', () {
    final revision = tracker.revision;
    tracker.consumeLog('Scheduler: Start task `FrogBoss`');
    tracker.recoverFromHistory([
      'Scheduler: Start task `Duel`',
    ], expectedRevision: revision);
    expect(tracker.currentTask, 'FrogBoss');
  });

  test('stopping during history fetch prevents stale recovery', () {
    final revision = tracker.revision;
    tracker.setRunning(false);
    tracker.recoverFromHistory([
      'Scheduler: Start task `Duel`',
    ], expectedRevision: revision);
    expect(tracker.currentTask, isEmpty);
  });
}

class _UnusedStorage implements GetStorage {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected storage access: ${invocation.memberName}');
}

ScriptLogWindow _historyWindow(String line) => ScriptLogWindow(
  scriptName: 'tomoe',
  from: null,
  to: null,
  olderCursor: null,
  liveCursor: '',
  hasOlder: false,
  reachedStart: true,
  limits: const ScriptLogWindowLimits(
    limitLines: 2000,
    limitBytes: 1048576,
    maxLineBytes: 4096,
  ),
  lines: [
    ScriptLogLine(
      fileName: 'test.txt',
      lineNo: 1,
      offset: 0,
      byteLength: line.length,
      text: line,
      lineTruncated: false,
    ),
  ],
);

class _StartOnlyWebSocketService extends WebSocketService {
  MessageListener? _listener;

  @override
  Future<WebSocketClient> connect({
    required String name,
    String? url,
    MessageListener? listener,
    bool force = false,
  }) async {
    _listener = listener;
    return WebSocketClient(name: name, url: 'ws://unused');
  }

  @override
  Future<void> send(String name, String message) async {
    if (message == 'start') _listener?.call(jsonEncode({'state': 1}));
  }
}
