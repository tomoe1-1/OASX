part of 'deploy_yaml_editor.dart';

class _DeployYamlErrorView extends StatelessWidget {
  const _DeployYamlErrorView({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SelectableText(
        message,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.error,
            ),
      ).paddingAll(Spacing.lg),
    );
  }
}
