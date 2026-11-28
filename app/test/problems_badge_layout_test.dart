import 'package:alula_app/workbench/layout_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const field = 'problemsBadgeHidden';

  test('Problems badge visibility accepts only the persisted hidden flag', () {
    final original = defaultLayout();
    final legacy = original.toJson();
    expect(legacy, isNot(contains(field)));

    for (final value in <Object?>[null, false, 'true', 1]) {
      final layout = WbNode.fromJson({...legacy, field: value}) as WbSplit;
      expect(layout.problemsBadgeHidden, isFalse);
      expect(layout.toJson(), isNot(contains(field)));
    }

    original.problemsBadgeHidden = true;
    final serialized = original.toJson();
    expect(serialized[field], isTrue);
    final restored = WbNode.fromJson(serialized) as WbSplit;
    expect(restored.problemsBadgeHidden, isTrue);
    expect(restored.toJson(), serialized);

    restored.problemsBadgeHidden = false;
    expect(restored.toJson(), legacy);
  });
}
