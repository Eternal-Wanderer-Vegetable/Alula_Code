import 'package:alula_app/workbench/activity_bar_position.dart';
import 'package:alula_app/workbench/activity_bar_size.dart';
import 'package:alula_app/workbench/layout_controller.dart';
import 'package:alula_app/workbench/layout_model.dart';
import 'package:flutter/painting.dart' show Axis;
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Activity Bar layout placement', () {
    test('Side → Top → Bottom → Side preserves editor and panel weights', () {
      final root = defaultLayout();
      final layout = WorkbenchLayout(root: root);
      final activity = root.leafOf('activity')!;
      final editor = root.leafOf('editor')!;
      final panel = root.leafOf('panel')!;
      final mainRow = root.children.first as WbSplit;
      final editorWeight = editor.weight;
      final panelWeight = panel.weight;

      expect(layout.activityBarLocation, ActivityBarLocation.side);
      expect(layout.setActivityBarLocation(ActivityBarLocation.top), isTrue);
      _expectHorizontalLocation(
        layout,
        ActivityBarLocation.top,
        activity,
        editorWeight,
        panelWeight,
      );

      expect(layout.setActivityBarLocation(ActivityBarLocation.bottom), isTrue);
      _expectHorizontalLocation(
        layout,
        ActivityBarLocation.bottom,
        activity,
        editorWeight,
        panelWeight,
      );

      expect(layout.setActivityBarLocation(ActivityBarLocation.side), isTrue);
      expect(layout.activityBarLocation, ActivityBarLocation.side);
      expect(identical(root.children.first, mainRow), isTrue);
      expect(mainRow.axis, Axis.horizontal);
      expect(mainRow.children[0], same(activity));
      expect((mainRow.children[1] as WbLeaf).region, 'sidebar');
      expect(activity.fixedExtent, 48);
      expect(editor.weight, editorWeight);
      expect((mainRow.children[1] as WbLeaf).weight, closeTo(0.24, 1e-9));
      expect(panel.weight, panelWeight);
      expect(root.children.last, same(panel));
      expect(
          root.leaves.where((leaf) => leaf.region == 'activity'), hasLength(1));
      expect(layout.setActivityBarLocation(ActivityBarLocation.side), isFalse);
      layout.dispose();
    });

    test('Hidden restores into each requested position', () {
      for (final target in [
        ActivityBarLocation.side,
        ActivityBarLocation.top,
        ActivityBarLocation.bottom,
      ]) {
        final layout = WorkbenchLayout();
        final activity = layout.leafOf('activity')!;
        expect(
            layout.setActivityBarLocation(ActivityBarLocation.hidden), isTrue);
        expect(activity.collapsed, isTrue);
        expect(layout.activityBarLocation, ActivityBarLocation.hidden);

        expect(layout.setActivityBarLocation(target), isTrue);
        expect(activity.collapsed, isFalse);
        expect(layout.activityBarLocation, target);
        expect(layout.root.leaves.where((leaf) => leaf.region == 'activity'),
            hasLength(1));
        if (target == ActivityBarLocation.side) {
          expect(layout.root.parentSplitOf('activity')!.axis, Axis.horizontal);
          expect(activity.fixedExtent, 48);
        } else {
          final parent = layout.root.parentSplitOf('activity')!;
          expect(parent.axis, Axis.vertical);
          expect(activity.fixedExtent, 44);
          expect(parent.children[target == ActivityBarLocation.top ? 0 : 1],
              same(activity));
        }
        layout.dispose();
      }
    });

    test('Compact is persisted while Top/Bottom keep their existing height',
        () {
      final layout = WorkbenchLayout();
      final activity = layout.leafOf('activity')!;
      final sidebar = layout.leafOf('sidebar')!;
      final editor = layout.leafOf('editor')!;
      final panel = layout.leafOf('panel')!;
      final sidebarWeight = sidebar.weight;
      final editorWeight = editor.weight;
      final panelWeight = panel.weight;

      expect(layout.setActivityBarSize(ActivityBarSize.compact), isTrue);
      expect(activity.fixedExtent, 36);
      expect(layout.setActivityBarLocation(ActivityBarLocation.top), isTrue);
      expect(layout.activityBarSize, ActivityBarSize.compact);
      expect(activity.fixedExtent, 44);
      expect(layout.setActivityBarLocation(ActivityBarLocation.side), isTrue);
      expect(activity.fixedExtent, 36);
      expect(sidebar.weight, sidebarWeight);
      expect(editor.weight, editorWeight);
      expect(panel.weight, panelWeight);

      final restored = WorkbenchLayout(
        root: WbNode.fromJson(layout.root.toJson()) as WbSplit,
      );
      expect(restored.activityBarSize, ActivityBarSize.compact);
      expect(restored.leafOf('activity')!.fixedExtent, 36);
      restored.dispose();
      layout.dispose();
    });

    test('size update preserves an existing Editor split tree', () {
      final layout = WorkbenchLayout();
      expect(
        layout.root.splitLeaf(
          'editor',
          'editor-2',
          Axis.horizontal,
          splitName: 'editor-group',
        ),
        isNotNull,
      );
      final editorGroup = layout.root.parentSplitOf('editor')!;
      final editorWeight = editorGroup.children[0].weight;
      final secondEditorWeight = editorGroup.children[1].weight;
      final splitWeight = editorGroup.weight;

      expect(layout.setActivityBarSize(ActivityBarSize.compact), isTrue);
      expect(layout.root.parentSplitOf('editor'), same(editorGroup));
      expect(layout.root.leafOf('editor-2'), isNotNull);
      expect(editorGroup.children[0].weight, editorWeight);
      expect(editorGroup.children[1].weight, secondEditorWeight);
      expect(editorGroup.weight, splitWeight);
      layout.dispose();
    });

    test('Hidden keeps its previous branch and repeated locations are stable',
        () {
      final layout = WorkbenchLayout();
      final activity = layout.leafOf('activity')!;
      final sidebar = layout.leafOf('sidebar')!;
      final sideParent = layout.root.parentSplitOf('activity');
      expect(layout.setActivityBarLocation(ActivityBarLocation.top), isTrue);
      final topParent = layout.root.parentSplitOf('activity');
      expect(layout.setActivityBarLocation(ActivityBarLocation.top), isFalse);
      expect(layout.setActivityBarLocation(ActivityBarLocation.hidden), isTrue);
      expect(layout.root.parentSplitOf('activity'), same(topParent));
      expect(layout.root.parentSplitOf('sidebar'), same(topParent));
      expect(layout.setActivityBarLocation(ActivityBarLocation.bottom), isTrue);
      expect(layout.root.parentSplitOf('activity'), same(topParent));
      expect(topParent!.children, [sidebar, activity]);
      expect(sideParent, isNot(same(topParent)));
      layout.dispose();
    });

    test('position metadata round-trips and reads legacy P05.11 JSON', () {
      final layout = WorkbenchLayout();
      for (final location in ActivityBarLocation.values) {
        layout.setActivityBarLocation(location);
        final restoredRoot = WbNode.fromJson(layout.root.toJson()) as WbSplit;
        final restored = WorkbenchLayout(root: restoredRoot);
        expect(restored.activityBarLocation, location);
        expect(restoredRoot.leaves.where((leaf) => leaf.region == 'activity'),
            hasLength(1));
        restored.dispose();
      }

      final legacySide = defaultLayout().toJson()
        ..remove('activityBarLocation');
      expect(
        WorkbenchLayout(root: WbNode.fromJson(legacySide) as WbSplit)
            .activityBarLocation,
        ActivityBarLocation.side,
      );

      final legacyHiddenRoot = defaultLayout();
      final legacyActivity = legacyHiddenRoot.leafOf('activity')!;
      legacyActivity
        ..collapsed = true
        ..lastWeight = legacyActivity.weight;
      final legacyHidden = legacyHiddenRoot.toJson()
        ..remove('activityBarLocation');
      expect(
        WorkbenchLayout(root: WbNode.fromJson(legacyHidden) as WbSplit)
            .activityBarLocation,
        ActivityBarLocation.hidden,
      );
      layout.dispose();
    });
  });
}

