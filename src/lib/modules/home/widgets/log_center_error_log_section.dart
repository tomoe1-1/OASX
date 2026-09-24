part of 'log_center_panel.dart';

extension _LogCenterErrorDetailLogSectionX on LogCenterErrorDetailView {
  /// Builds the log slivers with progressive state feedback.
  List<Widget> _buildLogSlivers(BuildContext context) {
    final lines = controller.selectedErrorLogLines;
    final preparing = controller.errorLogPreparing.value;
    if (lines.isEmpty) {
      if (controller.errorMessage.value.isNotEmpty) {
        return [
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(child: Text(controller.errorMessage.value)),
          ),
        ];
      }
      if (preparing) {
        return const [
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(child: CircularProgressIndicator()),
          ),
        ];
      }
      return const [SliverToBoxAdapter(child: SizedBox.shrink())];
    }
    final widgets = <Widget>[
      if (preparing || controller.errorLogAppending.value)
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.only(bottom: Spacing.xsPlus),
            child: LinearProgressIndicator(minHeight: 2),
          ),
        ),
    ];
    if (controller.wrapLines.value) {
      widgets.add(_buildWrappedLogSliver(context, lines));
      return widgets;
    }
    widgets.add(_buildHorizontalLogSliver(context, lines));
    return widgets;
  }

  /// Builds the wrapped vertical log sliver.
  Widget _buildWrappedLogSliver(BuildContext context, List<String> lines) {
    return SliverToBoxAdapter(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onLongPress: () => _openCopyDialog(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: lines.map((line) {
            return Padding(
              padding: const EdgeInsets.only(right: Spacing.md),
              child: LogCenterLogText(
                line: line,
                maxLines: null,
                overflow: TextOverflow.clip,
                softWrap: true,
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  /// Builds a selectable non-wrapped error log body.
  Widget _buildSelectableHorizontalLogArea(
    BuildContext context,
    List<String> lines,
    double width,
  ) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPress: () => _openCopyDialog(context),
      child: SizedBox(
        width: width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: lines.map((line) {
            return Padding(
              padding: const EdgeInsets.only(right: Spacing.md),
              child: LogCenterLogText(
                line: line,
                maxLines: 1,
                overflow: TextOverflow.visible,
                softWrap: false,
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  /// Builds the non-wrapped horizontal log area inside the vertical scroll flow.
  Widget _buildHorizontalLogSliver(BuildContext context, List<String> lines) {
    return SliverToBoxAdapter(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = _resolveContentWidth(
            context,
            constraints.maxWidth,
            controller.selectedErrorLogMaxWidthScore.value,
          );
          return Scrollbar(
            controller: detailHorizontalScrollController,
            interactive: true,
            thumbVisibility: width > constraints.maxWidth,
            notificationPredicate: (notification) {
              return notification.metrics.axis == Axis.horizontal;
            },
            child: SingleChildScrollView(
              controller: detailHorizontalScrollController,
              scrollDirection: Axis.horizontal,
              child: _buildSelectableHorizontalLogArea(context, lines, width),
            ),
          );
        },
      ),
    );
  }

  /// Opens the dedicated copy dialog with the current error-detail log body.
  void _openCopyDialog(BuildContext context) {
    showLogCenterCopyDialog(
      context,
      text: controller.selectedErrorLogText,
      onCopy: controller.copyText,
    );
  }

  /// Resolves one best-effort monospace width for horizontal scrolling.
  double _resolveContentWidth(
    BuildContext context,
    double viewportWidth,
    int widthScore,
  ) {
    final fontSize = Theme.of(context).textTheme.bodyMedium?.fontSize ?? 14;
    final estimatedWidth = widthScore * fontSize * 0.64 + 48;
    return estimatedWidth < viewportWidth ? viewportWidth : estimatedWidth;
  }
}
