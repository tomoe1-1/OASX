import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';
import 'package:oasx/modules/server/controllers/server_controller.dart';

void main() {
  test('invalid OAS path fails before shell or service operations', () async {
    final temp = Directory.systemTemp.createTempSync('oasx-invalid-deploy-');
    addTearDown(() => temp.deleteSync(recursive: true));
    final controller = ServerController(storage: _UnusedStorage());
    controller.rootPathServer.value = '${temp.path}/missing';

    await expectLater(controller.run(), throwsStateError);
    expect(controller.isDeployLoading.value, isFalse);
    expect(controller.rootPathAuthenticated.value, isFalse);
    expect(controller.shell, isNull);
    expect(await controller.runExclusive(), isFalse);
  });
}

// 路径校验失败必须发生在任何存储、Shell 或服务调用之前。
class _UnusedStorage implements GetStorage {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected storage access: ${invocation.memberName}');
}
