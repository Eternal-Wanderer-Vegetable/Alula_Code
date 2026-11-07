import 'package:alula_app/workbench/layout_controller.dart';
import 'package:alula_app/workbench/layout_model.dart';
import 'package:alula_app/workbench/panel_position.dart';
import 'package:flutter/painting.dart' show Axis;
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Panel defaults to Bottom and root JSON restores Top and Bottom', () {
    final layout = WorkbenchLayout(root: defaultLayout());
    final panel = layout.root.leafOf('panel')!;
    expect(layout.panelVerticalPosition, PanelVerticalPosition.bottom);

    expect(layout.setPanelVerticalPosition(PanelVerticalPosition.top), isTrue);
    expect(identical(layout.root.children.first, panel), isTrue);
    expect(layout.panelVerticalPosition, PanelVerticalPosition.top);

    final restoredTop = WbNode.fromJson(layout.root.toJson()) as WbSplit;
    final topLayout = WorkbenchLayout(root: restoredTop);
    expect(topLayout.panelVerticalPosition, PanelVerticalPosition.top);
    expect(topLayout.setPanelVerticalPosition(PanelVerticalPosition.bottom),
        isTrue);
    final restoredBottom = WbNode.fromJson(restoredTop.toJson()) as WbSplit;
    final bottomLayout = WorkbenchLayout(root: restoredBottom);
    expect(bottomLayout.panelVerticalPosition, PanelVerticalPosition.bottom);

    layout.dispose();
    topLayout.dispose();
    bottomLayout.dispose();
  });

  test('moving Panel preserves its state, siblings, and root metadata', () {
    final root = defaultLayout();
    final layout = WorkbenchLayout(root: root);
    final panel = root.leafOf('panel')!..weight = 0.41;
    panel
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
      ..activityBarAccountsVisible = false
      ..primarySidebarView = 'search'
      ..secondarySidebarView = 'git';
    final metadataBefore = Map<String, Object?>.from(root.toJson())
      ..remove('children');

    expect(layout.setPanelVerticalPosition(PanelVerticalPosition.top), isTrue);
    expect(identical(root.children.first, panel), isTrue);
    expect(root.children.skip(1).toList(), orderedEquals(otherChildren));
    expect(panel.weight, 0.41);
    expect(panel.collapsed, isTrue);
    expect(panel.lastWeight, 0.27);
    expect(panel.minExtent, 144);
    final metadataAfter = Map<String, Object?>.from(root.toJson())
      ..remove('children');
    expect(metadataAfter, metadataBefore);

    layout.dispose();
  });

  test('selecting the active position is a no-op', () {
    final layout = WorkbenchLayout(root: defaultLayout());
    var notifications = 0;
    layout.addListener(() => notifications++);

    expect(
      layout.setPanelVerticalPosition(PanelVerticalPosition.bottom),
      isFalse,
    );
    expect(layout.setPanelVerticalPosition(PanelVerticalPosition.top), isTrue);
    expect(layout.setPanelVerticalPosition(PanelVerticalPosition.top), isFalse);
    expect(notifications, 1);

    layout.dispose();
  });

  test('unsupported root shape leaves the layout untouched', () {
    final layout = WorkbenchLayout(
      root: WbSplit(
        axis: Axis.horizontal,
        children: [
          WbLeaf(region: 'editor'),
          WbLeaf(region: 'panel'),
        ],
      ),
    );
    final originalChildren = List<WbNode>.of(layout.root.children);

    expect(layout.panelVerticalPosition, isNull);
    expect(layout.setPanelVerticalPosition(PanelVerticalPosition.top), isFalse);
    expect(layout.root.children, orderedEquals(originalChildren));

    layout.dispose();
  });
}
