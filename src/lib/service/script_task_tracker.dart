/// A task in the scheduler's existing execution order.
class ScheduledScriptTask {
  const ScheduledScriptTask(this.name, this.nextRun);

  final String name;
  final String nextRun;
}

/// Tracks actual execution independently from legacy schedule candidates.
///
/// Older OAS servers call the selected queue head `schedule.running`, including
/// on reconnect while another task is executing. Scheduler log boundaries are
/// the source of truth for execution; schedule data supplies the upcoming queue.
class ScriptTaskTracker {
  bool isRunning = false;
  String currentTask = '';
  bool currentTaskKnown = false;
  int revision = 0;
  bool? _lastServerRunning;
  String _retryTask = '';
  List<ScheduledScriptTask> _pending = const [];
  List<ScheduledScriptTask> waiting = const [];

  static final _start = RegExp(r'Scheduler: Start task `([^`]+)`');
  static final _end = RegExp(r'Scheduler: End task `([^`]+)`');
  static final _incomplete = RegExp(r'Scheduler: task `([^`]+)` incomplete;');

  /// Does not infer a current task merely from a running process state.
  void setRunning(bool value) {
    if (isRunning == value && value) return;
    isRunning = value;
    currentTask = '';
    currentTaskKnown = !value;
    if (!value) _retryTask = '';
    revision++;
  }

  /// Only an initial running state can represent an already active process.
  bool observeServerRunning(bool value) {
    final previous = _lastServerRunning;
    final wasRunning = isRunning;
    _lastServerRunning = value;
    setRunning(value);
    return value && !wasRunning && previous != false;
  }

  void prepareFreshStart() {
    setRunning(false);
    _lastServerRunning = false;
    currentTaskKnown = false;
  }

  void connectionLost() {
    setRunning(false);
    _lastServerRunning = null;
  }

  void updateSchedule({
    ScheduledScriptTask? candidate,
    required List<ScheduledScriptTask> pending,
    required List<ScheduledScriptTask> waiting,
  }) {
    // Legacy get_next can leave self.task stale after moving it to waiting.
    final waitingNames = waiting.map((task) => task.name.trim()).toSet();
    _pending = [
      if (candidate != null && !waitingNames.contains(candidate.name.trim()))
        candidate,
      ...pending,
    ];
    this.waiting = waiting;
  }

  /// Keeps server order and recovers the queue head removed by legacy OAS.
  List<ScheduledScriptTask> get pending {
    final names = <String>{};
    final ordered = [
      if (_retryTask.isNotEmpty) ScheduledScriptTask(_retryTask, ''),
      ..._pending,
    ];
    return ordered.where((task) {
      final name = task.name.trim();
      return name.isNotEmpty && name != currentTask && names.add(name);
    }).toList();
  }

  bool consumeLog(String line) {
    if (!isRunning) return false;
    final boundary = _boundary(line);
    if (boundary == null) return false;
    if (!boundary.started &&
        boundary.name.isNotEmpty &&
        currentTask.isNotEmpty &&
        boundary.name != currentTask) {
      return false;
    }
    _applyBoundary(boundary);
    return true;
  }

  /// Applies the newest historical boundary only if live state did not change.
  /// Returns false when callers should continue to an older page.
  bool recoverFromHistory(
    Iterable<String> lines, {
    required int expectedRevision,
  }) {
    if (!isRunning || revision != expectedRevision) return true;
    for (final line in lines.toList().reversed) {
      final boundary = _boundary(line);
      if (boundary == null) continue;
      _applyBoundary(boundary);
      return true;
    }
    return false;
  }

  void _applyBoundary(_TaskBoundary boundary) {
    currentTask = boundary.started ? boundary.name : '';
    currentTaskKnown = true;
    if (boundary.started) {
      _retryTask = '';
    } else if (boundary.retry) {
      // OAS completion_gate blocks other tasks until this one is retried.
      _retryTask = boundary.name;
    } else if (boundary.name.isNotEmpty) {
      _pending = _pending.where((task) => task.name != boundary.name).toList();
      if (_retryTask == boundary.name) _retryTask = '';
    }
    revision++;
  }

  static _TaskBoundary? _boundary(String line) {
    final start = _start.firstMatch(line);
    if (start != null) {
      return _TaskBoundary(start.group(1)!.trim(), true);
    }
    final end = _end.firstMatch(line);
    if (end != null) return _TaskBoundary(end.group(1)!.trim(), false);
    final incomplete = _incomplete.firstMatch(line);
    if (incomplete != null) {
      return _TaskBoundary(incomplete.group(1)!.trim(), false, retry: true);
    }
    if (line.contains('Start scheduler loop:') ||
        line.contains('Scheduler entered task waiting state') ||
        line.contains('No task pending')) {
      return const _TaskBoundary('', false);
    }
    return null;
  }
}

class _TaskBoundary {
  const _TaskBoundary(this.name, this.started, {this.retry = false});

  final String name;
  final bool started;
  final bool retry;
}
