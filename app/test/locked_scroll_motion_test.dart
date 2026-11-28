import 'dart:async';

import 'package:alula_app/workbench/locked_scroll_motion.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const anchor = LockedScrollMotion(
    lockRevision: 2,
    anchorRevision: 3,
    sequence: 5,
  );

  test('offset frames preserve finite signed deltas and the source echo', () {
    final decodedAnchor = LockedScrollMotion.tryParse(anchor.toMap())!;
    expect(decodedAnchor.delta, isNull);
    expect(decodedAnchor.anchorRevision, 3);
    const motion = LockedScrollMotion(
      lockRevision: 2,
      anchorRevision: 3,
      sequence: 6,
      delta: (top: -9.5, left: null),
      source: (windowId: 'aux-1', sequence: 2),
    );
    final decoded = LockedScrollMotion.tryParse(motion.toMap())!;
    expect(decoded.delta, motion.delta);
    expect(decoded.source, motion.source);
    expect(decoded.lockRevision, motion.lockRevision);
    expect(decoded.sequence, motion.sequence);
    for (final invalid in [
      {...motion.toMap(), 'top': double.nan},
      {...motion.toMap(), 'left': double.infinity},
      {...motion.toMap(), 'anchorRevision': -1},
      {...motion.toMap(), 'sourceWindowId': ''},
      {...anchor.toMap(), 'left': 4.0},
    ]) {
      expect(LockedScrollMotion.tryParse(invalid), isNull);
    }
  });

  test('a slow engine receives the latest pending motion or an explicit clear',
      () async {
    final delivered = <int>[];
    final first = Completer<void>();
    final second = Completer<void>();
    final relay = LockedScrollMotionRelay((motion) async {
      delivered.add(motion.sequence);
      await (delivered.length == 1 ? first.future : second.future);
    });

    LockedScrollMotion frame(int sequence) => LockedScrollMotion(
          lockRevision: 2,
          anchorRevision: 3,
          sequence: sequence,
        );

    relay.offer(anchor);
    relay.offer(frame(6));
    relay.offer(frame(7));
    expect(delivered, [5]);
    first.complete();
    await pumpEventQueue();
    expect(delivered, [5, 7]);

    relay.offer(frame(8));
    relay.clear();
    second.complete();
    await pumpEventQueue();
    expect(delivered, [5, 7]);
  });
}
