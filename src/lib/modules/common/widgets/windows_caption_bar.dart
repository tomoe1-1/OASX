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
    final theme = Theme.of(context);
    const foreground = Color(0xFF10222C);
    final captionTheme = theme.copyWith(
      brightness: Brightness.light,
      colorScheme: theme.colorScheme.copyWith(
        brightness: Brightness.light,
        primary: const Color(0xFF143F53),
        surface: Colors.white,
        onSurface: foreground,
        onSurfaceVariant: const Color(0xFF152A36),
        outline: const Color(0xFF4F6A7A),
      ),
      textTheme: theme.textTheme.apply(
        bodyColor: foreground,
        displayColor: foreground,
      ),
      iconTheme: theme.iconTheme.copyWith(color: foreground),
      iconButtonTheme: IconButtonThemeData(
        style: (theme.iconButtonTheme.style ?? const ButtonStyle()).copyWith(
          foregroundColor: const WidgetStatePropertyAll(foreground),
        ),
      ),
      hoverColor: const Color(0x14102A3A),
      splashColor: const Color(0x20102A3A),
    );
    // The frame lets the home's one backdrop show through. Its light local
    // theme gives controls a dark foreground without changing the page theme.
    return Theme(
      data: captionTheme,
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Container(
          height: widget.preferredSize.height - 8,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.32),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withValues(alpha: 0.44)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(left: Spacing.sm),
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
                brightness: Brightness.light,
                isMaximized: _isMaximized,
              ),
            ],
          ),
        ),
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
