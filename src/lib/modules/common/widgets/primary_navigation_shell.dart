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
                    // 用 `Surfaces.divider` 而不是裸 `VerticalDivider`：
                    // 后者取 Material 默认的 `outlineVariant @ 全 alpha`，
                    // 与本项目 `dividerTheme` 里收敛过的同一条线颜色不一致。
                    // 同一屏里出现两条深浅不同的「同一种线」是最容易被
                    // 看出来的不讲究。
                    const _ShellDivider(),
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

/// 导航栏与内容区之间的竖向分隔线。
///
/// 取 `Surfaces.divider(context)`，与 `dividerTheme` / 手写卡片描边
/// 保持同一种颜色，避免同屏出现两条深浅不同的分隔线。
class _ShellDivider extends StatelessWidget {
  const _ShellDivider();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 1,
      child: ColoredBox(color: Surfaces.divider(context)),
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

/// 侧边栏顶部的品牌标识。
///
/// ## 为什么放弃原来的渐变方块
///
/// 旧实现是一个 40×40 圆角块：`primary → tertiary` 对角渐变、外挂
/// primary @28% 的模糊发光、中央一个 `w800` 大写 `X`。这三样恰好是
/// 「AI 生成 UI」最典型的组合（双色渐变 + 霓虹发光 + 单字母方标），
/// 信息量为零，却抢走了整个左栏的视觉注意力 —— 而左栏的主角应该是
/// **导航目的地**，不是 Logo。
///
/// ## 新做法：把品牌压成一条「状态色脊」
///
/// 用一根 3px 宽的竖向色条 + 紧邻的产品名，构成 L 形锚点：
///
/// - 色条用 `primary` 纯色（不要渐变 —— 渐变在这个尺寸上只会显脏）
/// - 产品名用界面已有的 `titleSmall` 字重，不做加权夸张
/// - 整体高度压到与一个图标齐平，不抢占第一视线的落点
///
/// 颜色仍是主题色，换种子时整块跟着走；但因为它足够小、足够安静，
/// 只做「你在哪个产品里」的定位，不参与信息表达。
class _RailBrandMark extends StatelessWidget {
  const _RailBrandMark({required this.scheme});

  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 品牌色条：3px 宽、20px 高、全圆角。纯色，不渐变、不发光。
          Container(
            width: 3,
            height: 20,
            decoration: BoxDecoration(
              color: scheme.primary,
              borderRadius: BorderRadius.circular(Radii.pill),
            ),
          ),
          const SizedBox(height: Spacing.xs),
          Text(
            'OASX',
            style: TextStyle(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
              // 11px + 0.8 字距：小字号下需要放开字距才读得清，
              // 这是排版常规则，不是为了「高级感」而加的装饰性字距。
              fontSize: 11,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }
}
