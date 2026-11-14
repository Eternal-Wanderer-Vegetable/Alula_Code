import 'package:alula_app/workbench/layout_controller.dart';
import 'package:alula_app/workbench/layout_model.dart';
import 'package:alula_app/workbench/panel_alignment.dart';
import 'package:alula_app/workbench/panel_maximize.dart';
import 'package:alula_app/workbench/panel_position.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('maximization eligibility follows Panel alignment and position', () {
    for (final alignment in PanelAlignment.values) {
      for (final position in PanelPosition.values) {
        final layout = WorkbenchLayout();
        layout.setPanelAlignment(alignment);
        layout.setPanelPosition(position);

        final expected = alignment == PanelAlignment.center ||
            position == PanelPosition.left ||
            position == PanelPosition.right;
        expect(
          layout.canMaximizePanel,
          expected,
          reason: '$alignment at $position',
        );
        layout.dispose();
      }
    }
  });

  test('hidden Panel is revealed and maximize state is not serialized', () {
    final layout = WorkbenchLayout();
    expect(layout.isCollapsed('panel'), isTrue);
    expect(layout.panelMaximized, isFalse);

    expect(layout.togglePanelMaximization(), isTrue);
    expect(layout.isCollapsed('panel'), isFalse);
    expect(layout.panelMaximized, isTrue);
    expect(layout.root.toJson().containsKey('panelMaximized'), isFalse);

    expect(layout.togglePanelMaximization(), isTrue);
    expect(layout.panelMaximized, isFalse);
    expect(layout.isCollapsed('panel'), isFalse,
        reason: 'Restore keeps the Panel visible, matching Code-OSS');
    layout.dispose();
  });

  test('unsupported non-center top/bottom invocation is a no-op', () {
    final layout = WorkbenchLayout()
      ..setPanelAlignment(PanelAlignment.left)
      ..setPanelPosition(PanelPosition.top);
    final before = layout.root.toJson();

    expect(layout.canMaximizePanel, isFalse);
    expect(layout.togglePanelMaximization(), isFalse);
    expect(layout.panelMaximized, isFalse);
    expect(layout.root.toJson(), before);
    layout.dispose();
  });

  test('position and alignment changes restore unsupported maximization', () {
    final layout = WorkbenchLayout();
    expect(layout.togglePanelMaximization(), isTrue);
    expect(layout.panelMaximized, isTrue);

    layout.setPanelAlignment(PanelAlignment.left);
    expect(layout.panelPosition, PanelPosition.bottom);
    expect(layout.panelAlignment, PanelAlignment.left);
    expect(layout.panelMaximized, isFalse);

    layout.setPanelPosition(PanelPosition.left);
    expect(layout.canMaximizePanel, isTrue);
    expect(layout.togglePanelMaximization(), isTrue);
    expect(layout.panelMaximized, isTrue);

    layout.setPanelPosition(PanelPosition.bottom);
    expect(layout.panelMaximized, isFalse);
    layout.dispose();
  });

  test('center-aligned maximize survives supported position changes', () {
    final layout = WorkbenchLayout();
    expect(layout.togglePanelMaximization(), isTrue);
    expect(layout.panelMaximized, isTrue);

    layout.setPanelPosition(PanelPosition.left);
    expect(layout.panelMaximized, isTrue);
    layout.setPanelPosition(PanelPosition.top);
    expect(layout.panelMaximized, isTrue);
    layout.dispose();
  });
}
