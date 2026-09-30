part of 'index.dart';

extension _HomeViewActions on _HomeViewState {
  Widget _buildDashboardBody() {
    return Obx(() {
      if (controller.startupLoadingMessage.value.isNotEmpty) {
        return const SizedBox.expand();
      }
      if (controller.isStartupConnectionFailed.value &&
          scriptService.scriptOrderList.isEmpty) {
        return _buildConnectionFailedView();
      }
      return Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: ConfigWorkbench(
          controller: controller,
          scriptService: scriptService,
          loadingAddScript: _isAddingScript,
          refreshingScripts: _isRefreshingScripts,
          onAddScriptTap: _onAddScriptCardTap,
          onRefreshScriptsTap: _onRefreshScriptsTap,
        ),
      );
    });
  }

  Widget _buildConnectionFailedView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Spacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Obx(() {
              if (controller.isStartupChecking.value) {
                return const SizedBox(
                  width: 36,
                  height: 36,
                  child: CircularProgressIndicator(strokeWidth: 2.6),
                );
              }
              return Icon(
                Icons.cloud_off_rounded,
                size: 34,
                color: Theme.of(context).colorScheme.outline,
              );
            }),
            const SizedBox(height: Spacing.md),
            Text(I18n.homeConnectionRetryHint.tr, textAlign: TextAlign.center),
            if (Get.isRegistered<ServerController>() &&
                !Get.find<ServerController>().rootPathAuthenticated.value) ...[
              const SizedBox(height: Spacing.md),
              const Text('OAS 目录无效，请重新选择安装目录。'),
              const SizedBox(height: Spacing.sm),
              SelectableText(
                Get.find<ServerController>().rootPathServer.value,
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: Spacing.md),
            OutlinedButton.icon(
              onPressed: () => Get.toNamed('/server'),
              icon: const Icon(Icons.folder_open_rounded),
              label: Text(I18n.homeGoDeployPage.tr),
            ),
            const SizedBox(height: Spacing.sm),
            TextButton.icon(
              onPressed: controller.isStartupChecking.value
                  ? null
                  : controller.retryStartupConnection,
              icon: const Icon(Icons.refresh_rounded),
              label: Text(I18n.homeConnectionRetryAction.tr),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _onAddScriptCardTap() async {
    if (_isAddingScript) {
      return;
    }
    final createdConfig = await showAddConfigDialog(
      context,
      onSubmitting: () => _setAddingScript(true),
      onSubmitDone: () {
        _setAddingScript(false);
        controller.syncWorkspaceState();
      },
    );
    if (createdConfig == null || createdConfig.isEmpty) {
      return;
    }
    controller.setActiveScript(createdConfig);
  }

  Future<void> _onRefreshScriptsTap() async {
    if (_isRefreshingScripts) {
      return;
    }
    _setRefreshingScripts(true);
    try {
      await controller.retryStartupConnection();
      controller.syncWorkspaceState();
    } catch (_) {
      Get.snackbar(I18n.loginError.tr, I18n.loginErrorMsg.tr);
    } finally {
      _setRefreshingScripts(false);
    }
  }
}