void _expectHorizontalLocation(
  WorkbenchLayout layout,
  ActivityBarLocation location,
  WbLeaf activity,
  double editorWeight,
  double panelWeight,
) {
  final parent = layout.root.parentSplitOf('activity')!;
  final sidebar = layout.root.leafOf('sidebar')!;
  expect(layout.activityBarLocation, location);
  expect(parent.axis, Axis.vertical);
  expect(
      parent.children,
      location == ActivityBarLocation.top
          ? [activity, sidebar]
          : [sidebar, activity]);
  expect(activity.fixedExtent, 44);
  expect(activity.collapsed, isFalse);
  expect(layout.root.parentSplitOf('sidebar'), same(parent));
  final mainRow = _mainRow(layout.root);
  expect(mainRow.children, hasLength(2));
  expect(mainRow.children.first, same(parent));
  expect(mainRow.children.last, same(layout.root.leafOf('editor')));
  expect((mainRow.children.first as WbSplit).weight, closeTo(0.24, 1e-9));
  expect(layout.root.leafOf('editor')!.weight, editorWeight);
  expect(layout.root.leafOf('panel')!.weight, panelWeight);
  expect(layout.root.children.last, same(layout.root.leafOf('panel')));
  expect(layout.root.leaves.where((leaf) => leaf.region == 'activity'),
      hasLength(1));
}

WbSplit _mainRow(WbSplit root) => root.children.first as WbSplit;
