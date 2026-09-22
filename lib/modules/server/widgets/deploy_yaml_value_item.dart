part of 'deploy_yaml_editor.dart';

class _DeployYamlValueItem extends StatelessWidget {
  const _DeployYamlValueItem({
    required this.line,
    required this.comments,
    required this.controller,
    required this.focusNode,
    required this.onChanged,
  });

  final DeployYamlValueLine line;
  final String comments;
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final label = _DeployYamlValueLabel(label: line.key, comments: comments);
        final input = line.isBoolean ? _buildSwitch() : _buildTextField();
        final labelWidth = _labelWidth(context, constraints.maxWidth);
        if (!_canUseHorizontalLayout(constraints.maxWidth, labelWidth)) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              label,
              const SizedBox(height: Spacing.xsPlus),
              Align(alignment: Alignment.centerLeft, child: input),
            ],
          ).paddingOnly(bottom: Spacing.smMid);
        }
        final inputWidth = _inputWidth(constraints.maxWidth, labelWidth);
        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(width: labelWidth, child: label),
            const SizedBox(width: Spacing.md),
            const Spacer(),
            SizedBox(width: inputWidth, child: input),
          ],
        ).paddingOnly(bottom: 5);
      },
    );
  }

  bool _canUseHorizontalLayout(double maxWidth, double labelWidth) {
    return maxWidth >= labelWidth + _minimumInputWidth + 24;
  }

  double _labelWidth(BuildContext context, double maxWidth) {
    final textStyle = DefaultTextStyle.of(context).style;
    final painter = TextPainter(
      text: TextSpan(text: line.key, style: textStyle),
      maxLines: 1,
      textDirection: TextDirection.ltr,
    )..layout();
    final helpWidth = comments.isEmpty ? 0.0 : 27.0;
    if (maxWidth <= _minimumLabelWidth) {
      return maxWidth;
    }
    return (painter.width + helpWidth).clamp(_minimumLabelWidth, maxWidth);
  }

  double _inputWidth(double maxWidth, double labelWidth) {
    if (line.isBoolean) {
      return 64;
    }
    final desired = (controller.text.length * 9.0 + 48).clamp(180.0, 520.0);
    final available = maxWidth - labelWidth - 24;
    return desired.clamp(_minimumInputWidth, available);
  }

  Widget _buildSwitch() {
    return Switch(
      value: line.value.trim().toLowerCase() == 'true',
      onChanged: (value) => onChanged(value ? 'true' : 'false'),
    );
  }

  Widget _buildTextField() {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      minLines: 1,
      maxLines: 1,
      textInputAction: TextInputAction.done,
      onChanged: onChanged,
      onTapOutside: PlatformUtils.isWeb ? null : (_) => focusNode.unfocus(),
      onEditingComplete: PlatformUtils.isWeb ? null : focusNode.unfocus,
      decoration: const InputDecoration(isDense: true),
    );
  }
}

const double _minimumInputWidth = 160;
const double _minimumLabelWidth = 96;

class _DeployYamlValueLabel extends StatelessWidget {
  const _DeployYamlValueLabel({required this.label, required this.comments});

  final String label;
  final String comments;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(child: Text(label)),
        if (comments.isNotEmpty) _DeployYamlHelpTooltip(message: comments),
      ],
    );
  }
}
