import 'package:flutter_test/flutter_test.dart';
import 'package:oasx/modules/args/index.dart';

void main() {
  test('ArgsController can load model from json string', () {
    const payload =
        '{"scheduler":[{"name":"enable","value":true,"type":"boolean"}]}';
    final controller = ArgsController();
    controller.loadModelfromStr(payload);

    expect(controller.groups.value.length, 1);
    expect(controller.groups.value.first.groupName, 'scheduler');
  });

  test('multi_enum values are normalized to a string list', () {
    final controller = ArgsController();
    controller.loadModelfromStr(
      '{"task":[{"name":"tasks","value":["a","c"],'
      '"type":"multi_enum","enumEnum":["a","b","c"]}]}',
    );

    final model = controller.groups.value.first.members.first as ArgumentModel;
    expect(model.value, <String>['a', 'c']);
    expect(controller.validateArgument(model, model.value), isNull);
    expect(controller.validateArgument(model, <String>['unknown']), isNotNull);
  });

  test('multi_enum also accepts a JSON encoded stored value', () {
    expect(
      ArgumentModel.normalizeMultiEnumValue('["one","two"]'),
      <String>['one', 'two'],
    );
  });
}
