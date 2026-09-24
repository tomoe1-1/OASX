part of 'log_center_panel.dart';

/// Opens the dedicated copy dialog for one log payload.
Future<void> showLogCenterCopyDialog(
  BuildContext context, {
  required String text,
  required ValueChanged<String> onCopy,
}) async {
  if (text.isEmpty) {
    return;
  }
  await showDialog<void>(
    context: context,
    builder: (context) => LogCenterCopyDialog(text: text, onCopy: onCopy),
  );
}

/// Dedicated log copy surface used after a long press.
class LogCenterCopyDialog extends StatefulWidget {
  /// Creates one log copy dialog.
  const LogCenterCopyDialog({
    super.key,
    required this.text,
    required this.onCopy,
  });

  /// Full log text shown in the dialog.
  final String text;

  /// Clipboard callback owned by the log controller.
  final ValueChanged<String> onCopy;

  @override
  State<LogCenterCopyDialog> createState() => _LogCenterCopyDialogState();
}

class _LogCenterCopyDialogState extends State<LogCenterCopyDialog> {
  /// Current selection inside the copy dialog.
  TextSelection? _selection;

  /// Dedicated scroll controller for the dialog body.
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selectionStyle = DefaultSelectionStyle.of(context);
    final selectionColor =
        selectionStyle.selectionColor ??
        theme.colorScheme.primary.withValues(alpha: 0.28);
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: Spacing.lg, vertical: Spacing.xxl),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 920,
          maxHeight: MediaQuery.sizeOf(context).height * 0.88,
        ),
        child: Padding(
          padding: const EdgeInsets.all(Spacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(I18n.copy.tr, style: theme.textTheme.titleMedium),
              const SizedBox(height: Spacing.md),
              Expanded(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(color: theme.colorScheme.outlineVariant),
                    borderRadius: BorderRadius.circular(Radii.md),
                  ),
                  child: Scrollbar(
                    controller: _scrollController,
                    thumbVisibility: true,
                    child: SingleChildScrollView(
                      controller: _scrollController,
                      padding: const EdgeInsets.all(Spacing.md),
                      child: SelectableText(
                        widget.text,
                        onSelectionChanged: _handleSelectionChanged,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontFeatures: const [FontFeature.tabularFigures()],
                          height: 1.4,
                        ),
                        selectionColor: selectionColor,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: Spacing.md),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(I18n.cancel.tr),
                  ),
                  const SizedBox(width: Spacing.sm),
                  FilledButton.icon(
                    onPressed: _copySelectionOrAll,
                    icon: const Icon(Icons.content_copy_rounded),
                    label: Text(I18n.copy.tr),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Stores the latest selection produced by the dialog text.
  void _handleSelectionChanged(
    TextSelection selection,
    SelectionChangedCause? cause,
  ) {
    _selection = selection;
  }

  /// Copies the selected text, or the entire log when nothing is selected.
  void _copySelectionOrAll() {
    final text = _selectedText();
    widget.onCopy(text.isEmpty ? widget.text : text);
  }

  /// Returns the selected dialog text while preserving existing line breaks.
  String _selectedText() {
    final selection = _selection;
    if (selection == null) {
      return '';
    }
    final start = selection.start < selection.end
        ? selection.start
        : selection.end;
    final end = selection.start < selection.end
        ? selection.end
        : selection.start;
    if (start < 0 || end <= start || end > widget.text.length) {
      return '';
    }
    return widget.text.substring(start, end);
  }
}
