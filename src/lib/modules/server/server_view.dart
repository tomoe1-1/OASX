import 'package:expansion_tile_group/expansion_tile_group.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:styled_widget/styled_widget.dart';

import 'package:oasx/config/design_tokens.dart';
import 'package:oasx/modules/common/widgets/appbar.dart';
import 'package:oasx/modules/log/log_widget.dart';
import 'package:oasx/modules/server/controllers/server_controller.dart';
import 'package:oasx/modules/server/widgets/deploy_section_panel.dart';
import 'package:oasx/translation/i18n_content.dart';

class ServerView extends StatelessWidget {
  const ServerView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: buildPlatformAppBar(context, routePath: '/server'),
      floatingActionButton: _buildStartServerButton(context),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final serverController = Get.find<ServerController>();
          return SingleChildScrollView(
            child: Column(
              spacing: Spacing.sm,
              children: [
                ExpansionTileGroup(
                  toggleType: ToggleType.expandOnlyCurrent,
                  children: [
                    _buildPathSection(context),
                  ],
                ),
                DeploySectionPanel(
                  maxHeight: constraints.maxHeight - 200,
                ),
                LogWidget(
                  key: ValueKey(serverController.hashCode),
                  controller: serverController,
                  title: I18n.setupLog.tr,
                ).constrained(height: constraints.maxHeight - 200),
              ],
            ).padding(
              right: Spacing.smPlus,
              left: Spacing.smPlus,
            ),
          );
        },
      ),
    );
  }

  ExpansionTileItem _buildPathSection(BuildContext context) {
    final path = GetX<ServerController>(builder: (controller) {
      return <Widget>[
        Text(
          I18n.rootPathServer.tr,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(width: Spacing.smPlus),
        Text(controller.rootPathServer.value),
        TextButton(
          onPressed: () async {
            final selectedDirectory =
                await FilePicker.platform.getDirectoryPath();
            if (selectedDirectory == null) {
              return;
            }
            controller.updateRootPathServer(selectedDirectory);
          },
          child: Text(I18n.selectRootPathServer.tr),
        ),
      ].toRow();
    });
    final pass = GetX<ServerController>(builder: (controller) {
      return <Widget>[
        controller.rootPathAuthenticated.value
            ? Icon(Icons.check_circle, color: SemanticColors.success(context))
            : Icon(Icons.error, color: SemanticColors.danger(context)),
        Text(
          controller.rootPathAuthenticated.value
              ? I18n.rootPathCorrect.tr
              : I18n.rootPathIncorrect.tr,
        ),
      ].toRow();
    });

    return ExpansionTileItem(
      initiallyExpanded: false,
      isHasTopBorder: false,
      isHasBottomBorder: false,
      collapsedBackgroundColor: Theme.of(context)
          .colorScheme
          .secondaryContainer
          .withValues(alpha: 0.28),
      borderRadius: const BorderRadius.all(Radius.circular(Radii.md)),
      title: pass,
      children: [
        path,
        Text(I18n.rootPathServerHelp.tr),
      ],
    );
  }

  Widget _buildStartServerButton(BuildContext context) {
    return GetX<ServerController>(builder: (controller) {
      if (!controller.rootPathAuthenticated.value) {
        return const SizedBox(width: 100, height: 100);
      }
      return FloatingActionButton(
        onPressed: () {
          if (controller.isDeployLoading.value) {
            return;
          }
          controller.run();
        },
        child: Obx(
          () => AnimatedSwitcher(
            duration: Motion.of(context, Motion.normal),
            child: controller.isDeployLoading.value
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 3,
                    ),
                  )
                : const Icon(Icons.auto_mode_rounded),
          ),
        ),
      );
    });
  }

}
