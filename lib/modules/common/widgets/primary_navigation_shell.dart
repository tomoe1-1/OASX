import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:oasx/config/design_tokens.dart';
import 'package:oasx/modules/common/widgets/appbar.dart';
import 'package:oasx/modules/home/index.dart';
import 'package:oasx/modules/home/models/home_workbench_layout.dart';
import 'package:oasx/modules/settings/index.dart';
import 'package:oasx/translation/i18n_content.dart';

const double kPrimaryNavigationRailWidth = 88;

class PrimaryNavigationShell extends StatefulWidget {
  const PrimaryNavigationShell({
    super.key,
    required this.initialRoutePath,
  });

  final String initialRoutePath;

  @override
  State<PrimaryNavigationShell> createState() => _PrimaryNavigationShellState();
}

class _PrimaryNavigationShellState extends State<PrimaryNavigationShell> {
  late String _routePath;
  late final Set<int> _builtIndexes;

  @override
  void initState() {
    super.initState();
    _routePath = _normalizeRoutePath(widget.initialRoutePath);
    _builtIndexes = <int>{_selectedIndexForRoute(_routePath)};
  }

  @override
  void didUpdateWidget(covariant PrimaryNavigationShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextRoutePath = _normalizeRoutePath(widget.initialRoutePath);
    if (nextRoutePath == _routePath) {
      return;
    }
    final previousRoutePath = _routePath;
    _routePath = nextRoutePath;
    _builtIndexes.add(_selectedIndexForRoute(nextRoutePath));
    _handleRouteExit(previousRoutePath, nextRoutePath);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final selectedIndex = _selectedIndexForRoute(_routePath);
        final showRail = _shouldShowRail(constraints.maxWidth);
        final content = _PrimaryNavigationContent(
          selectedIndex: selectedIndex,
          builtIndexes: _builtIndexes,
        );
        return Scaffold(
          appBar: buildPlatformAppBar(context, routePath: _routePath),
          resizeToAvoidBottomInset: false,
          body: showRail
              ? Row(
                  children: [
                    _PrimaryNavigationRail(
                      selectedIndex: selectedIndex,
                      onSelected: _handleDestinationSelected,
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(child: content),
                  ],
                )
              : content,
          bottomNavigationBar: showRail
              ? null
              : NavigationBar(
                  selectedIndex: selectedIndex,
                  onDestinationSelected: _handleDestinationSelected,
                  destinations: _destinations(),
                ),
        );
      },
    );
  }

  bool _shouldShowRail(double maxWidth) {
    const twoPaneShellWidth = kHomeWorkbenchMinCollectionWidth +
        kHomeWorkbenchMinDetailsWidth +
        kHomeWorkbenchDividerWidth +
        kPrimaryNavigationRailWidth;
    return maxWidth >= twoPaneShellWidth;
  }

  String _normalizeRoutePath(String value) {
    return value == '/settings' ? '/settings' : '/home';
  }

  int _selectedIndexForRoute(String value) {
    return value == '/settings' ? 1 : 0;
  }

  String _routePathForIndex(int index) {
    return index == 1 ? '/settings' : '/home';
  }

  void _handleDestinationSelected(int index) {
    final nextRoutePath = _routePathForIndex(index);
    if (nextRoutePath == _routePath) {
      return;
    }
    final previousRoutePath = _routePath;
    setState(() {
      _routePath = nextRoutePath;
      _builtIndexes.add(index);
    });
    _handleRouteExit(previousRoutePath, nextRoutePath);
  }

  void _handleRouteExit(String previousRoutePath, String nextRoutePath) {
    if (previousRoutePath == '/settings' && nextRoutePath != '/settings') {
      unawaited(handleSettingsLeaveEffect());
    }
  }

  List<Widget> _destinations() {
    return [
      NavigationDestination(
        icon: const Icon(Icons.home_rounded),
        label: I18n.home.tr,
      ),
      NavigationDestination(
        icon: const Icon(Icons.settings_rounded),
        label: I18n.setting.tr,
      ),
    ];
  }
}

class _PrimaryNavigationContent extends StatelessWidget {
  const _PrimaryNavigationContent({
    required this.selectedIndex,
    required this.builtIndexes,
  });

  final int selectedIndex;
  final Set<int> builtIndexes;

  @override
  Widget build(BuildContext context) {
    // 已构建过的页面常驻，避免重复初始化；切换时做淡入 + 轻微上移过渡
    return Stack(
      children: [
        for (final index in <int>[0, 1])
          if (builtIndexes.contains(index))
            _AnimatedPane(
              visible: index == selectedIndex,
              child: index == 0
                  ? const HomeView(standalone: false)
                  : const SettingsView(standalone: false),
            ),
      ],
    );
  }
}

/// 页面过渡容器：可见时淡入并归位，隐藏时淡出并保留占位
class _AnimatedPane extends StatelessWidget {
  const _AnimatedPane({required this.visible, required this.child});

  final bool visible;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: visible ? 1 : 0,
      duration: Motion.of(context, Motion.normal),
      curve: Motion.standard,
      child: IgnorePointer(
        ignoring: !visible,
        child: AnimatedSlide(
          offset: visible ? Offset.zero : const Offset(0, 0.015),
          duration: Motion.of(context, Motion.normal),
          curve: Motion.standard,
          child: TickerMode(
            enabled: visible,
            child: child,
          ),
        ),
      ),
    );
  }
}

class _PrimaryNavigationRail extends StatelessWidget {
  const _PrimaryNavigationRail({
    required this.selectedIndex,
    required this.onSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return NavigationRail(
      selectedIndex: selectedIndex,
      onDestinationSelected: onSelected,
      labelType: NavigationRailLabelType.all,
      minWidth: kPrimaryNavigationRailWidth,
      groupAlignment: -0.85,
      leading: Padding(
        padding: const EdgeInsets.only(top: Spacing.sm, bottom: Spacing.lg),
        child: _RailBrandMark(scheme: scheme),
      ),
      destinations: [
        NavigationRailDestination(
          icon: const Icon(Icons.home_outlined),
          selectedIcon: const Icon(Icons.home_rounded),
          label: Text(I18n.home.tr),
        ),
        NavigationRailDestination(
          icon: const Icon(Icons.settings_outlined),
          selectedIcon: const Icon(Icons.settings_rounded),
          label: Text(I18n.setting.tr),
        ),
      ],
    );
  }
}

/// 侧边栏顶部的品牌标识：用主题色渐变圆角块，替代纯文字，提升识别度
class _RailBrandMark extends StatelessWidget {
  const _RailBrandMark({required this.scheme});

  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    // 纯装饰：字母只是品牌图形的一部分，读屏时应整体忽略，
    // 否则会念出一个孤立的 "X"。
    return ExcludeSemantics(
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [scheme.primary, scheme.tertiary],
          ),
          borderRadius: const BorderRadius.all(Radius.circular(Radii.md)),
          boxShadow: [
            BoxShadow(
              color: scheme.primary.withValues(alpha: 0.28),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        alignment: Alignment.center,
        child: Text(
          'X',
          style: TextStyle(
            color: scheme.onPrimary,
            fontWeight: FontWeight.w800,
            fontSize: 19,
            letterSpacing: 0.4,
          ),
        ),
      ),
    );
  }
}
