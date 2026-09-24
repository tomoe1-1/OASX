import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:styled_widget/styled_widget.dart';

import 'package:oasx/config/design_tokens.dart';
import 'package:oasx/modules/server/controllers/server_controller.dart';
import 'package:oasx/modules/server/widgets/deploy_import_dialog.dart';
import 'package:oasx/modules/server/widgets/deploy_yaml_editor.dart';
import 'package:oasx/translation/i18n_content.dart';

/// Displays deploy.yaml editing as a collapsible panel matching log panels.
class DeploySectionPanel extends StatefulWidget {
  /// Creates one deploy configuration panel.
  const DeploySectionPanel({super.key, required this.maxHeight});

  /// Maximum content height for the YAML editor.
  final double maxHeight;

  @override
  State<DeploySectionPanel> createState() => _DeploySectionPanelState();
}

class _DeploySectionPanelState extends State<DeploySectionPanel> {
  final DeployYamlEditorController _editorController =
      DeployYamlEditorController();
  bool _collapsed = true;

  @override
  void initState() {
    super.initState();
    _editorController.onCopy = _showCopySnack;
    _editorController.onSave = _showSaveSnack;
    _editorController.onStateChanged = _refreshHeader;
  }

  @override
  Widget build(BuildContext context) {
    return GetX<ServerController>(builder: (controller) {
      final authenticated = controller.rootPathAuthenticated.value;
      return Card(
        margin: const EdgeInsets.only(bottom: Spacing.smPlus),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _DeploySectionHeader(
              authenticated: authenticated,
              collapsed: _collapsed,
              canSave: authenticated && _editorController.canSave,
              canExport: authenticated && !_editorController.hasUnsavedChanges,
              onToggle: _toggleCollapsed,
              onImport: _showImportDialog,
              onExport: _exportDeployFile,
              onCopy: _editorController.copy,
              onSave: _editorController.save,
            ),
            if (authenticated && !_collapsed) ...[
              const Divider(height: 1),
              _buildDeployYamlEditor(widget.maxHeight - 50),
            ],
          ],
        ),
      );
    });
  }

  Widget _buildDeployYamlEditor(double maxHeight) {
    return GetX<ServerController>(builder: (controller) {
      return DeployYamlEditor(
        content: controller.deployContent.value,
        maxHeight: maxHeight,
        onSave: controller.writeDeploy,
        controller: _editorController,
      );
    });
  }

  void _toggleCollapsed() {
    final controller = Get.find<ServerController>();
    if (!controller.rootPathAuthenticated.value) {
      return;
    }
    setState(() {
      _collapsed = !_collapsed;
    });
  }

  void _showCopySnack(String yaml) {
    Clipboard.setData(ClipboardData(text: yaml));
    Get.snackbar(I18n.tip.tr, I18n.copySuccess.tr);
  }

  void _showSaveSnack() {
    Get.snackbar(I18n.tip.tr, I18n.settingSaved.tr);
  }

  void _showImportDialog() {
    Get.dialog(const DeployImportDialog());
  }

  Future<void> _exportDeployFile() async {
    final path = await FilePicker.platform.saveFile(
      fileName: 'deploy.yaml',
      type: FileType.custom,
      allowedExtensions: const ['yaml'],
    );
    if (path == null || path.trim().isEmpty) {
      return;
    }
    final success = Get.find<ServerController>().exportDeployFile(path);
    Get.snackbar(
      I18n.tip.tr,
      success
          ? I18n.deployFileExportSuccess.tr
          : I18n.deployFileExportFailed.tr,
    );
  }

  void _refreshHeader() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() {});
      }
    });
  }
}

class _DeploySectionHeader extends StatelessWidget {
  const _DeploySectionHeader({
    required this.authenticated,
    required this.collapsed,
    required this.canSave,
    required this.canExport,
    required this.onToggle,
    required this.onImport,
    required this.onExport,
    required this.onCopy,
    required this.onSave,
  });

  final bool authenticated;
  final bool collapsed;
  final bool canSave;
  final bool canExport;
  final VoidCallback onToggle;
  final VoidCallback onImport;
  final VoidCallback onExport;
  final VoidCallback onCopy;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: authenticated ? onToggle : null,
      child: Row(
        children: [
          if (!authenticated)
            Icon(Icons.error, color: SemanticColors.danger(context))
                .paddingOnly(right: Spacing.xsPlus),
          Text(
            I18n.setupDeploy.tr,
            textAlign: TextAlign.left,
            style: Theme.of(context).textTheme.titleMedium,
          ).expanded(),
          if (!authenticated)
            Text(
              I18n.rootPathIncorrect.tr,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.error,
                  ),
            ).paddingOnly(right: Spacing.sm),
          IconButton(
            tooltip: I18n.importDeployFile.tr,
            icon: const Icon(Icons.file_download_outlined, size: 18),
            onPressed: authenticated ? onImport : null,
          ),
          IconButton(
            tooltip: I18n.exportDeployFile.tr,
            icon: const Icon(Icons.file_upload_outlined, size: 18),
            onPressed: canExport ? onExport : null,
          ),
          IconButton(
            tooltip: I18n.copy.tr,
            icon: const Icon(Icons.content_copy_rounded, size: 18),
            onPressed: canSave ? onCopy : null,
          ),
          IconButton(
            tooltip: I18n.argsSaveChanges.tr,
            icon: const Icon(Icons.save_rounded, size: 18),
            onPressed: canSave ? onSave : null,
          ),
          Icon(
            collapsed || !authenticated ? Icons.expand_more : Icons.expand_less,
            size: 20,
            color: authenticated ? null : Theme.of(context).disabledColor,
          ),
        ],
      ).paddingAll(Spacing.sm).constrained(height: 48),
    );
  }
}
