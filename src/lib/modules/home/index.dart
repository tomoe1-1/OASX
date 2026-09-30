import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:oasx/config/design_tokens.dart';
import 'package:oasx/modules/common/widgets/add_config_dialog.dart';
import 'package:oasx/modules/common/widgets/appbar.dart';
import 'package:oasx/modules/home/controllers/dashboard_controller.dart';
import 'package:oasx/modules/home/widgets/config_workbench.dart';
import 'package:oasx/modules/home/widgets/home_backdrop.dart';
import 'package:oasx/modules/server/controllers/server_controller.dart';
import 'package:oasx/service/script_service.dart';
import 'package:oasx/translation/i18n_content.dart';
import 'package:oasx/utils/check_version.dart';
import 'package:oasx/utils/platform_utils.dart';

part 'home_view_actions.dart';

class HomeView extends StatefulWidget {
  const HomeView({super.key, this.standalone = true});

  final bool standalone;

  @override
  State<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<HomeView> {
  final scriptService = Get.find<ScriptService>();
  final controller = Get.find<HomeDashboardController>();
  bool _isAddingScript = false;
  bool _isRefreshingScripts = false;

  void _setAddingScript(bool value) {
    if (!mounted) {
      return;
    }
    setState(() {
      _isAddingScript = value;
    });
  }

  void _setRefreshingScripts(bool value) {
    if (!mounted) {
      return;
    }
    setState(() {
      _isRefreshingScripts = value;
    });
  }

  @override
  void initState() {
    super.initState();
    if (!PlatformUtils.isWeb) {
      Future.delayed(const Duration(milliseconds: 300), () {
        checkUpdate();
      });
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      controller.checkStartupConnection();
    });
  }

  @override
  Widget build(BuildContext context) {
    // 底衬包在 `SafeArea` **外层**：渐变要贴着窗口边缘铺满，
    // 否则安全区内的 inset 会切掉画面右缘的渐隐带，露一条硬边。
    final body = HomeBackdrop(
      child: SafeArea(
        child: Stack(
          children: [
            _buildDashboardBody(),
            Obx(() {
              final message = controller.startupLoadingMessage.value;
              if (message.isEmpty) {
                return const SizedBox.shrink();
              }
              return Positioned.fill(
                child: _StartupLoadingOverlay(
                  message: message,
                  autoDeploying: controller.isStartupAutoDeploying.value,
                ),
              );
            }),
          ],
        ),
      ),
    );

    if (!widget.standalone) {
      return body;
    }

    return Scaffold(
      appBar: buildPlatformAppBar(
        context,
        routePath: '/home',
        trailingActions: PlatformUtils.usesDesktopLayout
            ? [
                IconButton(
                  tooltip: I18n.setting.tr,
                  onPressed: () => Get.toNamed('/settings'),
                  icon: const Icon(Icons.settings_rounded),
                ),
              ]
            : const [],
      ),
      body: body,
    );
  }
}

/// 启动状态浮层：**左侧状态面板**，与主界面的左栏同位同宽。
///
/// ## 为什么在左边、为什么没有全屏遮罩
///
/// 这不是本轮随手做的选择，是用户定稿过的方向：「部署的启动状态页放到
/// 左边」「部署页和启动页并行」。此前实现成一个全屏 25% 黑遮罩 +
/// 居中转圈 —— 底衬被压黑、少女完全看不见、信息只有一行字，表现就是
/// 「整块屏幕只有黑块和一个圈」。
///
/// 现在的结构：
/// - **无遮罩**：右侧底衬动画（发丝 + 眨眼）完整可见，这是「启动页」
///   该有的样子，也是参考视频自己的布局 —— 状态在左、少女在右；
/// - **面板几何 = 主界面左栏**（`Spacing.md` 页边距 + 340 栏宽）：
///   启动完成、面板消失、配置列表在同一位置出现，视线没有跳变；
/// - **步骤可见**：部署 → 登录 → 加载配置，三步状态一目了然，
///   转圈不再是「不知道在等什么」的黑洞；
/// - 日志尾行与跳转按钮收在面板内，按钮用 Outlined（次级动作，
///   不是每个按钮都该是 Filled）。
class _StartupLoadingOverlay extends StatefulWidget {
  const _StartupLoadingOverlay({
    required this.message,
    required this.autoDeploying,
  });

