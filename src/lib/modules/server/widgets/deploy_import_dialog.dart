import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:styled_widget/styled_widget.dart';
import 'package:super_drag_and_drop/super_drag_and_drop.dart';

import 'package:oasx/modules/server/controllers/server_controller.dart';
import 'package:oasx/translation/i18n_content.dart';
import 'package:oasx/config/design_tokens.dart';

/// Dialog for importing an external YAML file as local deploy.yaml.
class DeployImportDialog extends StatefulWidget {
  /// Creates one deploy import dialog.
  const DeployImportDialog({super.key});

  @override
  State<DeployImportDialog> createState() => _DeployImportDialogState();
}

class _DeployImportDialogState extends State<DeployImportDialog> {
  String? _selectedPath;
  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(I18n.importDeployFile.tr),
      content: _buildDropArea(context),
      actions: [
        TextButton(onPressed: Get.back, child: Text(I18n.cancel.tr)),
        FilledButton(
          onPressed: _selectedPath == null ? null : _confirmImport,
          child: Text(I18n.confirm.tr),
        ),
      ],
    );
  }

  Widget _buildDropArea(BuildContext context) {
    final theme = Theme.of(context);
    return DropRegion(
      formats: const [Formats.fileUri],
      hitTestBehavior: HitTestBehavior.opaque,
      onDropOver: _onDropOver,
      onDropEnter: (_) => _setDragging(true),
      onDropLeave: (_) => _setDragging(false),
      onDropEnded: (_) => _setDragging(false),
      onPerformDrop: _onPerformDrop,
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.sm),
        onTap: _pickFile,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: _dragging
                ? theme.colorScheme.primaryContainer.withValues(alpha: 0.28)
                : theme.colorScheme.surfaceContainerHighest
                    .withValues(alpha: 0.34),
            border: Border.all(
              color: _dragging
                  ? theme.colorScheme.primary
                  : theme.colorScheme.outlineVariant,
              style: BorderStyle.solid,
            ),
            borderRadius: BorderRadius.circular(Radii.sm),
          ),
          child: Center(child: _buildDropText(theme)).paddingAll(Spacing.lgPlus),
        ),
      ),
    ).constrained(width: 360, height: 140);
  }

  DropOperation _onDropOver(DropOverEvent event) {
    final canImport = event.session.items.any(
      (item) => item.canProvide(Formats.fileUri),
    );
    _setDragging(canImport);
    return canImport ? DropOperation.copy : DropOperation.none;
  }

  Future<void> _onPerformDrop(PerformDropEvent event) async {
    for (final item in event.session.items) {
      final reader = item.dataReader;
      if (reader == null || !reader.canProvide(Formats.fileUri)) {
        continue;
      }
      reader.getValue<Uri>(
        Formats.fileUri,
        (uri) {
          if (uri == null) {
            return;
          }
          _selectPath(uri.toFilePath());
        },
        onError: (_) => Get.snackbar(
          I18n.tip.tr,
          I18n.deployFileImportFailed.tr,
        ),
      );
      return;
    }
    Get.snackbar(I18n.tip.tr, I18n.deployFileImportFailed.tr);
  }

  Widget _buildDropText(ThemeData theme) {
    final selectedPath = _selectedPath;
    if (selectedPath == null) {
      return Text(
        I18n.selectDeployFile.tr,
        textAlign: TextAlign.center,
        style: theme.textTheme.bodyMedium,
      );
    }
    return Text(
      selectedPath.split(RegExp(r'[\\/]')).last,
      textAlign: TextAlign.center,
      style: theme.textTheme.titleSmall,
    );
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['yaml'],
      allowMultiple: false,
    );
    final path = result?.files.single.path;
    if (path == null) {
      return;
    }
    _selectPath(path);
  }

  void _selectPath(String path) {
    if (!path.toLowerCase().endsWith('.yaml')) {
      Get.snackbar(I18n.tip.tr, I18n.deployFileNameInvalid.tr);
      return;
    }
    setState(() {
      _dragging = false;
      _selectedPath = path;
    });
  }

  void _setDragging(bool dragging) {
    if (!mounted || _dragging == dragging) {
      return;
    }
    setState(() {
      _dragging = dragging;
    });
  }

  void _confirmImport() {
    final path = _selectedPath;
    if (path == null) {
      return;
    }
    final success = Get.find<ServerController>().importDeployFile(path);
    if (!success) {
      Get.snackbar(I18n.tip.tr, I18n.deployFileImportFailed.tr);
      return;
    }
    Get.back();
    Get.snackbar(I18n.tip.tr, I18n.deployFileImportSuccess.tr);
  }
}
