part of 'script_log_browser_controller.dart';

extension ScriptLogBrowserErrorDetailRenderX on ScriptLogBrowserController {
  /// Clears the current selected error render state.
  void resetSelectedErrorRenderState() {
    selectedErrorLogLines.clear();
    selectedErrorLogMaxWidthScore.value = 0;
    errorLogPreparing.value = false;
    errorLogAppending.value = false;
  }

  /// Cancels any stale selected error render work.
  void cancelSelectedErrorRenderWork() {
    _errorDetailRenderToken++;
    resetSelectedErrorRenderState();
  }

  /// Starts the deferred log preparation after the detail frame is shown.
  void scheduleSelectedErrorLogPreparation({
    required ScriptErrorLogDetail detail,
    required int renderToken,
  }) {
    errorLogPreparing.value = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!isSelectedErrorRenderActive(detail.id, renderToken)) {
        return;
      }
      unawaited(
        prepareSelectedErrorLog(detail: detail, renderToken: renderToken),
      );
    });
  }

  /// Parses and progressively appends the selected error log lines.
  Future<void> prepareSelectedErrorLog({
    required ScriptErrorLogDetail detail,
    required int renderToken,
  }) async {
    try {
      final payload = await _runErrorLogParser(
        () => parseScriptErrorLogPayload(detail.log.content),
      );
      if (!isSelectedErrorRenderActive(detail.id, renderToken)) {
        return;
      }
      final lines = payload.lines;
      final initialCount = lines.length < _errorLogInitialBatchSize
          ? lines.length
          : _errorLogInitialBatchSize;
      selectedErrorLogMaxWidthScore.value = payload.maxWidthScore;
      selectedErrorLogLines.assignAll(lines.take(initialCount));
      errorLogPreparing.value = false;
      if (initialCount >= lines.length) {
        errorLogAppending.value = false;
        return;
      }
      errorLogAppending.value = true;
      await appendSelectedErrorLogBatches(
        detailId: detail.id,
        renderToken: renderToken,
        lines: lines,
        startIndex: initialCount,
      );
    } catch (error) {
      if (!isSelectedErrorRenderActive(detail.id, renderToken)) {
        return;
      }
      errorLogPreparing.value = false;
      errorLogAppending.value = false;
      errorMessage.value = error.toString();
    }
  }

  /// Appends remaining error log lines in UI-friendly batches.
  Future<void> appendSelectedErrorLogBatches({
    required String detailId,
    required int renderToken,
    required List<String> lines,
    required int startIndex,
  }) async {
    var index = startIndex;
    while (index < lines.length) {
      if (!isSelectedErrorRenderActive(detailId, renderToken)) {
        return;
      }
      final end = (index + _errorLogAppendBatchSize).clamp(0, lines.length);
      selectedErrorLogLines.addAll(lines.sublist(index, end));
      index = end;
      await Future<void>.delayed(Duration.zero);
    }
    if (isSelectedErrorRenderActive(detailId, renderToken)) {
      errorLogAppending.value = false;
    }
  }

  /// Returns whether the selected error render work is still current.
  bool isSelectedErrorRenderActive(String detailId, int renderToken) {
    return !isClosed &&
        _errorDetailRenderToken == renderToken &&
        selectedErrorId.value == detailId &&
        errorDetailVisible.value;
  }

  /// Runs one error-log parser off the UI isolate when supported.
  Future<T> _runErrorLogParser<T>(T Function() parser) {
    if (kIsWeb) {
      return Future<T>.value(parser());
    }
    return Isolate.run(parser);
  }
}
