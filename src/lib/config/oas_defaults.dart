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

/// 保留有效的用户目录；目录失效后仅检查程序旁的已部署 OAS。
/// 不扫描其他磁盘，也不把未验证的候选目录交给自动部署。
String resolveStartupOasRootPath({
  String? savedRootPath,
  String? executablePath,
  required bool Function(String root) isValidRoot,
}) {
  final saved = savedRootPath?.trim();
  if (saved != null && saved.isNotEmpty && isValidRoot(saved)) {
    return saved;
  }
  final windows = path.Context(style: path.Style.windows);
  final executable = executablePath ?? Platform.resolvedExecutable;
  final defaultRoot = resolveDefaultOasRootPath(executablePath: executable);
  final siblingRoot = windows.normalize(
    windows.join(
      windows.dirname(executable),
      '..',
      'OnmyojiAutoScript-easy-install',
    ),
  );
  for (final candidate in [defaultRoot, siblingRoot]) {
    if (isValidRoot(candidate)) return candidate;
  }
  // 保留错误目录供设置页修正，不把它当作尚未部署的目标。
  return saved != null && saved.isNotEmpty ? saved : defaultRoot;
}
