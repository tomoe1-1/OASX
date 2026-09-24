import 'package:flutter_test/flutter_test.dart';
import 'package:oasx/modules/server/models/deploy_yaml_document.dart';

void main() {
  const sampleYaml = '''
Deploy:
  Git:
    # URL of AzurLaneAutoScript repository
    # [Other] Use 'https://github.com/LmeSzinc/AzurLaneAutoScript'
    Repository: https://github.com/AzurTian/OnmyojiAutoScript.git
    # Branch of Alas
    Branch: mine
    # Update Alas at startup
    AutoUpdate: false
    # Whether to keep local changes during update
    KeepLocalChanges: true
''';

  test('parse deploy yaml as readonly sections and editable leaf values', () {
    final document = DeployYamlDocument.parse(sampleYaml);

    expect(document.hasError, isFalse);
    expect(document.roots.single.key, 'Deploy');
    expect(document.roots.single.children.single.key, 'Git');

    final values = document.editableValues.toList();
    expect(values.map((line) => line.key), [
      'Repository',
      'Branch',
      'AutoUpdate',
      'KeepLocalChanges',
    ]);
    expect(values[0].value, 'https://github.com/AzurTian/OnmyojiAutoScript.git');
    expect(values[2].isBoolean, isTrue);
  });

  test('serialize preserves comments and only changes edited values', () {
    final document = DeployYamlDocument.parse(sampleYaml);
    final values = document.editableValues.toList();

    document.updateValue(values[0].index, 'https://example.com/repo.git');
    document.updateValue(values[1].index, 'master');
    document.updateValue(values[2].index, 'true');

    expect(document.serialize(), '''
Deploy:
  Git:
    # URL of AzurLaneAutoScript repository
    # [Other] Use 'https://github.com/LmeSzinc/AzurLaneAutoScript'
    Repository: https://example.com/repo.git
    # Branch of Alas
    Branch: master
    # Update Alas at startup
    AutoUpdate: true
    # Whether to keep local changes during update
    KeepLocalChanges: true
''');
  });

  test('serialize preserves inline comments after edited values', () {
    final document = DeployYamlDocument.parse('Deploy:\n  Git:\n    Branch: dev # branch name');
    final branch = document.editableValues.single;

    document.updateValue(branch.index, 'master');

    expect(document.serialize(), 'Deploy:\n  Git:\n    Branch: master # branch name');
  });
}
