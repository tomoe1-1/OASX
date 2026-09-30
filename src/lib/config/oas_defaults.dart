import 'dart:io';

import 'package:path/path.dart' as path;

/// 与本机 OAS 部署配置一致的私库和分支。
const String defaultOasRepository = 'git@github-oas:tomoe1-1/OAS-tomoe.git';
const String defaultOasBranch = 'self';

/// OASX 放在 yys 的版本目录内，OAS 位于同级 OAS 目录。
String resolveDefaultOasRootPath({String? executablePath}) {
  final windows = path.Context(style: path.Style.windows);
  final executable = executablePath ?? Platform.resolvedExecutable;
  return windows.normalize(
    windows.join(
      windows.dirname(executable),
      '..',
      'OAS',
      'OnmyojiAutoScript-easy-install',
    ),
  );
}
