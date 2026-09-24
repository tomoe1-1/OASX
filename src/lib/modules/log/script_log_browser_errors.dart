part of 'script_log_browser_controller.dart';

/// Error list refresh cadence while the list page is visible.
const Duration _errorListRefreshInterval = Duration(seconds: 5);

extension ScriptLogBrowserErrorsX on ScriptLogBrowserController {
  /// Loads one page of error logs for the current script.
  Future<void> loadErrorList({bool reset = false}) async {
    if (errorListLoading.value && !reset) {
      return;
    }
    if (!reset && !errorHasMore.value) {
      return;
    }
    final requestId = reset ? ++revision : revision;
    final cursor = reset ? null : errorNextCursor;
    _errorListRequestId = requestId;
    errorListLoading.value = true;
    errorMessage.value = '';
    if (reset) {
      errorNextCursor = null;
      errorHasMore.value = false;
    }
    try {
      final page = await ApiClient().getScriptErrorLogs(
        scriptName: scriptName,
        cursor: cursor,
      );
      if (!isErrorListLoadActive(requestId)) {
        return;
      }
      if (reset) {
        errorItems.assignAll(page.items);
      } else {
        errorItems.addAll(page.items);
      }
      errorNextCursor = page.nextCursor;
      errorHasMore.value = page.hasMore;
      if (selectedErrorId.value.isEmpty && page.items.isNotEmpty) {
        errorDetailVisible.value = false;
      }
    } catch (error) {
      if (isErrorListLoadActive(requestId)) {
        errorMessage.value = error.toString();
      }
    } finally {
      if (isErrorListLoadActive(requestId)) {
        errorListLoading.value = false;
      }
      if (_errorListRequestId == requestId) {
        _errorListRequestId = 0;
      }
    }
  }

  /// Starts background refresh for the visible error list page.
  void startErrorListAutoRefresh() {
    errorListRefreshTimer ??= Timer.periodic(
      _errorListRefreshInterval,
      (_) => refreshVisibleErrorList(),
    );
  }

  /// Stops background error-list refresh.
  void stopErrorListAutoRefresh() {
    errorListRefreshTimer?.cancel();
    errorListRefreshTimer = null;
  }

  /// Refreshes the error list when it is the visible page.
  void refreshVisibleErrorList() {
    if (activeTab.value != ScriptLogBrowserTab.error) {
      return;
    }
    if (errorDetailVisible.value) {
      return;
    }
    unawaited(loadErrorList(reset: true));
  }

  /// Loads detail for one selected error id.
  Future<void> selectError(String errorId) async {
    final normalized = errorId.trim();
    if (normalized.isEmpty) {
      return;
    }
    ScriptErrorLogItem? selectedItem;
    for (final item in errorItems) {
      if (item.id == normalized) {
        selectedItem = item;
        break;
      }
    }
    final requestId = revision;
    final renderToken = ++_errorDetailRenderToken;
    _errorDetailRequestId = requestId;
    selectedErrorId.value = normalized;
    selectedErrorTitle.value = selectedItem == null
        ? ''
        : formatErrorTimestamp(selectedItem.timestampMs, selectedItem.time);
    resetSelectedErrorRenderState();
    selectedErrorDetail.value = null;
    errorDetailVisible.value = true;
    errorDetailLoading.value = true;
    errorMessage.value = '';
    resetErrorDetailViewport?.call();
    try {
      final detail = await ApiClient().getScriptErrorLogDetail(normalized);
      if (!isErrorDetailLoadActive(requestId) ||
          selectedErrorId.value != normalized) {
        return;
      }
      selectedErrorDetail.value = detail;
      scheduleSelectedErrorLogPreparation(
        detail: detail,
        renderToken: renderToken,
      );
    } catch (error) {
      if (isErrorDetailLoadActive(requestId)) {
        errorMessage.value = error.toString();
      }
    } finally {
      if (isErrorDetailLoadActive(requestId)) {
        errorDetailLoading.value = false;
      }
      if (_errorDetailRequestId == requestId) {
        _errorDetailRequestId = 0;
      }
    }
  }

  /// Copies the selected error log text.
  void copySelectedErrorLog() {
    final text = selectedErrorLogText.isEmpty
        ? selectedErrorDetail.value?.log.content ?? ''
        : selectedErrorLogText;
    copyText(text);
  }

  /// Returns to the error list page.
  void backToErrorList() {
    cancelSelectedErrorRenderWork();
    errorDetailVisible.value = false;
    refreshVisibleErrorList();
  }

  /// Formats one error timestamp for list and detail headers.
  String formatErrorTimestamp(int timestamp, String fallback) {
    if (timestamp <= 0) {
      return fallback;
    }
    final time = DateTime.fromMillisecondsSinceEpoch(timestamp);
    return '${time.year.toString().padLeft(4, '0')}-'
        '${time.month.toString().padLeft(2, '0')}-'
        '${time.day.toString().padLeft(2, '0')} '
        '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}:'
        '${time.second.toString().padLeft(2, '0')}.'
        '${time.millisecond.toString().padLeft(3, '0')}';
  }

  /// Returns whether one error image download is running.
  bool isErrorImageDownloading(ScriptErrorImageInfo image) {
    return downloadingImageKeys.contains(errorImageDownloadKey(image));
  }

  /// Builds a stable key for the selected error image.
  String errorImageDownloadKey(ScriptErrorImageInfo image) {
    final detailId = selectedErrorDetail.value?.id ?? selectedErrorId.value;
    return '$detailId/${image.name}';
  }

  /// Downloads one error image.
  Future<void> downloadErrorImage(ScriptErrorImageInfo image) async {
    final detail = selectedErrorDetail.value;
    if (detail == null) {
      return;
    }
    final downloadKey = '${detail.id}/${image.name}';
    if (downloadingImageKeys.contains(downloadKey)) {
      return;
    }
    downloadingImageKeys.add(downloadKey);
    try {
      final payload = await ApiClient().getScriptErrorImage(
        detail.id,
        image.name,
      );
      if (kIsWeb) {
        await downloadBytesToBrowser(
          payload.bytes,
          payload.fileName,
          mimeType: 'image/png',
        );
        Get.snackbar(
          I18n.tip.tr,
          I18n.homeLogImageSaveSuccess.tr,
          duration: const Duration(seconds: 1),
        );
        return;
      }
      final path = await FilePicker.platform.saveFile(
        fileName: payload.fileName,
        type: FileType.image,
        allowedExtensions: const ['png'],
        bytes: payload.bytes,
      );
      if (path == null || path.trim().isEmpty) {
        return;
      }
      if (!_isMobileTargetPlatform()) {
        await saveBytesToPath(path, payload.bytes);
      }
      Get.snackbar(
        I18n.tip.tr,
        I18n.homeLogImageSaveSuccess.tr,
        duration: const Duration(seconds: 1),
      );
    } catch (_) {
      Get.snackbar(
        I18n.tip.tr,
        I18n.homeLogImageSaveFailed.tr,
        duration: const Duration(seconds: 2),
      );
    } finally {
      downloadingImageKeys.remove(downloadKey);
    }
  }

  /// Returns whether the current runtime target is mobile.
  bool _isMobileTargetPlatform() {
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }
}
