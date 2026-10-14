import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:oasx/config/global.dart';
import 'package:oasx/service/app_update/app_version_utils.dart';

void main() {
  test('all application version sources agree on 2.4.1', () async {
    expect(GlobalVar.version, 'v2.4.1');
    expect(await AppVersionUtils.getCurrentVersion(), 'v2.4.1');
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec, contains('version: 2.4.1+28'));
    expect(pubspec, contains('msix_version: 2.4.1.0'));
    expect(AppVersionUtils.compareVersion('v2.4.0', 'v2.4.1'), isTrue);
  });
}
