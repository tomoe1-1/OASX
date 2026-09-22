part of 'deploy_yaml_editor.dart';

class _DeployYamlHelpTooltip extends StatefulWidget {
  const _DeployYamlHelpTooltip({required this.message});

  final String message;

  @override
  State<_DeployYamlHelpTooltip> createState() => _DeployYamlHelpTooltipState();
}

class _DeployYamlHelpTooltipState extends State<_DeployYamlHelpTooltip> {
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _entry;

  @override
  void dispose() {
    _hide();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: IconButton(
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints.tightFor(width: 22, height: 22),
        icon: const Icon(Icons.help_outline, size: 16),
        onPressed: _toggle,
      ).paddingOnly(left: 5),
    );
  }

  void _toggle() {
    if (_entry == null) {
      _show();
    } else {
      _hide();
    }
  }

  void _show() {
    final overlay = Overlay.of(context);
    _entry = OverlayEntry(builder: _buildOverlay);
    overlay.insert(_entry!);
  }

  Widget _buildOverlay(BuildContext context) {
    final theme = Theme.of(context);
    return Stack(
      children: [
        Positioned.fill(
          child: Listener(
            onPointerDown: (_) => _hide(),
            child: Container(color: Colors.transparent),
          ),
        ),
        CompositedTransformFollower(
          link: _layerLink,
          offset: const Offset(0, 24),
          showWhenUnlinked: false,
          child: Material(
            elevation: 6,
            borderRadius: BorderRadius.circular(Radii.sm),
            color: theme.colorScheme.surface,
            child: SelectableText(
              widget.message,
              style: theme.textTheme.bodySmall,
            ).paddingAll(Spacing.smPlus).constrained(maxWidth: 360),
          ),
        ),
      ],
    );
  }

  void _hide() {
    _entry?.remove();
    _entry = null;
  }
}
