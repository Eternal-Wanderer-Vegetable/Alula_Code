import 'package:alula_app/workbench/layout_controller.dart';
import 'package:alula_app/workbench/layout_model.dart';
import 'package:alula_app/workbench/panel_position.dart';
import 'package:flutter/painting.dart' show Axis;
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Panel positions round-trip through the existing root JSON', () {
    final layout = WorkbenchLayout(root: defaultLayout());
    final panel = layout.root.leafOf('panel')!;
    expect(layout.panelPosition, PanelPosition.bottom);

    expect(layout.setPanelPosition(PanelPosition.top), isTrue);
    expect(identical(layout.root.children.first, panel), isTrue);
    expect(layout.panelPosition, PanelPosition.top);
    expect(layout.root.toJson()['axis'], 'v');

    expect(layout.setPanelPosition(PanelPosition.left), isTrue);
    expect(layout.panelPosition, PanelPosition.left);
    expect(layout.root.toJson()['axis'], 'h');
    final restoredLeft = WbNode.fromJson(layout.root.toJson()) as WbSplit;
    final leftLayout = WorkbenchLayout(root: restoredLeft);
    expect(leftLayout.panelPosition, PanelPosition.left);
    expect(leftLayout.setPanelPosition(PanelPosition.right), isTrue);
    final restoredRight = WbNode.fromJson(restoredLeft.toJson()) as WbSplit;
    final rightLayout = WorkbenchLayout(root: restoredRight);
    expect(rightLayout.panelPosition, PanelPosition.right);
    expect(rightLayout.setPanelPosition(PanelPosition.bottom), isTrue);

    final restoredBottom = WbNode.fromJson(restoredRight.toJson()) as WbSplit;
    final bottomLayout = WorkbenchLayout(root: restoredBottom);
    expect(bottomLayout.panelPosition, PanelPosition.bottom);

    layout.dispose();
    leftLayout.dispose();
    rightLayout.dispose();
    bottomLayout.dispose();
  });

  test('moving Panel preserves its state, siblings, and root metadata', () {
    final root = defaultLayout();
    final layout = WorkbenchLayout(root: root);
    final panel = root.leafOf('panel')!
      ..weight = 0.41
      ..collapsed = true
      ..lastWeight = 0.27
      ..minExtent = 144;
    final otherChildren =
        root.children.where((node) => !identical(node, panel)).toList();
    root
      ..activityBarLocation = ActivityBarLocation.top
      ..activityBarSize = ActivityBarSize.compact
      ..sideBarPosition = SideBarPosition.right
      ..activityBarOrder = ['git', 'explorer', 'search', 'outline']
      ..activityBarPinned = ['git', 'explorer']
      ..activityBarBadgesDisabled = ['search']
      ..activityBarAccountsVisible = false
      ..sidebarViewLocations = {
        'explorer': secondarySidebarViewLocation,
        'search': primarySidebarViewLocation,
        'outline': primarySidebarViewLocation,
        'git': secondarySidebarViewLocation,
      }
      ..primarySidebarView = 'search'
      ..secondarySidebarView = 'git';
    final metadataBefore = Map<String, Object?>.from(root.toJson())
      ..remove('children');
    metadataBefore.remove('axis');

    expect(layout.setPanelPosition(PanelPosition.left), isTrue);
    expect(identical(root.children.first, panel), isTrue);
    expect(root.children.skip(1).toList(), orderedEquals(otherChildren));
    expect(panel.weight, 0.41);
    expect(panel.collapsed, isTrue);
    expect(panel.lastWeight, 0.27);
    expect(panel.minExtent, 144);
    final metadataAfter = Map<String, Object?>.from(root.toJson())
      ..remove('children');
    metadataAfter.remove('axis');
    expect(metadataAfter, metadataBefore);

    layout.dispose();
  });

  test('active position is a no-op and orientation changes notify once', () {
    final layout = WorkbenchLayout(root: defaultLayout());
    var notifications = 0;
    layout.addListener(() => notifications++);

    expect(layout.setPanelPosition(PanelPosition.bottom), isFalse);
    expect(layout.setPanelPosition(PanelPosition.left), isTrue);
    expect(layout.setPanelPosition(PanelPosition.left), isFalse);
    expect(layout.setPanelPosition(PanelPosition.top), isTrue);
    expect(layout.setPanelPosition(PanelPosition.top), isFalse);
    expect(notifications, 2);

    layout.dispose();
  });

  test('vertical and horizontal moves preserve root and workspace nodes', () {
    final root = defaultLayout();
    final layout = WorkbenchLayout(root: root);
    final panel = root.leafOf('panel')!
      ..weight = 0.37
      ..minExtent = 132
      ..collapsed = true
      ..lastWeight = 0.22;
    final main = root.children.singleWhere((node) => !identical(node, panel));
    expect(layout.splitRegion('editor', 'editor-group-2', Axis.horizontal),
        isTrue);
    final mainTree = main.toJson();
    root
      ..activityBarLocation = ActivityBarLocation.bottom
      ..activityBarSize = ActivityBarSize.compact
      ..activityBarOrder = ['search', 'git', 'explorer', 'outline']
      ..activityBarPinned = ['search', 'git']
      ..activityBarBadgesDisabled = ['outline']
      ..activityBarAccountsVisible = false
      ..sideBarPosition = SideBarPosition.right
      ..sidebarViewLocations = {
        'explorer': secondarySidebarViewLocation,
        'search': primarySidebarViewLocation,
        'outline': secondarySidebarViewLocation,
        'git': primarySidebarViewLocation,
      }
      ..primarySidebarView = 'search'
      ..secondarySidebarView = 'explorer';
    final rootMetadata = Map<String, Object?>.from(root.toJson())
      ..remove('children')
      ..remove('axis');
    final otherChildren =
        root.children.where((node) => !identical(node, panel));

    for (final position in PanelPosition.values) {
      expect(layout.setPanelPosition(position), isTrue, reason: '$position');
      expect(identical(layout.root, root), isTrue);
      expect(identical(root.leafOf('panel'), panel), isTrue);
      expect(
          identical(
              root.children.singleWhere((node) => !identical(node, panel)),
              main),
          isTrue);
      expect(root.children.where((node) => !identical(node, panel)),
          orderedEquals(otherChildren));
      expect(main.toJson(), mainTree);
      expect(panel.weight, 0.37);
      expect(panel.minExtent, 132);
      expect(panel.collapsed, isTrue);
      expect(panel.lastWeight, 0.22);
      expect(layout.panelPosition, position);
      expect(
        root.axis,
        position == PanelPosition.top || position == PanelPosition.bottom
            ? Axis.vertical
            : Axis.horizontal,
      );
      final metadata = Map<String, Object?>.from(root.toJson())
        ..remove('children')
        ..remove('axis');
      expect(metadata, rootMetadata);
    }

    layout.dispose();
  });

  test('nested, middle, and duplicate Panel shapes remain unchanged', () {
    final nested = WorkbenchLayout(
      root: WbSplit(
        axis: Axis.vertical,
        children: [
          WbSplit(
            axis: Axis.horizontal,
            children: [WbLeaf(region: 'editor'), WbLeaf(region: 'panel')],
          ),
          WbLeaf(region: 'sidebar'),
        ],
      ),
    );
    expect(nested.panelPosition, isNull);
    expect(nested.setPanelPosition(PanelPosition.left), isFalse);

    final middleRoot = WbSplit(
      axis: Axis.vertical,
      children: [
        WbLeaf(region: 'sidebar'),
        WbLeaf(region: 'panel'),
        WbLeaf(region: 'editor'),
      ],
    );
    final middle = WorkbenchLayout(root: middleRoot);
    final middleChildren = List<WbNode>.of(middleRoot.children);
    expect(middle.panelPosition, isNull);
    expect(middle.setPanelPosition(PanelPosition.right), isFalse);
    expect(middleRoot.children, orderedEquals(middleChildren));

    final duplicateRoot = WbSplit(
      axis: Axis.horizontal,
      children: [WbLeaf(region: 'panel'), WbLeaf(region: 'panel')],
    );
    final duplicate = WorkbenchLayout(root: duplicateRoot);
    expect(duplicate.panelPosition, isNull);
    expect(duplicate.setPanelPosition(PanelPosition.left), isFalse);

    final nestedDuplicate = WorkbenchLayout(
      root: WbSplit(
        axis: Axis.vertical,
        children: [
          WbLeaf(region: 'panel'),
          WbSplit(
            axis: Axis.horizontal,
            children: [WbLeaf(region: 'panel'), WbLeaf(region: 'editor')],
          ),
        ],
      ),
    );
    expect(nestedDuplicate.panelPosition, isNull);
    expect(nestedDuplicate.setPanelPosition(PanelPosition.right), isFalse);

    nested.dispose();
    middle.dispose();
    duplicate.dispose();
    nestedDuplicate.dispose();
  });
}
