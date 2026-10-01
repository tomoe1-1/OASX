import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:oasx/config/design_tokens.dart';
import 'package:oasx/modules/server/index.dart';
import 'package:oasx/translation/i18n_content.dart';

Widget getTitle(BuildContext context, {String? routePath}) {
  final resolvedRoutePath = _resolveRoutePath(context, routePath: routePath);
  return switch (resolvedRoutePath) {
    '/settings' => const SettingTitle(),
    '/server' => const ServerTitle(),
    _ => const HomeTitleBar(),
  };
}

String _resolveRoutePath(BuildContext context, {String? routePath}) {
  final explicitRoute = routePath?.trim() ?? '';
  if (explicitRoute.isNotEmpty) {
    return explicitRoute;
  }

  final routingCurrent = Get.routing.current;
  if (routingCurrent.isNotEmpty) {
    return routingCurrent;
  }

  final routeName = ModalRoute.of(context)?.settings.name;
  if (routeName != null && routeName.isNotEmpty) {
    return routeName;
  }
  return Get.currentRoute;
}

/// 给浅色标题栏里的白发头像一块深色底，保持小尺寸下的辨识度。
class _BrandIcon extends StatelessWidget {
  const _BrandIcon();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: const Color(0xFF17344C),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF476B84)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Image.asset(
          'assets/images/Icon-app.png',
          width: 30,
          height: 30,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => const Icon(
            Icons.auto_awesome_rounded,
            size: 23,
            color: Color(0xFFE8F5FB),
          ),
        ),
      ),
    );
  }
}

class HomeTitleBar extends StatelessWidget {
  const HomeTitleBar({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 5),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const _BrandIcon(),
          const SizedBox(width: Spacing.mdPlus),
          Flexible(child: _TitleLabel(text: 'OASX / ${I18n.home.tr}')),
        ],
      ),
    );
  }
}

class SettingTitle extends StatelessWidget {
  const SettingTitle({super.key});

  @override
  Widget build(BuildContext context) {
    final backButton = switch (Theme.of(context).platform) {
      TargetPlatform.android => false,
      TargetPlatform.iOS => false,
      _ => true,
    };
    return Padding(
      padding: const EdgeInsets.only(left: 5),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (backButton) ...[
            BackButton(onPressed: _backHomeOrPop),
            const SizedBox(width: Spacing.sm),
          ],
          const _BrandIcon(),
          const SizedBox(width: Spacing.mdPlus),
          Flexible(child: _TitleLabel(text: 'OASX / ${I18n.setting.tr}')),
        ],
      ),
    );
  }

  void _backHomeOrPop() {
    final canPop = Get.key.currentState?.canPop() ?? false;
    if (canPop || Get.previousRoute.isNotEmpty) {
      Get.back();
      return;
    }
    Get.offAllNamed('/home');
  }
}

class ServerTitle extends StatelessWidget {
  const ServerTitle({super.key});

  @override
  Widget build(BuildContext context) {
    final backButton = switch (Theme.of(context).platform) {
      TargetPlatform.android => false,
      TargetPlatform.iOS => false,
      _ => true,
    };
    return Padding(
      padding: const EdgeInsets.only(left: 5),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Obx(() {
            if (backButton &&
                !Get.find<ServerController>().isDeployLoading.value) {
              return const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  BackButton(),
                  SizedBox(width: Spacing.sm),
                ],
              );
            }
            return const SizedBox.shrink();
          }),
          const _BrandIcon(),
          const SizedBox(width: Spacing.mdPlus),
          const Flexible(child: _TitleLabel(text: 'OASX / Server')),
        ],
      ),
    );
  }
}

/// 标题：主名称加重、副标题弱化，形成两级层次
class _TitleLabel extends StatelessWidget {
  const _TitleLabel({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // 形如 "OASX / Home"，拆出品牌名与页面名做差异化着色
    final separatorIndex = text.indexOf(' / ');
    if (separatorIndex <= 0) {
      return Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        softWrap: false,
        style: Theme.of(context).textTheme.titleMedium,
      );
    }
    final brand = text.substring(0, separatorIndex);
    final page = text.substring(separatorIndex + 3);
    final baseStyle = Theme.of(context).textTheme.titleMedium;
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: brand,
            style: baseStyle?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
              color: scheme.primary,
            ),
          ),
          TextSpan(
            text: '  /  ',
            style: baseStyle?.copyWith(color: scheme.outline),
          ),
          TextSpan(
            text: page,
            style: baseStyle?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
      style: baseStyle,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      softWrap: false,
    );
  }
}