  final String message;
  final bool autoDeploying;

  @override
  State<_StartupLoadingOverlay> createState() =>
      _StartupLoadingOverlayState();
}

class _StartupLoadingOverlayState extends State<_StartupLoadingOverlay> {
  /// 自动部署是否发生过 —— 决定「部署」步骤显示 done 还是 pending。
  /// 若 OAS 本来就在跑，登录一次成功就直接进配置阶段，部署步骤
  /// 一直 pending，这是事实：它确实没发生。
  bool _sawAutoDeploy = false;

  @override
  void initState() {
    super.initState();
    if (widget.autoDeploying) {
      _sawAutoDeploy = true;
    }
  }

  @override
  void didUpdateWidget(covariant _StartupLoadingOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.autoDeploying) {
      _sawAutoDeploy = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final windowWidth = MediaQuery.sizeOf(context).width;
    final panelWidth =
        math.min(340.0, math.max(260.0, windowWidth - Spacing.xl * 2));

    final configPhase = widget.message == I18n.homeLoadingConfigDetail;
    final deployStatus = widget.autoDeploying
        ? _StartupStepStatus.active
        : (_sawAutoDeploy ? _StartupStepStatus.done : _StartupStepStatus.pending);
    final loginStatus = widget.autoDeploying
        ? _StartupStepStatus.pending
        : (configPhase ? _StartupStepStatus.done : _StartupStepStatus.active);
    final configStatus =
        configPhase ? _StartupStepStatus.active : _StartupStepStatus.pending;

    return Stack(
      fit: StackFit.expand,
      children: [
        // HomeBackdrop 在此层下方持续以 cover 绘制正面全幅背景，
        // 部署状态页沿用同一幅随窗口缩放的画面与轻微动态。
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: const [
                Color(0xD607101C),
                Color(0x9907101C),
                Color(0x3307101C),
                Color(0x0007101C),
              ],
              stops: const [0, 0.35, 0.72, 1],
            ),
          ),
        ),
        SafeArea(
          child: Align(
            alignment: Alignment.centerLeft,
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                horizontal: Spacing.xl,
                vertical: Spacing.lg,
              ),
              child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0, end: 1),
        duration: Motion.of(context, Motion.slow),
        curve: Curves.easeOutCubic,
        builder: (context, t, child) => Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(-12 * (1 - t), 0),
            child: child,
          ),
        ),
        child: Container(
            width: math.min(430, math.max(panelWidth, windowWidth * 0.32)),
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: const Color(0xEB111D2D),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: const Color(0x555D829F)),
              boxShadow: const [
                BoxShadow(color: Color(0x77030911), blurRadius: 48, offset: Offset(0, 20)),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.auto_awesome_rounded,
                        color: Color(0xFF76BDD8), size: 22),
                    const SizedBox(width: 10),
                    Text('OASX', style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: const Color(0xFFE9F4F9), fontWeight: FontWeight.w700,
                      letterSpacing: 2,
                    )),
                    const Spacer(),
                    Text(I18n.homeStartupOverline.tr,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: const Color(0xFF9AB1C3), letterSpacing: 1,
                        )),
                  ],
                ),
                const SizedBox(height: 26),
                Text(widget.message.tr,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: const Color(0xFFF2F7FA), fontWeight: FontWeight.w700,
                    )),
                const SizedBox(height: 8),
                Text(
                  '${I18n.homeStartupStepDeploy.tr} · '
                  '${I18n.homeStartupStepLogin.tr} · '
                  '${I18n.homeStartupStepConfig.tr}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: const Color(0xFF9AB1C3),
                    )),
                const SizedBox(height: 24),
                const Divider(color: Color(0x445D829F), height: 1),
                const SizedBox(height: 20),
                _StartupStepRow(
                  status: deployStatus,
                  label: I18n.homeStartupStepDeploy.tr,
                ),
                const SizedBox(height: Spacing.sm),
                _StartupStepRow(
                  status: loginStatus,
                  label: I18n.homeStartupStepLogin.tr,
                ),
                const SizedBox(height: Spacing.sm),
                _StartupStepRow(
                  status: configStatus,
                  label: I18n.homeStartupStepConfig.tr,
                ),
                const SizedBox(height: 20),
                LinearProgressIndicator(
                  minHeight: 3,
                  borderRadius: BorderRadius.circular(2),
                  backgroundColor: const Color(0xFF263749),
                  color: const Color(0xFF76BDD8),
                ),
                const _StartupLogTail(),
                const SizedBox(height: 22),
                OutlinedButton.icon(
                  onPressed: () => Get.toNamed('/server'),
                  icon: const Icon(Icons.open_in_new_rounded, size: 16),
                  label: Text(I18n.homeGoDeployPage.tr),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFB9DEF0),
                    side: const BorderSide(color: Color(0x885D829F)),
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                  ),
                ),
              ],
            ),
          ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

