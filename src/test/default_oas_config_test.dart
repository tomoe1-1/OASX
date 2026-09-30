import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:oasx/config/oas_defaults.dart';
import 'package:oasx/modules/server/models/deploy_git_config.dart';

void main() {
  test('version folder resolves the sibling private OAS installation', () {
    expect(
      resolveDefaultOasRootPath(
        executablePath: r'C:\Users\12296\Desktop\yys\OASX-2.0.0\oasx.exe',
      ),
      r'C:\Users\12296\Desktop\yys\OAS\OnmyojiAutoScript-easy-install',
    );
  });

  group('private repository defaults', () {
    late Directory root;

    setUp(() {
      root = Directory.systemTemp.createTempSync('oasx-default-config-');
      Directory('${root.path}/config').createSync();
    });

    tearDown(() => root.deleteSync(recursive: true));

    test('empty Git settings use the private repository and self branch', () {
      File(
        '${root.path}/config/deploy.yaml',
      ).writeAsStringSync('Deploy:\n  Git: {}\n');
      final config = DeployGitConfig.read(root.path);
      expect(config.repository, defaultOasRepository);
      expect(config.branch, 'self');
    });

    test('existing explicit repository and branch take precedence', () {
      File('${root.path}/config/deploy.yaml').writeAsStringSync(
        'Deploy:\n  Git:\n    Repository: git@example.test:custom/OAS.git\n    Branch: custom\n',
      );
      final config = DeployGitConfig.read(root.path);
      expect(config.repository, 'git@example.test:custom/OAS.git');
      expect(config.branch, 'custom');
    });
  });
}
