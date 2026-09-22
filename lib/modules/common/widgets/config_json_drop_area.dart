import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:oasx/translation/i18n_content.dart';
import 'package:styled_widget/styled_widget.dart';
import 'package:super_drag_and_drop/super_drag_and_drop.dart';
import 'package:oasx/config/design_tokens.dart';

class ConfigJsonDropArea extends StatefulWidget {
  const ConfigJsonDropArea({
    super.key,
    required this.selectedPath,
    required this.enabled,
    required this.onSelected,
  });

  final String? selectedPath;
  final bool enabled;
  final ValueChanged<String> onSelected;

  @override
  State<ConfigJsonDropArea> createState() => _ConfigJsonDropAreaState();
}

class _ConfigJsonDropAreaState extends State<ConfigJsonDropArea> {
  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DropRegion(
      formats: const [Formats.fileUri],
      hitTestBehavior: HitTestBehavior.opaque,
      onDropOver: _onDropOver,
      onDropEnter: (_) => _setDragging(widget.enabled),
      onDropLeave: (_) => _setDragging(false),
      onDropEnded: (_) => _setDragging(false),
      onPerformDrop: _onPerformDrop,
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.sm),
        onTap: widget.enabled ? _pickFile : null,
        child: DecoratedBox(
          decoration: _decoration(theme),
          child: Center(child: _dropText(theme)).paddingAll(Spacing.lgPlus),
        ),
      ),
    ).constrained(width: 320, height: 120);
  }

  BoxDecoration _decoration(ThemeData theme) {
    return BoxDecoration(
      color: _dragging
          ? theme.colorScheme.primaryContainer.withValues(alpha: 0.28)
          : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.34),
      border: Border.all(
        color: _dragging
            ? theme.colorScheme.primary
            : theme.colorScheme.outlineVariant,
      ),
      borderRadius: BorderRadius.circular(Radii.sm),
    );
  }

  DropOperation _onDropOver(DropOverEvent event) {
    if (!widget.enabled) {
      return DropOperation.none;
    }
    final canImport = event.session.items.any(
      (item) => item.canProvide(Formats.fileUri),
    );
    _setDragging(canImport);
    return canImport ? DropOperation.copy : DropOperation.none;
  }

  Future<void> _onPerformDrop(PerformDropEvent event) async {
    if (!widget.enabled) {
      return;
    }
    for (final item in event.session.items) {
      final reader = item.dataReader;
      if (reader == null || !reader.canProvide(Formats.fileUri)) {
        continue;
      }
      reader.getValue<Uri>(
        Formats.fileUri,
        (uri) {
          if (uri != null) {
            _selectPath(uri.toFilePath());
          }
        },
        onError: (_) => Get.snackbar(I18n.tip.tr, I18n.configImportFailed.tr),
      );
      return;
    }
    Get.snackbar(I18n.tip.tr, I18n.configImportFailed.tr);
  }

  Widget _dropText(ThemeData theme) {
    final selectedPath = widget.selectedPath;
    if (selectedPath == null) {
      return Text(
        I18n.selectConfigJsonFile.tr,
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
      allowedExtensions: const ['json'],
      allowMultiple: false,
    );
    final path = result?.files.single.path;
    if (path != null) {
      _selectPath(path);
    }
  }

  void _selectPath(String path) {
    if (!path.toLowerCase().endsWith('.json')) {
      Get.snackbar(I18n.tip.tr, I18n.configJsonFileInvalid.tr);
      return;
    }
    _setDragging(false);
    widget.onSelected(path);
  }

  void _setDragging(bool value) {
    if (!mounted || _dragging == value) {
      return;
    }
    setState(() {
      _dragging = value;
    });
  }
}
