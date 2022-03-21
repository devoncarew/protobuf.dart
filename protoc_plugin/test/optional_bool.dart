import 'package:test/test.dart';

import '../out/protos/optional_bool.pb.dart';

void main() {
  test('Non optional bool default', () {
    var msg = OptionalBoolTest();
    expect(msg.nonOptionalBool, false);
  });

  test('Optional bool default', () {
    var msg = OptionalBoolTest();
    expect(msg.optionalBool, false);
  });

  test('Optional bool, default specified', () {
    var msg = OptionalBoolTest();
    expect(msg.optionalBoolWithDefault, true);
  });
}
