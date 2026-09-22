part of 'log_center_panel.dart';

/// Header controls for the log center.
class LogCenterToolbar extends StatelessWidget {
  /// Creates toolbar controls.
  const LogCenterToolbar({
    super.key,
    required this.controller,
    required this.onToggleLineWrap,
  });

  /// Log browser controller.
  final ScriptLogBrowserController controller;

  /// Toggles wrapping with panel-level scroll handling.
  final VoidCallback onToggleLineWrap;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: _leadingControls(context)),
        const SizedBox(width: Spacing.sm),
        _trailingControls(),
      ],
    );
  }

  /// Builds title and tab switch on the left.
  Widget _leadingControls(BuildContext context) {
    return Wrap(
      spacing: Spacing.sm,
      runSpacing: Spacing.sm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [_tabSwitch()],
    );
  }

  /// Builds action buttons aligned to the right.
  Widget _trailingControls() {
    return Obx(() {
      if (!_shouldShowLogActions()) {
        return const SizedBox.shrink();
      }
      return Wrap(
        spacing: Spacing.xs,
        runSpacing: Spacing.xs,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (_shouldShowWrapAction()) _wrapButton(),
          if (controller.activeTab.value == ScriptLogBrowserTab.info)
            _autoScrollButton(),
          _copyButton(),
          _clearButton(),
        ],
      );
    });
  }

  /// Returns whether the current view owns log text actions.
  bool _shouldShowLogActions() {
    if (controller.activeTab.value == ScriptLogBrowserTab.info) {
      return true;
    }
    return controller.errorDetailVisible.value;
  }

  /// Returns whether wrapping can affect the current log text.
  bool _shouldShowWrapAction() {
    if (controller.activeTab.value == ScriptLogBrowserTab.info) {
      return true;
    }
    return controller.errorDetailVisible.value;
  }

  /// Builds the info/error tab selector.
  Widget _tabSwitch() {
    return Obx(
      () => SegmentedButton<ScriptLogBrowserTab>(
        showSelectedIcon: false,
        segments: [
          ButtonSegment(
            value: ScriptLogBrowserTab.info,
            label: Text(I18n.homeLogInfoTab.tr),
          ),
          ButtonSegment(
            value: ScriptLogBrowserTab.error,
            label: Text(I18n.homeLogErrorTab.tr),
          ),
        ],
        selected: {controller.activeTab.value},
        onSelectionChanged: (values) => controller.selectTab(values.first),
      ),
    );
  }

  Widget _autoScrollButton() {
    final enabled = controller.autoScroll.value;
    return IconButton(
      tooltip: I18n.homeLogAutoScroll.tr,
      onPressed: controller.toggleAutoScroll,
      icon: Icon(enabled ? Icons.flash_on_rounded : Icons.flash_off_rounded),
    );
  }

  /// Builds the long-line wrapping action.
  Widget _wrapButton() {
    final enabled = controller.wrapLines.value;
    return IconButton(
      tooltip: I18n.homeLogWrapLines.tr,
      onPressed: onToggleLineWrap,
      icon: Icon(enabled ? Icons.wrap_text : Icons.short_text),
    );
  }

  /// Builds the copy action.
  Widget _copyButton() {
    return IconButton(
      tooltip: I18n.copy.tr,
      onPressed: _copyCurrent,
      icon: const Icon(Icons.content_copy_rounded),
    );
  }

  /// Builds the clear action.
  Widget _clearButton() {
    return IconButton(
      tooltip: I18n.clearLog.tr,
      onPressed: controller.clearCurrentView,
      icon: const Icon(Icons.delete_outlined),
    );
  }

  void _copyCurrent() {
    controller.copyCurrentView();
  }
}
