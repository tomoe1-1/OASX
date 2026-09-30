// 离线静态校验：不启动任何子进程，直接调用 analyzer 库。
//
// 用途：本机 dart/flutter CLI 因环境限制无法创建子进程（dart analyze、
// flutter build 均会崩在 ProcessException），但代码质量仍必须校验。
// 该脚本绕过 CLI，直接把源码喂给 analyzer 的 parse + resolve 流程。
//
// 用法（注意要显式 --packages，让脚本自身能 import 到 analyzer）：
//   dart --packages=script/oc_merged.json run script/offline_check.dart \
//        .dart_tool/package_config.json <file1.dart> [file2.dart ...]
//
// `script/oc_merged.json` = 项目 .dart_tool/package_config.json + analyzer
// 及其依赖（用 script/oc_pkgconfig.json 里的条目补进去，见该文件顶部说明）。
library;

import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/file_system/physical_file_system.dart';

Future<void> main(List<String> args) async {
  if (args.length < 2) {
    stderr.writeln('usage: offline_check.dart <packageConfig> <files...>');
    exitCode = 2;
    return;
  }

  final configPath = File(args.first).absolute.path;
  // analyzer 10.x 对 `includedPaths` 做严格校验：必须是
  // `pathContext.normalize(path) == path`。Windows 上 `WindowsStyle.normalize`
  // 会把盘符大小写、分隔符都改写成自己的规范形式，而 `File.absolute.path`
  // 给出的形式未必与之字节相等（实测分隔符为 `/` 时差 1 个 code unit）。
  // 最稳的办法是**直接把分析器自己的 normalize 结果喂回去**。
  final pathCtx = PhysicalResourceProvider.INSTANCE.pathContext;
  String norm(String p) => pathCtx.normalize(p);
  final files = args.skip(1).map((p) => norm(File(p).absolute.path)).toList();

  // analyzer 10.x 移除了 `packageConfigPath` 参数 —— 它现在按
  // `includedPaths` 向上找最近的 `.dart_tool/package_config.json`。
  // 所以 `configPath` 参数（第一项）只用于**决定收哪个包配置**：
  // 调用方需额外用 `dart --packages=<config> run` 让脚本自身能 import analyzer，
  // 而这里通过把 configPath 的目录也纳入 includedPaths，
  // 让 analyzer 顺着它找到同一份配置。
  final roots = <String>[
    ...files,
    norm(File(configPath).parent.path),
  ];

  final collection = AnalysisContextCollection(
    includedPaths: roots,
    resourceProvider: PhysicalResourceProvider.INSTANCE,
  );

  var errors = 0;
  var warnings = 0;
  var infos = 0;

  for (final file in files) {
    final context = collection.contextFor(file);
    final result = await context.currentSession.getResolvedUnit(file);

    if (result is! ResolvedUnitResult) {
      stderr.writeln('SKIP  $file  (无法解析: ${result.runtimeType})');
      continue;
    }

    for (final diag in result.errors) {
      final sev = diag.severity.name;
      if (sev == 'ERROR') {
        errors++;
      } else if (sev == 'WARNING') {
        warnings++;
      } else {
        infos++;
      }
      final line = result.lineInfo
          .getLocation(diag.offset)
          .let((l) => '${l.lineNumber}:${l.columnNumber}');
      final tag = sev == 'ERROR'
          ? 'ERROR  '
          : sev == 'WARNING'
              ? 'WARN   '
              : 'INFO   ';
      stdout.writeln('$tag ${_rel(file)}:$line  ${diag.message}');
    }
  }

  stdout.writeln('');
  stdout.writeln('=== 汇总 ===');
  stdout.writeln('文件数: ${files.length}');
  stdout.writeln('错误  : $errors');
  stdout.writeln('警告  : $warnings');
  stdout.writeln('提示  : $infos');

  exitCode = errors > 0 ? 1 : 0;
}

String _rel(String abs) {
  final cwd = Directory.current.path;
  return abs.startsWith(cwd) ? abs.substring(cwd.length + 1) : abs;
}

extension<T> on T {
  R let<R>(R Function(T) f) => f(this);
}
