part of 'script_log_browser_controller.dart';

/// Visible page inside one script log center.
enum ScriptLogBrowserTab {
  /// Normal realtime and history log page.
  info,

  /// Error list and detail page.
  error,
}

/// Connection state for the live info log stream.
enum ScriptLogStreamStatus {
  /// No stream is active.
  idle,

  /// Stream is opening.
  connecting,

  /// Stream is connected.
  connected,

  /// Stream is reconnecting.
  reconnecting,

  /// Stream failed.
  error,
}
