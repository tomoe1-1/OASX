import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, VoidCallback, defaultTargetPlatform, kIsWeb;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:oasx/api/api_client.dart';
import 'package:oasx/api/sse_client.dart';
import 'package:oasx/modules/log/log_browser_models.dart';
import 'package:oasx/translation/i18n_content.dart';
import 'package:oasx/utils/browser_download_io.dart'
    if (dart.library.html) 'package:oasx/utils/browser_download_web.dart';
import 'package:oasx/utils/file_save_stub.dart'
    if (dart.library.io) 'package:oasx/utils/file_save_io.dart';

part 'script_log_browser_actions.dart';
part 'script_log_browser_error_detail_render.dart';
part 'script_log_browser_errors.dart';
part 'script_log_browser_error_render.dart';
part 'script_log_browser_info.dart';
part 'script_log_browser_state.dart';
part 'script_log_browser_stream.dart';
part 'script_log_browser_window.dart';

/// Log window line count used for live-following mode.
const int kAutoScrollLogWindowLineLimit = 100;

/// Log window line count used for manual review mode.
const int kManualScrollLogWindowLineLimit = 300;

/// Script-scoped log browser controller.
class ScriptLogBrowserController extends GetxController {
  /// Creates one script log browser controller.
  ScriptLogBrowserController({required this.scriptName});

  /// Script name owned by this controller.
  final String scriptName;

  /// Current selected tab.
  final activeTab = ScriptLogBrowserTab.info.obs;

  /// Info log lines.
  final lines = <ScriptLogLine>[].obs;

  /// Cached set of info log keys for fast deduplication.
  final _lineKeys = <String>{};

  /// Cached score for the widest info log line.
  int maxLineWidthScore = 0;

  /// Whether info latest window is loading.
  final infoLoading = false.obs;

  /// Whether an older info window is loading.
  final olderLoading = false.obs;

  /// User-visible info error.
  final infoError = ''.obs;

  /// Current live stream status.
  final streamStatus = ScriptLogStreamStatus.idle.obs;

  /// Whether info logs should follow bottom.
  final autoScroll = true.obs;

  /// Whether long log lines should wrap in the viewport.
  final wrapLines = true.obs;

  /// Error log list items.
  final errorItems = <ScriptErrorLogItem>[].obs;

  /// Selected error item id.
  final selectedErrorId = ''.obs;

  /// Selected error item title captured from the list page.
  final selectedErrorTitle = ''.obs;

  /// Selected error detail.
  final selectedErrorDetail = Rxn<ScriptErrorLogDetail>();

  /// Prepared error detail log lines for virtual rendering.
  final selectedErrorLogLines = <String>[].obs;

  /// Cached score for the widest error detail log line.
  final selectedErrorLogMaxWidthScore = 0.obs;

  /// Image download keys currently running.
  final downloadingImageKeys = <String>[].obs;

  /// Whether the error detail page is visible.
  final errorDetailVisible = false.obs;

  /// Whether error list is loading.
  final errorListLoading = false.obs;

  /// Whether error detail is loading.
  final errorDetailLoading = false.obs;

  /// Whether error log lines are being prepared.
  final errorLogPreparing = false.obs;

  /// Whether remaining error log lines are still appending.
  final errorLogAppending = false.obs;

  /// User-visible error page failure.
  final errorMessage = ''.obs;

  /// Whether error list has more pages.
  final errorHasMore = false.obs;

  /// Last saved viewport offset.
  double savedScrollOffset = 0;

  /// First visible log anchor key.
  String savedAnchorKey = '';

  /// Pixel delta from viewport top to anchor.
  double savedAnchorDelta = 0;

  /// Callback used by UI to follow bottom.
  VoidCallback? scrollToBottom;

  /// Callback used by UI to restore saved offset.
  void Function(double offset)? restoreScrollOffset;

  /// Callback used by UI after history prepend.
  void Function(int insertedCount)? preserveViewportAfterPrepend;

  /// Callback used by UI to reset the error detail viewport.
  VoidCallback? resetErrorDetailViewport;

  /// UI owner currently bound to viewport callbacks.
  Object? viewportOwner;

  /// Cursor for loading older log lines.
  String? olderCursor;

  /// Cursor for starting live stream.
  String liveCursor = '';

  /// Whether the history start has been reached.
  bool reachedStart = false;

  /// Active SSE client.
  ApiSseClient? streamClient;

  /// Periodic refresh timer for the visible error list.
  Timer? errorListRefreshTimer;

  /// Revision used to drop stale async results.
  int revision = 0;

  /// Error list next page cursor.
  String? errorNextCursor;

  /// Active info load request id.
  int _infoLoadRequestId = 0;

  /// Active older log request id.
  int _olderLoadRequestId = 0;

  /// Active error list request id.
  int _errorListRequestId = 0;

  /// Active error detail request id.
  int _errorDetailRequestId = 0;

  /// Token used to cancel stale error detail render work.
  int _errorDetailRenderToken = 0;

  /// Whether a bottom sync has already been queued for this frame.
  bool _bottomSyncQueued = false;

  /// Whether info view should reload the latest window when re-entered.
  bool _shouldRefreshLatestOnInfoResume = false;

  /// Maximum lines retained in the current visible info window.
  int retainedLogLineLimit = kAutoScrollLogWindowLineLimit;

  /// Returns whether info view should reload latest logs on the next activate.
  bool get shouldRefreshLatestOnInfoResume => _shouldRefreshLatestOnInfoResume;

  @override
  void onClose() {
    scrollToBottom = null;
    restoreScrollOffset = null;
    preserveViewportAfterPrepend = null;
    resetErrorDetailViewport = null;
    stopErrorListAutoRefresh();
    unawaited(stopStream());
    super.onClose();
  }
}

/// Scores a log line width by a rough monospace character budget.
int _scoreScriptLogLineWidth(String text) {
  return text.runes.fold(0, (total, rune) {
    return total + (rune > 255 ? 2 : 1);
  });
}