enum _StartupStepStatus { pending, active, done }

/// 单个步骤行：小图标 + 标签。
///
/// 状态用**三个维度**同时表达（尺寸/颜色/图标形状都不同），
/// 不只靠颜色 —— 色觉障碍用户也能分清 pending / active / done。
class _StartupStepRow extends StatelessWidget {
  const _StartupStepRow({required this.status, required this.label});

  final _StartupStepStatus status;
  final String label;

  @override
  Widget build(BuildContext context) {
    final Widget icon;
    switch (status) {
      case _StartupStepStatus.done:
        icon = const Icon(Icons.check_rounded,
            size: 18, color: Color(0xFF7CC9A8));
      case _StartupStepStatus.active:
        icon = const SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: Color(0xFF76BDD8),
          ),
        );
      case _StartupStepStatus.pending:
        icon = const Icon(Icons.radio_button_unchecked,
            size: 16, color: Color(0xFF718A9F));
    }
    final TextStyle? labelStyle;
    switch (status) {
      case _StartupStepStatus.active:
        labelStyle = Theme.of(context)
            .textTheme
            .bodyMedium
            ?.copyWith(color: const Color(0xFFF2F7FA), fontWeight: FontWeight.w600);
      case _StartupStepStatus.done:
        labelStyle = Theme.of(context)
            .textTheme
            .bodyMedium
            ?.copyWith(color: const Color(0xFFCADBE4));
      case _StartupStepStatus.pending:
        labelStyle = Theme.of(context)
            .textTheme
            .bodyMedium
            ?.copyWith(color: const Color(0xFF8EA5B8));
    }
    return Row(
      children: [
        SizedBox(width: 18, child: icon),
        const SizedBox(width: Spacing.smPlus),
        Expanded(child: Text(label, style: labelStyle)),
      ],
    );
  }
}

/// 部署日志尾行：最多 3 行，左竖线标示「这是流式日志」，
/// 不做卡片嵌套（面板里再套卡片是视觉噪音）。
class _StartupLogTail extends StatelessWidget {
  const _StartupLogTail();

  @override
  Widget build(BuildContext context) {
    if (!Get.isRegistered<ServerController>()) {
      return const SizedBox.shrink();
    }
    final server = Get.find<ServerController>();
    return Obx(() {
      final lines = server.logs
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .toList();
      if (lines.isEmpty) {
        return const SizedBox.shrink();
      }
      final tail = lines.length > 3 ? lines.sublist(lines.length - 3) : lines;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: Spacing.lg),
          Text(
            I18n.homeStartupLogTitle.tr,
            style: TypeScale.caption(context)?.copyWith(
              color: const Color(0xFF9AB1C3),
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: Spacing.xs),
          Container(
            padding: const EdgeInsets.only(left: Spacing.smPlus),
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(color: Color(0x885D829F), width: 2),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final line in tail)
                  Text(
                    line,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: const Color(0xFFB3C5D2),
                          height: 1.5,
                          fontFeatures: const <FontFeature>[
                            FontFeature.tabularFigures(),
                          ],
                        ),
                  ),
              ],
            ),
          ),
        ],
      );
    });
  }
}
