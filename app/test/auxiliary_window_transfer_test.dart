import 'package:alula_app/workbench/auxiliary_window_transfer.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AuxiliaryWindowBounds', () {
    test('parses finite bounds including displays left of the primary screen',
        () {
      final snapshot = AuxiliaryWindowBounds.tryParse({
        'windowId': 'aux-left',
        'sequence': 4,
        'left': -800,
        'top': 40,
        'width': 600,
        'height': 500,
      });

      expect(snapshot, isNotNull);
      expect(snapshot!.bounds, const Rect.fromLTWH(-800, 40, 600, 500));
      expect(AuxiliaryWindowBounds.tryParse(snapshot.toMap())?.sequence, 4);
    });

    test('rejects malformed or non-finite bounds', () {
      for (final value in <Object?>[
        null,
        <String, Object?>{},
        {
          'windowId': '',
          'sequence': 1,
          'left': 0,
          'top': 0,
          'width': 10,
          'height': 10,
        },
        {
          'windowId': 'aux',
          'sequence': 0,
          'left': 0,
          'top': 0,
          'width': 10,
          'height': 10,
        },
        {
          'windowId': 'aux',
          'sequence': 1,
          'left': double.nan,
          'top': 0,
          'width': 10,
          'height': 10,
        },
        {
          'windowId': 'aux',
          'sequence': 1,
          'left': 0,
          'top': 0,
          'width': double.infinity,
          'height': 10,
        },
        {
          'windowId': 'aux',
          'sequence': 1,
          'left': 0,
          'top': 0,
          'width': 0,
          'height': 10,
        },
      ]) {
        expect(AuxiliaryWindowBounds.tryParse(value), isNull);
      }
    });
  });

  group('AuxiliaryWindowBoundsRegistry', () {
    AuxiliaryWindowBounds bounds(
      String id,
      int sequence,
      Rect rect,
    ) =>
        AuxiliaryWindowBounds(
          windowId: id,
          sequence: sequence,
          bounds: rect,
        );

    test('uses half-open rectangles and rejects ambiguous overlaps', () {
      final registry = AuxiliaryWindowBoundsRegistry();
      registry.update(
        bounds('left', 1, const Rect.fromLTWH(-100, 0, 100, 100)),
      );
      registry.update(
        bounds('right', 1, const Rect.fromLTWH(0, 0, 100, 100)),
      );

      expect(registry.uniqueWindowAt(const Offset(-1, 50)), 'left');
      expect(registry.uniqueWindowAt(const Offset(0, 50)), 'right');
      expect(registry.windowCountAt(const Offset(0, 50)), 1);
      expect(registry.uniqueWindowAt(const Offset(100, 100)), isNull);
      expect(registry.windowCountAt(const Offset(100, 100)), 0);

      registry.update(
        bounds('overlap', 1, const Rect.fromLTWH(20, 20, 40, 40)),
      );
      expect(registry.uniqueWindowAt(const Offset(30, 30)), isNull,
          reason: 'overlapping native windows do not guess a recipient');
      expect(registry.windowCountAt(const Offset(30, 30)), 2);
      expect(registry.uniqueWindowAt(const Offset(double.nan, 30)), isNull);
      expect(registry.windowCountAt(const Offset(double.nan, 30)), 0);
    });

    test('ignores stale sequence numbers and allows newer bounds', () {
      final registry = AuxiliaryWindowBoundsRegistry();
      expect(
        registry.update(
          bounds('aux', 2, const Rect.fromLTWH(100, 100, 200, 200)),
        ),
        isTrue,
      );
      expect(
        registry.update(
          bounds('aux', 1, const Rect.fromLTWH(0, 0, 20, 20)),
        ),
        isFalse,
      );
      expect(registry.uniqueWindowAt(const Offset(110, 110)), 'aux');
      expect(
        registry.update(
          bounds('aux', 3, const Rect.fromLTWH(0, 0, 20, 20)),
        ),
        isTrue,
      );
      expect(registry.uniqueWindowAt(const Offset(110, 110)), isNull);
    });

    test('bounds registry stays at its configured capacity and removes ids',
        () {
      final registry = AuxiliaryWindowBoundsRegistry(capacity: 2);
      expect(
        registry.update(bounds('one', 1, const Rect.fromLTWH(0, 0, 10, 10))),
        isTrue,
      );
      expect(
        registry.update(bounds('two', 1, const Rect.fromLTWH(20, 0, 10, 10))),
        isTrue,
      );
      expect(
        registry.update(
          bounds('three', 1, const Rect.fromLTWH(40, 0, 10, 10)),
        ),
        isFalse,
      );
      expect(registry.length, 2);
      expect(registry.remove('one'), isTrue);
      expect(
        registry.update(
          bounds('three', 1, const Rect.fromLTWH(40, 0, 10, 10)),
        ),
        isTrue,
      );
      expect(registry.length, 2);
      registry.clear();
      expect(registry.length, 0);
    });
  });
}
