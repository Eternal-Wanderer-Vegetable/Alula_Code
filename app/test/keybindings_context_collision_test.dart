import 'package:alula_app/workbench/keybindings.dart';
import 'package:flutter/foundation.dart' show TargetPlatform;
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('context-scoped default keybinding collisions', () {
    test('Complete Merge overrides line insertion only in Merge Editor', () {
      for (final platform in [TargetPlatform.windows, TargetPlatform.linux]) {
        final bindings = KeybindingSet.load(platform: platform);
        final outsideMerge = bindings.resolveBindings(
          matchesWhen: (condition) => condition == null,
        );
        final inMerge = bindings.resolveBindings(
          matchesWhen: (condition) =>
              condition == null || condition == 'mergeEditorActive',
        );

        expect(
          outsideMerge.values.where((binding) =>
              binding.commandId == 'editor.action.insertLineAfter'),
          hasLength(1),
        );
        expect(
          outsideMerge.values.where(
              (binding) => binding.commandId == 'mergeEditor.acceptMerge'),
          isEmpty,
        );
        expect(
          inMerge.values.where(
              (binding) => binding.commandId == 'mergeEditor.acceptMerge'),
          hasLength(1),
        );
        expect(
          inMerge.values.where((binding) =>
              binding.commandId == 'editor.action.insertLineAfter'),
          isEmpty,
        );
        expect(
          bindings.commandForChord(parseChord('ctrl+enter')!),
          'editor.action.insertLineAfter',
        );
        expect(bindings.shortcutFor('mergeEditor.acceptMerge'), 'Ctrl+Enter');
      }
    });

    test('macOS uses Cmd+Enter in the same Merge Editor context', () {
      final bindings = KeybindingSet.load(platform: TargetPlatform.macOS);
      final outsideMerge = bindings.resolveBindings(
        matchesWhen: (condition) => condition == null,
      );
      final inMerge = bindings.resolveBindings(
        matchesWhen: (condition) =>
            condition == null || condition == 'mergeEditorActive',
      );

      expect(
        outsideMerge.values.where(
            (binding) => binding.commandId == 'editor.action.insertLineAfter'),
        hasLength(1),
      );
      expect(
        inMerge.values
            .where((binding) => binding.commandId == 'mergeEditor.acceptMerge'),
        hasLength(1),
      );
      expect(
        inMerge.values.where(
            (binding) => binding.commandId == 'editor.action.insertLineAfter'),
        isEmpty,
      );
      expect(bindings.commandForChord(parseChord('cmd+enter')!),
          'editor.action.insertLineAfter');
      expect(bindings.shortcutFor('mergeEditor.acceptMerge'), 'Meta+Enter');
    });

    test('user removal and rebinding keep context collisions independent', () {
      final removed = KeybindingSet.load(
        platform: TargetPlatform.windows,
        userJson: '[{"key":"ctrl+enter","command":"-mergeEditor.acceptMerge"}]',
      );
      expect(removed.shortcutFor('mergeEditor.acceptMerge'), isNull);
      expect(
        removed
            .resolveBindings(
              matchesWhen: (condition) =>
                  condition == null || condition == 'mergeEditorActive',
            )
            .values
            .where((binding) =>
                binding.commandId == 'editor.action.insertLineAfter'),
        hasLength(1),
      );

      final removedLineInsert = KeybindingSet.load(
        platform: TargetPlatform.windows,
        userJson:
            '[{"key":"ctrl+enter","command":"-editor.action.insertLineAfter"}]',
      );
      expect(
        removedLineInsert
            .resolveBindings(matchesWhen: (condition) => condition == null)
            .values
            .where((binding) =>
                binding.commandId == 'editor.action.insertLineAfter'),
        isEmpty,
      );
      expect(
        removedLineInsert
            .resolveBindings(
              matchesWhen: (condition) =>
                  condition == null || condition == 'mergeEditorActive',
            )
            .values
            .where((binding) => binding.commandId == 'mergeEditor.acceptMerge'),
        hasLength(1),
      );

      final rebound = KeybindingSet.load(
        platform: TargetPlatform.windows,
        userJson:
            '[{"key":"ctrl+alt+enter","command":"mergeEditor.acceptMerge",'
            '"when":"mergeEditorActive"}]',
      );
      expect(rebound.shortcutFor('mergeEditor.acceptMerge'), 'Ctrl+Alt+Enter');
      expect(
        rebound
            .resolveBindings(
              matchesWhen: (condition) =>
                  condition == null || condition == 'mergeEditorActive',
            )
            .values
            .where((binding) => binding.commandId == 'mergeEditor.acceptMerge'),
        hasLength(1),
      );
      expect(
        rebound
            .resolveBindings(matchesWhen: (condition) => condition == null)
            .values
            .where((binding) =>
                binding.commandId == 'editor.action.insertLineAfter'),
        hasLength(1),
      );
    });

    test('caps context alternatives per chord without dropping Merge default',
        () {
      final overrides = List.generate(
        100,
        (index) => '{"key":"ctrl+enter","command":"test.context$index",'
            '"when":"context$index"}',
      ).join(',');
      final bindings = KeybindingSet.load(
        platform: TargetPlatform.windows,
        userJson: '[$overrides]',
      );
      final mergeAndOldContext = bindings.resolveBindings(
        matchesWhen: (condition) =>
            condition == null ||
            condition == 'mergeEditorActive' ||
            condition == 'context0',
      );
      final mergeOnly = bindings.resolveBindings(
        matchesWhen: (condition) =>
            condition == null || condition == 'mergeEditorActive',
      );
      final latestContext = bindings.resolveBindings(
        matchesWhen: (condition) =>
            condition == null ||
            condition == 'mergeEditorActive' ||
            condition == 'context99',
      );

      expect(
        mergeAndOldContext.values
            .where((binding) => binding.commandId == 'mergeEditor.acceptMerge'),
        hasLength(1),
      );
      expect(
        mergeOnly.values
            .where((binding) => binding.commandId == 'mergeEditor.acceptMerge'),
        hasLength(1),
      );
      expect(
        latestContext.values
            .where((binding) => binding.commandId == 'test.context99'),
        hasLength(1),
      );
    });

    test('later user bindings take precedence only in their matching context',
        () {
      final bindings = KeybindingSet.load(
        platform: TargetPlatform.windows,
        userJson: '[{"key":"ctrl+enter","command":"test.completeMerge",'
            '"when":"mergeEditorActive"}]',
      );
      final outsideMerge = bindings.resolveBindings(
        matchesWhen: (condition) => condition == null,
      );
      final inMerge = bindings.resolveBindings(
        matchesWhen: (condition) =>
            condition == null || condition == 'mergeEditorActive',
      );

      expect(
        outsideMerge.values.where(
            (binding) => binding.commandId == 'editor.action.insertLineAfter'),
        hasLength(1),
      );
      expect(
        inMerge.values
            .where((binding) => binding.commandId == 'test.completeMerge'),
        hasLength(1),
      );
      expect(
        inMerge.values
            .where((binding) => binding.commandId == 'mergeEditor.acceptMerge'),
        isEmpty,
      );
    });
  });
}
