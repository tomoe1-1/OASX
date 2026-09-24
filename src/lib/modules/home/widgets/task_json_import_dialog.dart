import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:oasx/translation/i18n_content.dart';
import 'package:super_drag_and_drop/super_drag_and_drop.dart';
import 'package:oasx/config/design_tokens.dart';

class TaskJsonImportRequest {
  const TaskJsonImportRequest({
    this.jsonText,
    this.filePath,
    this.fileBytes,
    this.fileName,
  });

  final String? jsonText;
  final String? filePath;
  final Uint8List? fileBytes;
  final String? fileName;
}

class TaskJsonImportDialog extends StatefulWidget {
  const TaskJsonImportDialog({super.key});

  @override
  State<TaskJsonImportDialog> createState() => _TaskJsonImportDialogState();
}

class _TaskJsonImportDialogState extends State<TaskJsonImportDialog> {
  final TextEditingController _textController = TextEditingController();
  String? _filePath;
  Uint8List? _fileBytes;
  String? _fileName;
  String? _errorText;
  bool _dragging = false;

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(I18n.taskJsonImport.tr),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              I18n.taskJsonChooseOne.tr,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: Spacing.sm),
            TextField(
              controller: _textController,
              minLines: 2,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: I18n.taskJsonTextHint.tr,
                hintStyle: Theme.of(context).textTheme.bodyMedium,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: Spacing.md),
            _buildDropArea(context),
            if (_errorText != null) ...[
              const SizedBox(height: Spacing.sm),
              Text(
                _errorText!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Get.back<TaskJsonImportRequest>(),
          child: Text(I18n.cancel.tr),
        ),
        FilledButton(onPressed: _submit, child: Text(I18n.taskJsonImport.tr)),
      ],
    );
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['json'],
      withData: kIsWeb,
    );
    final picked = result?.files.single;
    if (picked == null) return;
    _selectFile(
      fileName: picked.name,
      filePath: picked.path,
      fileBytes: picked.bytes,
    );
  }

  Widget _buildDropArea(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 320,
      height: 120,
      child: DropRegion(
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
                  : theme.colorScheme.surfaceContainerHighest.withValues(
                      alpha: 0.34,
                    ),
              border: Border.all(
                color: _dragging
                    ? theme.colorScheme.primary
                    : theme.colorScheme.outlineVariant,
              ),
              borderRadius: BorderRadius.circular(Radii.sm),
            ),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(Spacing.md),
                child: Text(
                  _fileName ?? I18n.taskJsonSelectFile.tr,
                  textAlign: TextAlign.center,
                  style: _fileName == null
                      ? theme.textTheme.bodyMedium
                      : theme.textTheme.titleSmall,
                ),
              ),
            ),
          ),
        ),
      ),
    );
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
      if (reader == null || !reader.canProvide(Formats.fileUri)) continue;
      reader.getValue<Uri>(
        Formats.fileUri,
        (uri) {
          if (uri == null) return;
          final path = uri.toFilePath();
          _selectFile(fileName: _fileNameFromPath(path), filePath: path);
        },
        onError: (_) => Get.snackbar(I18n.tip.tr, I18n.taskJsonImportFailed.tr),
      );
      return;
    }
    Get.snackbar(I18n.tip.tr, I18n.taskJsonImportFailed.tr);
  }

  void _selectFile({
    required String fileName,
    String? filePath,
    Uint8List? fileBytes,
  }) {
    if (!fileName.toLowerCase().endsWith('.json')) {
      setState(() => _errorText = I18n.taskJsonFileInvalid.tr);
      return;
    }
    setState(() {
      _fileName = fileName;
      _filePath = filePath;
      _fileBytes = fileBytes;
      _errorText = null;
      _dragging = false;
    });
  }

  void _setDragging(bool dragging) {
    if (!mounted || _dragging == dragging) return;
    setState(() => _dragging = dragging);
  }

  void _submit() {
    final text = _textController.text.trim();
    final hasFile = _fileName != null;
    final hasText = text.isNotEmpty;
    if (hasFile == hasText) {
      setState(() => _errorText = I18n.taskJsonSourceInvalid.tr);
      return;
    }
    Get.back(
      result: TaskJsonImportRequest(
        jsonText: hasText ? text : null,
        filePath: _filePath,
        fileBytes: _fileBytes,
        fileName: _fileName,
      ),
    );
  }

  String _fileNameFromPath(String path) {
    final segments = path.split(RegExp(r'[\\/]'));
    return segments.isEmpty ? path : segments.last;
  }
}
