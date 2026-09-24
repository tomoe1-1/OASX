import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:window_manager/window_manager.dart';

import 'package:oasx/config/design_tokens.dart';
import 'package:oasx/modules/common/widgets/title.dart';
import 'package:oasx/translation/i18n_content.dart';

const double _compactActionBaseThreshold = 280;
const double _compactActionWidth = 48;

class WindowsCaptionBar extends StatefulWidget implements PreferredSizeWidget {
  const WindowsCaptionBar({
    super.key,
    required this.brightness,
    this.onMenuPressed,
    this.routePath,
    this.trailingActions = const [],
  });

  final Brightness brightness;
  final VoidCallback? onMenuPressed;
  final String? routePath;
  final List<Widget> trailingActions;

  @override
  Size get preferredSize => const Size.fromHeight(50);

  @override
  State<WindowsCaptionBar> createState() => _WindowsCaptionBarState();
}

class _WindowsCaptionBarState extends State<WindowsCaptionBar>
    with WindowListener {
  bool _isMaximized = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    unawaited(_syncMaximizedState());
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowMaximize() {
    if (!mounted || _isMaximized) {
      return;
    }
    setState(() => _isMaximized = true);
  }

  @override
  void onWindowUnmaximize() {
    if (!mounted || !_isMaximized) {
      return;
    }
    setState(() => _isMaximized = false);
  }

  @override
  void onWindowRestore() {
    unawaited(_syncMaximizedState());
  }

  Future<void> _syncMaximizedState() async {
    final nextValue = await windowManager.isMaximized();
    if (!mounted || nextValue == _isMaximized) {
      return;
    }
    setState(() => _isMaximized = nextValue);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: widget.preferredSize.height,
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(
          bottom: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(left: Spacing.lg),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final hideTrailingActions = _shouldHideTrailingActions(
                    constraints.maxWidth,
                  );
                  return Row(
                    children: [
                      if (widget.onMenuPressed != null)
                        IconButton(
                          icon: const Icon(Icons.menu),
                          tooltip: I18n.more.tr,
                          onPressed: widget.onMenuPressed,
                          visualDensity: VisualDensity.compact,
                          constraints: const BoxConstraints.tightFor(
                            width: 40,
                            height: 40,
                          ),
                        ),
                      Expanded(
                        child: DragToMoveArea(
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: getTitle(
                              context,
                              routePath: widget.routePath,
                            ),
                          ),
                        ),
                      ),
                      if (!hideTrailingActions &&
                          widget.trailingActions.isNotEmpty)
                        const SizedBox(width: Spacing.sm),
                      if (!hideTrailingActions) ...widget.trailingActions,
                      const SizedBox(width: Spacing.sm),
                    ],
                  );
                },
              ),
            ),
          ),
          _WindowCaptionButtons(
            brightness: widget.brightness,
            isMaximized: _isMaximized,
          ),
        ],
      ),
    );
  }

  bool _shouldHideTrailingActions(double maxWidth) {
    if (widget.trailingActions.isEmpty) {
      return false;
    }
    final threshold =
        _compactActionBaseThreshold +
        (widget.trailingActions.length * _compactActionWidth);
    return maxWidth <= threshold;
  }
}

class _WindowCaptionButtons extends StatelessWidget {
  const _WindowCaptionButtons({
    required this.brightness,
    required this.isMaximized,
  });

  final Brightness brightness;
  final bool isMaximized;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        WindowCaptionButton.minimize(
          brightness: brightness,
          onPressed: () async {
            final isMinimized = await windowManager.isMinimized();
            if (isMinimized) {
              await windowManager.restore();
              return;
            }
            await windowManager.minimize();
          },
        ),
        if (isMaximized)
          WindowCaptionButton.unmaximize(
            brightness: brightness,
            onPressed: () async {
              await windowManager.unmaximize();
            },
          )
        else
          WindowCaptionButton.maximize(
            brightness: brightness,
            onPressed: () async {
              await windowManager.maximize();
            },
          ),
        WindowCaptionButton.close(
          brightness: brightness,
          onPressed: () async {
            await windowManager.close();
          },
        ),
      ],
    );
  }
}
