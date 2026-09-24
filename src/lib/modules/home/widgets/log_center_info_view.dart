part of 'log_center_panel.dart';

/// Info log list with history prefetch.
class LogCenterInfoView extends StatelessWidget {
  /// Creates the info log view.
  const LogCenterInfoView({
    super.key,
    required this.controller,
    required this.scrollController,
    required this.horizontalScrollController,
    required this.onScrollNotification,
  });

  /// Log browser controller.
  final ScriptLogBrowserController controller;

  /// Scroll controller owned by panel state.
  final ScrollController scrollController;

  /// Horizontal scroll controller used when wrapping is disabled.
  final ScrollController horizontalScrollController;

  /// Scroll notification handler.
  final bool Function(ScrollNotification notification) onScrollNotification;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if (controller.infoLoading.value && controller.lines.isEmpty) {
        return const Center(child: CircularProgressIndicator());
      }
      if (controller.infoError.value.isNotEmpty && controller.lines.isEmpty) {
        return _buildMessage(context, controller.infoError.value);
      }
      if (controller.lines.isEmpty) {
        return _buildMessage(context, I18n.homeNoLog.tr);
      }
      return Column(
        children: [
          if (controller.olderLoading.value)
            const LinearProgressIndicator(minHeight: 2),
          Expanded(child: _buildList(context, controller.wrapLines.value)),
        ],
      );
    });
  }

  Widget _buildList(BuildContext context, bool wrapLines) {
    return Scrollbar(
      controller: scrollController,
      interactive: true,
      thumbVisibility: true,
      notificationPredicate: (notification) {
        return notification.metrics.axis == Axis.vertical;
      },
      child: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
        child: ClipRect(child: _buildScrollableArea(context, wrapLines)),
      ),
    );
  }

  Widget _buildScrollableArea(BuildContext context, bool wrapLines) {
    if (wrapLines) {
      return _buildVerticalList(context, wrapLines: true);
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = _resolveContentWidth(context, constraints.maxWidth);
        return Scrollbar(
          controller: horizontalScrollController,
          interactive: true,
          thumbVisibility: width > constraints.maxWidth,
          notificationPredicate: (notification) {
            return notification.metrics.axis == Axis.horizontal;
          },
          child: SingleChildScrollView(
            controller: horizontalScrollController,
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: width,
              child: _buildVerticalList(context, wrapLines: false),
            ),
          ),
        );
      },
    );
  }

  Widget _buildVerticalList(BuildContext context, {required bool wrapLines}) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPress: () => _openCopyDialog(context),
      child: NotificationListener<ScrollNotification>(
        onNotification: onScrollNotification,
        child: ListView.builder(
          key: ValueKey<String>('log-info-${controller.scriptName}'),
          controller: scrollController,
          padding: const EdgeInsets.symmetric(horizontal: Spacing.sm, vertical: Spacing.xsPlus),
          itemCount: controller.lines.length,
          itemBuilder: (context, index) {
            // 日志行重绘频繁，隔离到各自图层，避免整列表跟着重绘。
            return RepaintBoundary(
              child: LogCenterLogText(
                line: controller.lines[index].text,
                maxLines: wrapLines ? null : 1,
                overflow: wrapLines ? TextOverflow.clip : TextOverflow.visible,
                softWrap: wrapLines,
              ),
            );
          },
        ),
      ),
    );
  }

  double _resolveContentWidth(BuildContext context, double viewportWidth) {
    final fontSize = Theme.of(context).textTheme.bodyMedium?.fontSize ?? 14;
    final longest = controller.maxLineWidthScore;
    final estimatedWidth = longest * fontSize * 0.64 + 48;
    return estimatedWidth < viewportWidth ? viewportWidth : estimatedWidth;
  }

  Widget _buildMessage(BuildContext context, String message) {
    return Center(
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodyMedium,
      ),
    );
  }

  /// Opens the dedicated copy dialog with the current info log body.
  void _openCopyDialog(BuildContext context) {
    showLogCenterCopyDialog(
      context,
      text: controller.infoLogText,
      onCopy: controller.copyText,
    );
  }
}
