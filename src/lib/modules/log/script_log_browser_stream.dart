part of 'script_log_browser_controller.dart';

extension ScriptLogBrowserStreamX on ScriptLogBrowserController {
  /// Starts the live info log stream.
  Future<void> startStream(int requestId) async {
    if (!isRequestActive(requestId)) {
      return;
    }
    final uri = ApiClient().buildScriptLogStreamUri(
      scriptName,
      cursor: liveCursor,
      limitLines: kAutoScrollLogWindowLineLimit,
    );
    streamClient = ApiSseClient(
      url: uri,
      onEvent: handleStreamEvent,
      onStateChanged: handleStreamState,
    );
    unawaited(streamClient?.connect());
  }

  /// Stops the current live stream.
  Future<void> stopStream() async {
    final client = streamClient;
    streamClient = null;
    streamStatus.value = ScriptLogStreamStatus.idle;
    unawaited(client?.dispose());
  }

  /// Updates stream status from the generic SSE client.
  void handleStreamState(ApiSseConnectionState state, String? message) {
    streamStatus.value = switch (state) {
      ApiSseConnectionState.connecting => ScriptLogStreamStatus.connecting,
      ApiSseConnectionState.connected => ScriptLogStreamStatus.connected,
      ApiSseConnectionState.reconnecting => ScriptLogStreamStatus.reconnecting,
      ApiSseConnectionState.error => ScriptLogStreamStatus.error,
    };
    if (message != null && message.trim().isNotEmpty) {
      infoError.value = message;
    }
  }

  /// Parses one SSE event.
  void handleStreamEvent(ApiSseEvent event) {
    final payload = event.data.trim();
    if (payload.isEmpty) {
      return;
    }
    try {
      final data = jsonDecode(payload) as Map<String, dynamic>;
      switch (event.name.trim()) {
        case 'ready':
        case 'heartbeat':
        case 'rotate':
          updateLiveCursor(data['cursor']);
          break;
        case 'append':
          appendLiveLines(data);
          break;
        case 'error':
          infoError.value = data['message']?.toString() ?? payload;
          streamStatus.value = ScriptLogStreamStatus.error;
          break;
      }
    } catch (error) {
      printError(info: 'log[$scriptName] parse stream event: $error');
    }
  }

  /// Appends lines from an SSE append event.
  void appendLiveLines(Map<String, dynamic> data) {
    final rawLines = data['lines'] as List? ?? const [];
    final parsed = rawLines
        .whereType<Map>()
        .map((item) => ScriptLogLine.fromJson(item.cast<String, dynamic>()))
        .toList();
    if (parsed.isNotEmpty) {
      final fresh = parsed.where((line) => !_lineKeys.contains(line.key));
      final freshLines = fresh.toList();
      if (freshLines.isNotEmpty) {
        lines.addAll(freshLines);
        _lineKeys.addAll(freshLines.map((line) => line.key));
        for (final line in freshLines) {
          final score = _scoreScriptLogLineWidth(line.text);
          if (score > maxLineWidthScore) {
            maxLineWidthScore = score;
          }
        }
        trimToLiveWindow();
      }
    }
    updateLiveCursor(data['next_cursor']);
    if (autoScroll.value) {
      syncBottomAfterFrame();
    }
  }

  /// Updates the live cursor if the event carries one.
  void updateLiveCursor(dynamic cursor) {
    final value = cursor?.toString() ?? '';
    if (value.isNotEmpty) {
      liveCursor = value;
    }
  }
}
