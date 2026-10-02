part of 'script_service.dart';

extension ScriptServiceWsX on ScriptService {
  Future<void> connectScript(String name) async {
    if (!scriptModelMap.containsKey(name)) {
      addScriptModel(name);
    }
    wsService.removeAllListeners(name);
    final client = await wsService.connect(
      name: name,
      listener: (mg) => wsListener(mg, name),
    );
    client.status.listen((wsStatus) {
      scriptModelMap[name]?.update(state: wsStatus.scriptState);
      if (wsStatus == WsStatus.closed ||
          wsStatus == WsStatus.error ||
          wsStatus == WsStatus.reconnecting) {
        _taskTrackers[name]?.connectionLost();
        _publishTrackedTasks(name);
      }
    });
    // _connect reports initial failures before this subscription is attached.
    if (client.status.value == WsStatus.closed ||
        client.status.value == WsStatus.error ||
        client.status.value == WsStatus.reconnecting) {
      _taskTrackers[name]?.connectionLost();
      _publishTrackedTasks(name);
    }
  }

  Future<void> startScript(String name) async {
    if (!scriptModelMap.containsKey(name)) return;
    if (isRunning(name)) return;
    final tracker = _taskTrackers.putIfAbsent(name, ScriptTaskTracker.new);
    tracker.prepareFreshStart();
    _publishTrackedTasks(name);
    try {
      await connectScript(name);
      await wsService.send(name, 'start');
    } catch (_) {
      tracker.connectionLost();
      _publishTrackedTasks(name);
      rethrow;
    }
  }

  void wsListener(dynamic message, String name) {
    if (message is! String) {
      printError(info: 'Websocket push data is not of type string and map');
      return;
    }
    final tracker = _taskTrackers.putIfAbsent(name, ScriptTaskTracker.new);
    if (!message.startsWith('{') || !message.endsWith('}')) {
      if (tracker.consumeLog(message)) _publishTrackedTasks(name);
      return;
    }
    final data = jsonDecode(message) as Map<String, dynamic>;
    if (data.containsKey('state')) {
      final state = ScriptState.getState(data['state']);
      final recover = tracker.observeServerRunning(
        state == ScriptState.running,
      );
      scriptModelMap[name]?.update(state: state);
      _publishTrackedTasks(name);
      if (recover) {
        unawaited(_recoverCurrentTask(name, tracker));
      }
    }
    if (!data.containsKey('schedule')) {
      return;
    }

    final schedule = data['schedule'];
    if (schedule is! Map) return;
    final run = _readScheduledTask(schedule['running']);
    tracker.updateSchedule(
      candidate: run,
      pending: _readScheduledTasks(schedule['pending']),
      waiting: _readScheduledTasks(schedule['waiting']),
      failed: schedule.containsKey('failed')
          ? _readScheduledTasks(schedule['failed']) : null,
    );
    _publishTrackedTasks(name);
  }

  ScheduledScriptTask? _readScheduledTask(dynamic value) {
    if (value is! Map) return null;
    final taskName = value['name']?.toString().trim() ?? '';
    if (taskName.isEmpty) return null;
    return ScheduledScriptTask(taskName, value['next_run']?.toString() ?? '',
        enabled: value['enabled'] != false);
  }

  List<ScheduledScriptTask> _readScheduledTasks(dynamic value) => value is List
      ? value.map(_readScheduledTask).whereType<ScheduledScriptTask>().toList()
      : const [];

  void _publishTrackedTasks(String name) {
    final tracker = _taskTrackers[name];
    final model = scriptModelMap[name];
    if (tracker == null || model == null) return;
    model.update(
      currentTaskKnown: tracker.currentTaskKnown,
      runningTask: tracker.currentTask.isEmpty
          ? TaskItemModel.empty()
          : TaskItemModel(name, tracker.currentTask, ''),
      pendingTaskList: tracker.pending
          .map((task) => TaskItemModel(name, task.name, task.nextRun))
          .toList(),
      failedTaskList: tracker.failed
          .map((task) => TaskItemModel(name, task.name, task.nextRun, enabled: task.enabled))
          .toList(),
      waitingTaskList: tracker.waiting
          .map((task) => TaskItemModel(name, task.name, task.nextRun))
          .toList(),
    );
  }

  /// Restores execution when the UI connects during a long-running task.
  Future<void> _recoverCurrentTask(
    String name,
    ScriptTaskTracker tracker,
  ) async {
    final token = (_taskRecoveryTokens[name] ?? 0) + 1;
    _taskRecoveryTokens[name] = token;
    final revision = tracker.revision;
    final watch = Stopwatch()..start();
    String? cursor;
    try {
      for (
        var page = 0;
        page < 8 && watch.elapsedMilliseconds < 10000;
        page++
      ) {
        if (!identical(_taskTrackers[name], tracker) ||
            _taskRecoveryTokens[name] != token ||
            !tracker.isRunning ||
            tracker.revision != revision) {
          return;
        }
        final window = await _taskHistoryLoader(
          name,
          cursor: cursor,
          limitLines: 2000,
          limitBytes: 1048576,
        ).timeout(const Duration(seconds: 2));
        if (!identical(_taskTrackers[name], tracker) ||
            _taskRecoveryTokens[name] != token ||
            !tracker.isRunning ||
            tracker.revision != revision) {
          return;
        }
        if (tracker.recoverFromHistory(
          window.lines.map((line) => line.text),
          expectedRevision: revision,
        )) {
          _publishTrackedTasks(name);
          return;
        }
        final older = window.olderCursor;
        if (window.reachedStart ||
            !window.hasOlder ||
            older == cursor ||
            older == null ||
            older.isEmpty) {
          return;
        }
        cursor = older;
      }
    } catch (error) {
      // Log history is optional on older servers; live boundaries still work.
      printInfo(info: 'ws[$name] current task history unavailable: $error');
    }
  }

  Future<void> stopScript(String name) async {
    if (!scriptModelMap.containsKey(name)) return;
    _taskTrackers[name]?.observeServerRunning(false);
    _publishTrackedTasks(name);
    await wsService.send(name, 'stop');
  }
}
