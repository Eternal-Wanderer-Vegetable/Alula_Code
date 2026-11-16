import 'package:alula_app/workbench/auxiliary_focus_context.dart';
import 'package:alula_app/workbench/auxiliary_window.dart';
import 'package:flutter_test/flutter_test.dart';

AuxiliaryFocusContextEvent event({
  required String windowId,
  required int sequence,
  required String groupId,
  bool focused = false,
  AuxiliaryFocusEventKind kind = AuxiliaryFocusEventKind.update,
}) =>
    AuxiliaryFocusContextEvent(
      kind: kind,
      windowId: windowId,
      sequence: sequence,
      groupId: groupId,
      focused: focused,
    );

void main() {
  group('AuxiliaryFocusContextEvent', () {
    test('wire data contains only active window/group focus metadata', () {
      final wire = event(
        windowId: 'aux-2',
        sequence: 3,
        groupId: 'aux-2:editor',
        focused: true,
      ).toMap();

      expect(wire.keys.toSet(), {
        'protocol',
        'type',
        'windowId',
        'sequence',
        'groupId',
        'focused',
      });
      expect(wire, isNot(contains('documentId')));
      expect(wire, isNot(contains('text')));
      expect(wire, isNot(contains('dirty')));
      expect(wire, isNot(contains('selection')));
      expect(wire, isNot(contains('session')));
      expect(AuxiliaryFocusContextEvent.tryParse(wire)?.windowId, 'aux-2');
      final olderPeerWire = {
        ...wire,
        'documentId': 'file:/workspace/ignored.dart'
      };
      final parsedFromOlderPeer =
          AuxiliaryFocusContextEvent.tryParse(olderPeerWire);
      expect(parsedFromOlderPeer?.toMap(), wire,
          reason: 'legacy document identity is ignored and never re-emitted');
    });

    test('rejects malformed and oversized identity payloads', () {
      expect(AuxiliaryFocusContextEvent.tryParse({'windowId': 'aux'}), isNull);
      expect(
        AuxiliaryFocusContextEvent.tryParse(
          event(
            windowId: 'aux-1',
            sequence: -1,
            groupId: 'aux-1:editor',
          ).toMap(),
        ),
        isNull,
      );
      expect(
        AuxiliaryFocusContextEvent.tryParse(
          event(
            windowId: 'aux-1',
            sequence: 1,
            groupId: 'aux-1:editor',
          ).toMap()
            ..['text'] = 'not part of protocol',
        ),
        isNotNull,
        reason: 'unknown fields are ignored and never enter the parsed event',
      );
    });
  });

  group('AuxiliaryFocusContextRegistry', () {
    AuxiliaryFocusContextRegistry registry() => AuxiliaryFocusContextRegistry()
      ..initializeMain(
        windowId: 'main',
        groupId: 'main:editor',
      );

    test('focus changes select the latest part and reject stale events', () {
      final owners = registry();
      final initialRevision = owners.snapshot!.revision;
      final hello = owners.apply(event(
        windowId: 'aux-1',
        sequence: 1,
        groupId: 'aux-1:editor',
        kind: AuxiliaryFocusEventKind.register,
      ));
      expect(hello.accepted, isTrue);
      expect(hello.snapshotChanged, isFalse);
      expect(owners.snapshot!.windowId, 'main');

      final focused = owners.apply(event(
        windowId: 'aux-1',
        sequence: 2,
        groupId: 'aux-1:editor',
        focused: true,
      ));
      expect(focused.snapshotChanged, isTrue);
      expect(owners.snapshot!.windowId, 'aux-1');
      expect(owners.snapshot!.revision, greaterThan(initialRevision));
      expect(owners.snapshot!.toMap().keys.toSet(), {
        'windowId',
        'groupId',
        'revision',
      });

      final groupChanged = owners.apply(event(
        windowId: 'aux-1',
        sequence: 3,
        groupId: 'aux-1:second-group',
        focused: true,
      ));
      expect(groupChanged.snapshotChanged, isTrue);
      expect(owners.snapshot!.groupId, 'aux-1:second-group');

      final stale = owners.apply(event(
        windowId: 'aux-1',
        sequence: 2,
        groupId: 'aux-1:old-group',
      ));
      expect(stale.accepted, isFalse);
      expect(owners.snapshot!.groupId, 'aux-1:second-group');
    });

    test('blur and close fall back to the most recently active survivor', () {
      final owners = registry();
      owners.apply(event(
        windowId: 'aux-1',
        sequence: 1,
        groupId: 'aux-1:editor',
        kind: AuxiliaryFocusEventKind.register,
      ));
      owners.apply(event(
        windowId: 'aux-1',
        sequence: 2,
        groupId: 'aux-1:editor',
        focused: true,
      ));
      owners.apply(event(
        windowId: 'aux-2',
        sequence: 1,
        groupId: 'aux-2:editor',
        kind: AuxiliaryFocusEventKind.register,
      ));
      owners.apply(event(
        windowId: 'aux-2',
        sequence: 2,
        groupId: 'aux-2:editor',
        focused: true,
      ));

      final mainBlur = owners.apply(event(
        windowId: 'main',
        sequence: 0,
        groupId: 'main:editor',
      ));
      expect(mainBlur.snapshotChanged, isFalse,
          reason: 'a delayed blur from another part cannot steal ownership');
      expect(owners.snapshot!.windowId, 'aux-2');

      final removed = owners.removeAuxiliaryWindow('aux-2');
      expect(removed.snapshotChanged, isTrue);
      expect(owners.snapshot!.windowId, 'aux-1');

      owners.apply(event(
        windowId: 'aux-1',
        sequence: 3,
        groupId: 'aux-1:editor',
      ));
      expect(owners.snapshot!.windowId, 'main');
    });

    test('an auxiliary that never owned focus is not chosen as MRU fallback',
        () {
      final owners = registry();
      owners.apply(event(
        windowId: 'aux-1',
        sequence: 1,
        groupId: 'aux-1:editor',
        kind: AuxiliaryFocusEventKind.register,
      ));

      final mainBlur = owners.apply(event(
        windowId: 'main',
        sequence: 0,
        groupId: 'main:editor',
      ));

      expect(mainBlur.snapshotChanged, isFalse);
      expect(owners.snapshot!.windowId, 'main');
    });

    test('keeps auxiliary owner registration bounded and removes closed owners',
        () {
      final owners = registry();
      for (var index = 0; index < maxAuxiliaryFocusWindows; index++) {
        final result = owners.apply(event(
          windowId: 'aux-$index',
          sequence: 1,
          groupId: 'aux-$index:editor',
          kind: AuxiliaryFocusEventKind.register,
        ));
        expect(result.accepted, isTrue);
      }
      final overflow = owners.apply(event(
        windowId: 'aux-overflow',
        sequence: 1,
        groupId: 'aux-overflow:editor',
        kind: AuxiliaryFocusEventKind.register,
      ));
      expect(overflow.accepted, isFalse);
      expect(owners.auxiliaryWindowCount, maxAuxiliaryFocusWindows);

      owners.removeAuxiliaryWindow('aux-0');
      expect(owners.auxiliaryWindowCount, maxAuxiliaryFocusWindows - 1);
      expect(
        owners
            .apply(event(
              windowId: 'aux-overflow',
              sequence: 1,
              groupId: 'aux-overflow:editor',
              kind: AuxiliaryFocusEventKind.register,
            ))
            .accepted,
        isTrue,
      );
    });

    test('focus events never change the transferred editor payload', () {
      const text = 'dirty\r\nemoji 😀\n';
      final payload = AuxiliaryWindowPayload.forDocument(
        path: '/workspace/notes.txt',
        name: 'notes.txt',
        text: text,
        dirty: true,
      );
      final before = payload.toArguments();
      final owners = registry();
      owners.apply(event(
        windowId: 'aux-1',
        sequence: 1,
        groupId: 'aux-1:editor',
        kind: AuxiliaryFocusEventKind.register,
      ));
      owners.apply(event(
        windowId: 'aux-1',
        sequence: 2,
        groupId: 'aux-1:editor',
        focused: true,
      ));
      expect(payload.text, text);
      expect(payload.dirty, isTrue);
      expect(payload.toArguments(), before);
    });
  });
}
