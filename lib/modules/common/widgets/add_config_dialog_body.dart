import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:oasx/api/api_client.dart';
import 'package:oasx/api/config_transfer_models.dart';
import 'package:oasx/config/design_tokens.dart';
import 'package:oasx/modules/common/widgets/config_json_drop_area.dart';
import 'package:oasx/service/script_service.dart';
import 'package:oasx/translation/i18n_content.dart';

class AddConfigDialogBody extends StatefulWidget {
  const AddConfigDialogBody({
    super.key,
    required this.initialName,
    required this.configAll,
    required this.defaultTemplate,
    this.onSubmitting,
    this.onSubmitDone,
  });

  final String initialName;
  final List<String> configAll;
  final String defaultTemplate;
  final VoidCallback? onSubmitting;
  final VoidCallback? onSubmitDone;

  @override
  State<AddConfigDialogBody> createState() => _AddConfigDialogBodyState();
}

class _AddConfigDialogBodyState extends State<AddConfigDialogBody> {
  late String _newName;
  late String _selectedTemplate;
  String? _selectedJsonPath;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _newName = widget.initialName;
    _selectedTemplate = widget.defaultTemplate;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(I18n.configAdd.tr),
      content: _dialogContent(context),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
          child: Text(I18n.cancel.tr),
        ),
        FilledButton(
          onPressed: _isSubmitting ? null : _submit,
          child: _confirmContent(),
        ),
      ],
    );
  }

  Widget _dialogContent(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: (MediaQuery.sizeOf(context).height * 0.55)
            .clamp(300.0, 520.0)
            .toDouble(),
      ),
      child: SizedBox(
        width: 320,
        child: SingleChildScrollView(child: _formContent()),
      ),
    );
  }

  Widget _formContent() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(I18n.newName.tr),
        TextFormField(
          initialValue: _newName,
          enabled: !_isSubmitting,
          onChanged: (value) => _newName = value,
        ),
        const SizedBox(height: Spacing.md),
        Text(I18n.configCopyFromExist.tr),
        _templateDropdown(),
        const SizedBox(height: Spacing.md),
        Text(I18n.configImportJson.tr),
        const SizedBox(height: Spacing.sm),
        ConfigJsonDropArea(
          selectedPath: _selectedJsonPath,
          enabled: !_isSubmitting,
          onSelected: _setJsonPath,
        ),
      ],
    );
  }

  Widget _templateDropdown() {
    return DropdownButton<String>(
      value: _selectedTemplate,
      menuMaxHeight: 300,
      isExpanded: true,
      items: widget.configAll
          .map<DropdownMenuItem<String>>(
            (e) => DropdownMenuItem(value: e, child: Text(e)),
          )
          .toList(),
      onChanged: _isSubmitting ? null : _setTemplate,
    );
  }

  Widget _confirmContent() {
    if (!_isSubmitting) {
      return Text(I18n.confirm.tr);
    }
    return const SizedBox(
      width: 16,
      height: 16,
      child: CircularProgressIndicator(strokeWidth: 2),
    );
  }

  void _setTemplate(String? value) {
    if (value == null) {
      return;
    }
    setState(() {
      _selectedTemplate = value;
    });
  }

  void _setJsonPath(String path) {
    setState(() {
      _selectedJsonPath = path;
    });
  }

  Future<void> _submit() async {
    final normalizedName = _newName.trim();
    if (normalizedName.isEmpty) {
      Get.snackbar(I18n.tip.tr, I18n.nameCannotEmpty.tr);
      return;
    }
    _setSubmitting(true);
    widget.onSubmitting?.call();
    try {
      final resultName = await _submitConfig(normalizedName);
      if (mounted) {
        Navigator.of(context).pop(resultName);
      }
    } catch (e) {
      final message = e is ConfigTransferException
          ? e.message
          : I18n.configImportFailed.tr;
      Get.snackbar(I18n.tip.tr, message);
    } finally {
      _setSubmitting(false);
      widget.onSubmitDone?.call();
    }
  }

  Future<String> _submitConfig(String normalizedName) {
    final importedPath = _selectedJsonPath;
    return importedPath == null
        ? _copyConfig(normalizedName)
        : _importConfig(normalizedName, importedPath);
  }

  Future<String> _copyConfig(String normalizedName) async {
    final navList = await ApiClient().configCopy(
      normalizedName,
      _selectedTemplate,
    );
    final scripts = navList.where((e) => e != 'Home');
    await Get.find<ScriptService>().syncScriptsAndConnect(
      scripts: scripts,
      configName: normalizedName,
    );
    return normalizedName;
  }

  Future<String> _importConfig(String normalizedName, String path) {
    return Get.find<ScriptService>().importConfig(
      configName: normalizedName,
      filePath: path,
    );
  }

  void _setSubmitting(bool value) {
    if (!mounted || _isSubmitting == value) {
      return;
    }
    setState(() {
      _isSubmitting = value;
    });
  }
}
