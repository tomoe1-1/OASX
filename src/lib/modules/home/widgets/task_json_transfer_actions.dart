import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:oasx/api/api_client.dart';
import 'package:oasx/api/config_transfer_models.dart';
import 'package:oasx/modules/args/index.dart';
import 'package:oasx/modules/home/widgets/task_json_import_dialog.dart';
import 'package:oasx/service/websocket_service.dart';
import 'package:oasx/translation/i18n_content.dart';
import 'package:oasx/utils/browser_download_io.dart'
    if (dart.library.html) 'package:oasx/utils/browser_download_web.dart';
import 'package:oasx/utils/file_save_stub.dart'
    if (dart.library.io) 'package:oasx/utils/file_save_io.dart';

class TaskJsonTransferActions extends StatefulWidget {
  const TaskJsonTransferActions({
    super.key,
    required this.configName,
    required this.taskName,
    required this.onImported,
  });

  final String configName;
  final String taskName;
  final Future<void> Function() onImported;

  @override
  State<TaskJsonTransferActions> createState() =>
      _TaskJsonTransferActionsState();
}

class _TaskJsonTransferActionsState extends State<TaskJsonTransferActions> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ActionButton(
          tooltip: I18n.taskJsonImport.tr,
          icon: Icons.file_download_outlined,
          onPressed: _busy ? null : _importJson,
        ),
        _ActionButton(
          tooltip: I18n.taskJsonExport.tr,
          icon: Icons.file_upload_outlined,
          onPressed: _busy ? null : _exportJson,
        ),
        _ActionButton(
          tooltip: I18n.taskJsonCopy.tr,
          icon: Icons.content_copy_rounded,
          onPressed: _busy ? null : _copyJson,
        ),
      ],
    );
  }

  Future<void> _importJson() async {
    final request = await Get.dialog<TaskJsonImportRequest>(
      const TaskJsonImportDialog(),
    );
    if (request == null) return;
    final argsController = Get.find<ArgsController>();
    if (argsController.hasDraftChanges && !await _confirmDiscardDraft()) {
      return;
    }
    await _runBusy(() async {
      if (argsController.hasDraftChanges) {
        await argsController.discardDraftChanges();
      }
      await ApiClient().importTaskJson(
        configName: widget.configName,
        taskName: widget.taskName,
        jsonText: request.jsonText,
        filePath: request.filePath,
        fileBytes: request.fileBytes,
        fileName: request.fileName,
      );
      await widget.onImported();
      await Get.find<WebSocketService>().send(
        widget.configName,
        'get_schedule',
      );
      Get.snackbar(I18n.tip.tr, I18n.taskJsonImportSuccess.tr);
    }, I18n.taskJsonImportFailed.tr);
  }

  Future<void> _exportJson() async {
    await _runBusy(() async {
      final payload = await ApiClient().exportTaskJson(
        configName: widget.configName,
        taskName: widget.taskName,
      );
      if (kIsWeb) {
        await downloadBytesToBrowser(
          payload.bytes,
          payload.fileName,
          mimeType: 'application/json',
        );
        Get.snackbar(I18n.tip.tr, I18n.taskJsonExportSuccess.tr);
        return;
      }
      final path = await FilePicker.platform.saveFile(
        fileName: payload.fileName,
        type: FileType.custom,
        allowedExtensions: const ['json'],
        bytes: payload.bytes,
      );
      if (path == null || path.trim().isEmpty) return;
      if (shouldWritePickedSavePath()) {
        await saveBytesToPath(path, payload.bytes);
      }
      Get.snackbar(I18n.tip.tr, I18n.taskJsonExportSuccess.tr);
    }, I18n.taskJsonExportFailed.tr);
  }

  Future<void> _copyJson() async {
    await _runBusy(() async {
      final payload = await ApiClient().copyTaskJson(
        configName: widget.configName,
        taskName: widget.taskName,
      );
      const encoder = JsonEncoder.withIndent('  ');
      final text = payload is String ? payload : encoder.convert(payload);
      await Clipboard.setData(ClipboardData(text: text));
      Get.snackbar(I18n.tip.tr, I18n.taskJsonCopySuccess.tr);
    }, I18n.taskJsonCopyFailed.tr);
  }

  Future<bool> _confirmDiscardDraft() async {
    final result = await Get.defaultDialog<bool>(
      title: I18n.taskJsonImport.tr,
      middleText: I18n.taskJsonDiscardDraftPrompt.tr,
      textConfirm: I18n.confirm.tr,
      textCancel: I18n.cancel.tr,
      onConfirm: () => Get.back(result: true),
      onCancel: () {},
    );
    return result == true;
  }

  Future<void> _runBusy(Future<void> Function() action, String fallback) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      final message = e is ConfigTransferException ? e.message : fallback;
      Get.snackbar(I18n.tip.tr, message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
    );
  }
}
