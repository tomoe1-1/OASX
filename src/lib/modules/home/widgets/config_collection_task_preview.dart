import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:oasx/config/design_tokens.dart';
import 'package:oasx/modules/home/models/config_model.dart';
import 'package:oasx/translation/i18n_content.dart';

class ConfigCollectionTaskPreview extends StatelessWidget {
  const ConfigCollectionTaskPreview({
    super.key,
    required this.script,
    this.showWaitingTime = true,
  });

  final ScriptModel script;
  final bool showWaitingTime;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final isRunning = script.state.value == ScriptState.running;
      final runningName = isRunning
          ? script.runningTask.value.taskName.value.trim()
          : '';
      final next = _nextTaskPreview(runningName);
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _TaskPreviewRow(
            key: const ValueKey('config-current-task'),
            label: I18n.homeCurrentTask.tr,
            text: runningName.isNotEmpty
                ? runningName.tr
                : (isRunning && !script.currentTaskKnown.value
                      ? I18n.homeCurrentTaskLoading.tr
                      : I18n.homeNoRunningTask.tr),
            icon: Icons.bolt_rounded,
            color: runningName.isNotEmpty
                ? SemanticColors.success(context)
                : SemanticColors.neutral(context),
          ),
          const SizedBox(height: Spacing.xs),
          _TaskPreviewRow(
            key: const ValueKey('config-next-task'),
            label: I18n.homeNextTask.tr,
            text: next?.displayName ?? I18n.homeNoTask.tr,
            icon: next?.icon ?? Icons.schedule_rounded,
            color: next?.color(context) ?? SemanticColors.neutral(context),
          ),
        ],
      );
    });
  }

  _TaskPreviewData? _nextTaskPreview(String runningName) {
    // Preserve backend scheduler order and skip any duplicated running entry.
    for (final task in script.pendingTaskList) {
      final name = task.taskName.value.trim();
      if (name.isNotEmpty && name != runningName) {
        return _TaskPreviewData(type: _PreviewTaskType.pending, name: name);
      }
    }
    for (final task in script.waitingTaskList) {
      final name = task.taskName.value.trim();
      if (name.isNotEmpty && name != runningName) {
        return _TaskPreviewData(
          type: _PreviewTaskType.waiting,
          name: name,
          timeText: showWaitingTime ? task.nextRun.value.trim() : '',
        );
      }
    }
    return null;
  }
}

class _TaskPreviewRow extends StatelessWidget {
  const _TaskPreviewRow({
    super.key,
    required this.label,
    required this.text,
    required this.icon,
    required this.color,
  });

  final String label;
  final String text;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelMedium;
    return Tooltip(
      message: '$label：$text',
      child: Row(
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: Spacing.xs),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '$label：',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  TextSpan(text: text),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              softWrap: false,
              style: style,
            ),
          ),
        ],
      ),
    );
  }
}

enum _PreviewTaskType { pending, waiting }

class _TaskPreviewData {
  const _TaskPreviewData({
    required this.type,
    required this.name,
    this.timeText = '',
  });

  final _PreviewTaskType type;
  final String name;
  final String timeText;

  String get displayName {
    final localizedName = name.tr;
    if (timeText.isEmpty || type != _PreviewTaskType.waiting) {
      return localizedName;
    }
    return '$localizedName ${timeText.split(' ').last}';
  }

  IconData get icon => switch (type) {
    _PreviewTaskType.pending => Icons.layers_rounded,
    _PreviewTaskType.waiting => Icons.schedule_rounded,
  };

  Color color(BuildContext context) => switch (type) {
    _PreviewTaskType.pending => SemanticColors.warning(context),
    _PreviewTaskType.waiting => SemanticColors.neutral(context),
  };
}
