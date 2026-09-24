import 'package:flutter/material.dart';
import 'package:oasx/api/api_client.dart';
import 'package:oasx/modules/common/widgets/add_config_dialog_body.dart';

Future<String?> showAddConfigDialog(
  BuildContext context, {
  VoidCallback? onSubmitting,
  VoidCallback? onSubmitDone,
}) async {
  final initialName = await ApiClient().getNewConfigName();
  final fetchedConfigAll = await ApiClient().getConfigAll();
  final configAll = fetchedConfigAll.isEmpty
      ? <String>['template']
      : fetchedConfigAll;
  final defaultTemplate = configAll.contains('template')
      ? 'template'
      : (configAll.isNotEmpty ? configAll.first : 'template');
  if (!context.mounted) {
    return null;
  }
  return showDialog<String>(
    context: context,
    builder: (dialogContext) => AddConfigDialogBody(
      initialName: initialName,
      configAll: configAll,
      defaultTemplate: defaultTemplate,
      onSubmitting: onSubmitting,
      onSubmitDone: onSubmitDone,
    ),
  );
}
