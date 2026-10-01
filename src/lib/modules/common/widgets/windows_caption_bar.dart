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
    const foreground = Color(0xFFE4F1F7);
    final captionTheme = theme.copyWith(
      brightness: Brightness.dark,
      colorScheme: theme.colorScheme.copyWith(
        brightness: Brightness.dark,
        primary: const Color(0xFF9BDCEF),
        surface: const Color(0xFF142A3A),
        onSurface: foreground,
        onSurfaceVariant: const Color(0xFFBCD0DD),
        outline: const Color(0xFF7594A8),
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
      hoverColor: const Color(0x185CCAE3),
      splashColor: const Color(0x205CCAE3),
    );
    // Keep the caption dark in both app themes so its controls remain readable
    // against the blue background. The page below retains its own theme.
    return Theme(
      data: captionTheme,
      child: Container(
        height: widget.preferredSize.height,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [Color(0xFF142A3A), Color(0xFF102030), Color(0xFF0D1928)],
            stops: [0, 0.58, 1],
          ),
          border: Border(bottom: BorderSide(color: Color(0x705CCAE3))),
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
              brightness: Brightness.dark,
              isMaximized: _isMaximized,
            ),
          ],
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
