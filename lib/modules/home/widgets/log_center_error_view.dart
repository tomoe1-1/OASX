part of 'log_center_panel.dart';

/// Error log list and detail view.
class LogCenterErrorView extends StatelessWidget {
  /// Creates the error log view.
  const LogCenterErrorView({
    super.key,
    required this.controller,
    required this.listScrollController,
    required this.detailScrollController,
    required this.detailHorizontalScrollController,
  });

  /// Log browser controller.
  final ScriptLogBrowserController controller;

  /// Scroll controller for the error list.
  final ScrollController listScrollController;

  /// Scroll controller for the error detail.
  final ScrollController detailScrollController;

  /// Horizontal scroll controller for non-wrapped error detail text.
  final ScrollController detailHorizontalScrollController;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if (controller.errorListLoading.value && controller.errorItems.isEmpty) {
        return const Center(child: CircularProgressIndicator());
      }
      if (controller.errorMessage.value.isNotEmpty &&
          controller.errorItems.isEmpty) {
        return Center(child: Text(controller.errorMessage.value));
      }
      if (controller.errorItems.isEmpty) {
        return Center(child: Text(I18n.homeLogNoErrors.tr));
      }
      return controller.errorDetailVisible.value
          ? _buildDetail(context)
          : _buildList(context);
    });
  }

  Widget _buildList(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: Scrollbar(
            controller: listScrollController,
            interactive: true,
            thumbVisibility: true,
            child: ListView.separated(
              controller: listScrollController,
              itemCount: controller.errorItems.length,
              separatorBuilder: (context, index) {
                return Divider(
                  height: 1,
                  thickness: 1,
                  color: Theme.of(context).colorScheme.outlineVariant,
                );
              },
              itemBuilder: (context, index) {
                final item = controller.errorItems[index];
                return Obx(() {
                  final selected = controller.selectedErrorId.value == item.id;
                  return ListTile(
                    dense: true,
                    selected: selected,
                    title: Text(
                      item.timestampMs.toString(),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    subtitle: Text(
                      '${_formatErrorTime(item)} · ${item.imageCount} ${I18n.homeLogImages.tr}',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    onTap: () => controller.selectError(item.id),
                  );
                });
              },
            ),
          ),
        ),
        if (controller.errorHasMore.value) _buildLoadMore(context),
      ],
    );
  }

  Widget _buildLoadMore(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: Spacing.sm),
      child: TextButton(
        onPressed: () => controller.loadErrorList(),
        child: Text(I18n.homeLogLoadOlder.tr),
      ),
    );
  }

  Widget _buildDetail(BuildContext context) {
    return LogCenterErrorDetailView(
      controller: controller,
      detailScrollController: detailScrollController,
      detailHorizontalScrollController: detailHorizontalScrollController,
    );
  }

  String _formatErrorTime(ScriptErrorLogItem item) {
    return controller.formatErrorTimestamp(item.timestampMs, item.time);
  }
}
