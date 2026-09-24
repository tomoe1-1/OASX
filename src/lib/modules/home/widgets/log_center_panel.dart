import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:oasx/api/api_client.dart';
import 'package:oasx/config/design_tokens.dart';
import 'package:oasx/modules/log/log_browser_models.dart';
import 'package:oasx/modules/log/script_log_browser_controller.dart';
import 'package:oasx/translation/i18n_content.dart';

part 'log_center_copy_dialog.dart';
part 'log_center_error_view.dart';
part 'log_center_error_detail_view.dart';
part 'log_center_error_log_section.dart';
part 'log_center_error_image_card.dart';
part 'log_center_info_view.dart';
part 'log_center_log_text.dart';
part 'log_center_log_text_span_builder.dart';
part 'log_center_toolbar.dart';
part 'log_center_panel_scroll.dart';

/// Script log center backed by the `/logs` browser API.
class LogCenterPanel extends StatefulWidget {
  /// Creates one script log center.
  const LogCenterPanel({super.key, required this.scriptName});

  /// Active script name.
  final String scriptName;

  @override
  State<LogCenterPanel> createState() => _LogCenterPanelState();
}

class _LogCenterPanelState extends State<LogCenterPanel> {
  static const double _bottomThreshold = 80;
  static const int _prefetchRemainingLines = 50;
  static const double _estimatedLineExtent = 22;

  final Object _viewportOwner = Object();
  ScriptLogBrowserController? _controller;
  ScrollController? _scrollController;
  ScrollController? _horizontalScrollController;
  ScrollController? _errorListScrollController;
  ScrollController? _errorDetailScrollController;
  ScrollController? _errorDetailHorizontalScrollController;
  bool _suppressScrollHandling = false;
  int _bottomScrollToken = 0;
  int _scrollSuppressionToken = 0;

  @override
  void initState() {
    super.initState();
    _horizontalScrollController = ScrollController();
    _errorListScrollController = ScrollController();
    _errorDetailScrollController = ScrollController();
    _errorDetailHorizontalScrollController = ScrollController();
    _bindController(widget.scriptName);
  }

  @override
  void didUpdateWidget(covariant LogCenterPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scriptName == widget.scriptName) {
      return;
    }
    _saveLogCenterViewport(this);
    _releaseLogCenterController(this, suspend: true);
    _bindController(widget.scriptName);
  }

  @override
  void deactivate() {
    _saveLogCenterViewport(this);
    super.deactivate();
  }

  @override
  void dispose() {
    _saveLogCenterViewport(this);
    _releaseLogCenterController(this, suspend: true);
    _scrollController?.dispose();
    _horizontalScrollController?.dispose();
    _errorListScrollController?.dispose();
    _errorDetailScrollController?.dispose();
    _errorDetailHorizontalScrollController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.scriptName.trim().isEmpty) {
      return Card(child: Center(child: Text(I18n.homeNoScriptSelected.tr)));
    }
    final controller = _controller;
    if (controller == null) {
      return Card(child: Center(child: Text(I18n.homeNoLog.tr)));
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LogCenterToolbar(
              controller: controller,
              onToggleLineWrap: () => _handleLogCenterLineWrapToggle(this),
            ),
            const SizedBox(height: Spacing.md),
            Expanded(
              child: Obx(
                () => controller.activeTab.value == ScriptLogBrowserTab.info
                    ? LogCenterInfoView(
                        controller: controller,
                        scrollController: _scrollController!,
                        horizontalScrollController:
                            _horizontalScrollController!,
                        onScrollNotification: _handleScrollNotification,
                      )
                    : LogCenterErrorView(
                        controller: controller,
                        listScrollController: _errorListScrollController!,
                        detailScrollController: _errorDetailScrollController!,
                        detailHorizontalScrollController:
                            _errorDetailHorizontalScrollController!,
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _bindController(String scriptName) {
    final normalized = scriptName.trim();
    final previousScrollController = _scrollController;
    if (normalized.isEmpty) {
      _controller = null;
      _scrollController = ScrollController();
      previousScrollController?.dispose();
      return;
    }
    _controller = _resolveController(normalized);
    _scrollController = ScrollController(
      initialScrollOffset: _controller!.savedScrollOffset,
    );
    final controller = _controller!;
    controller.viewportOwner = _viewportOwner;
    controller.scrollToBottom = () => _scrollLogCenterToBottom(this);
    controller.restoreScrollOffset = (offset) {
      _restoreLogCenterScrollOffset(this, offset);
    };
    controller.preserveViewportAfterPrepend = (insertedCount) {
      _preserveLogCenterViewportAfterPrepend(this, insertedCount);
    };
    controller.resetErrorDetailViewport = () {
      _resetErrorDetailViewport(this);
    };
    previousScrollController?.dispose();
    _activateLogCenterControllerAfterFrame(this, controller);
  }

  ScriptLogBrowserController _resolveController(String scriptName) {
    if (Get.isRegistered<ScriptLogBrowserController>(tag: scriptName)) {
      return Get.find<ScriptLogBrowserController>(tag: scriptName);
    }
    return Get.put(
      ScriptLogBrowserController(scriptName: scriptName),
      tag: scriptName,
      permanent: true,
    );
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (notification.metrics.axis != Axis.vertical) {
      return false;
    }
    if (_suppressScrollHandling) {
      return false;
    }
    if (notification is UserScrollNotification ||
        notification is ScrollUpdateNotification) {
      _handleLogCenterScrollPosition(this);
    }
    return false;
  }
}
