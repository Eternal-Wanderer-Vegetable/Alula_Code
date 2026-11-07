import 'package:alula_app/workbench/layout_controller.dart';
import 'package:alula_app/workbench/layout_grid.dart';
import 'package:alula_app/workbench/layout_model.dart';
import 'package:alula_app/workbench/panel_alignment.dart';
import 'package:alula_app/workbench/panel_position.dart';
import 'package:alula_app/workbench/sidebar_position.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(
  WorkbenchLayout layout, {
  FocusNode? editorFocus,
  List<int>? editorMounts,
}) =>
    MaterialApp(
      home: Scaffold(
        body: WorkbenchGrid(layout: layout, builders: {
          for (final region in [
            'activity',
            'sidebar',
            'editor',
            'secondarySidebar',
            'panel',
          ])
            region: (_) => region == 'editor'
                ? Focus(
                    focusNode: editorFocus,
                    child: _MountProbe(mounts: editorMounts),
                  )
                : ColoredBox(
                    key: ValueKey('probe-$region'),
                    color: Colors.blue,
                  ),
        }),
      ),
    );

class _MountProbe extends StatefulWidget {
  const _MountProbe({this.mounts});

  final List<int>? mounts;

  @override
  State<_MountProbe> createState() => _MountProbeState();
}

class _MountProbeState extends State<_MountProbe> {
  @override
  void initState() {
    super.initState();
    if (widget.mounts != null) widget.mounts!.add(1);
  }

  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}

Rect _rect(WidgetTester tester, String region) =>
    tester.getRect(find.byKey(ValueKey('wb-region-$region')));

void main() {
  test('alignment defaults to Center and round-trips in the root JSON', () {
    final layout = WorkbenchLayout();
    expect(layout.panelAlignment, PanelAlignment.center);
    expect(layout.root.toJson().containsKey('panelAlignment'), isFalse);

    expect(layout.setPanelAlignment(PanelAlignment.justify), isTrue);
    expect(layout.root.toJson()['panelAlignment'], 'justify');
    final restored = WorkbenchLayout(
      root: WbNode.fromJson(layout.root.toJson()) as WbSplit,
    );
    expect(restored.panelAlignment, PanelAlignment.justify);

    final legacy = WbNode.fromJson({
      ...defaultLayout().toJson(),
      'panelAlignment': 'invalid',
    }) as WbSplit;
    expect(WorkbenchLayout(root: legacy).panelAlignment, PanelAlignment.center);
    layout.dispose();
    restored.dispose();
  });

  test(
      'alignment commands from side positions move Panel to Bottom and persist',
      () {
    for (final side in [PanelPosition.left, PanelPosition.right]) {
      final layout = WorkbenchLayout();
      final mainRow = layout.root.children
          .singleWhere((node) => node is WbSplit && node.name == 'main-row');
      final panel = layout.root.leafOf('panel')!
        ..collapsed = false
        ..lastWeight = null;
      layout.setPanelPosition(side);

      expect(layout.setPanelAlignment(PanelAlignment.left), isTrue);
      expect(layout.panelPosition, PanelPosition.bottom);
      expect(layout.panelAlignment, PanelAlignment.left);
      expect(identical(layout.root.leafOf('panel'), panel), isTrue);
      expect(
        identical(
          layout.root.children.singleWhere((node) => node is WbSplit),
          mainRow,
        ),
        isTrue,
      );

      expect(layout.setPanelPosition(PanelPosition.top), isTrue);
      expect(layout.panelAlignment, PanelAlignment.left);
      final restored = WorkbenchLayout(
        root: WbNode.fromJson(layout.root.toJson()) as WbSplit,
      );
      expect(restored.panelPosition, PanelPosition.top);
      expect(restored.panelAlignment, PanelAlignment.left);
      restored.dispose();
      layout.dispose();
    }
  });

  testWidgets('alignment reflows Panel width for both Side Bar positions',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    for (final side in SideBarPosition.values) {
      for (final alignment in PanelAlignment.values) {
        final layout = WorkbenchLayout();
        if (side == SideBarPosition.right) {
          expect(layout.setSideBarPosition(side), isTrue);
        }
        layout
          ..setRegionCollapsed('panel', false)
          ..setRegionCollapsed('secondarySidebar', false)
          ..setPanelAlignment(alignment);
        await tester.pumpWidget(_host(layout));
        await tester.pump();

        final panel = _rect(tester, 'panel');
        final primary = _rect(tester, 'sidebar');
        final editor = _rect(tester, 'editor');
        final secondary = _rect(tester, 'secondarySidebar');
        final allSideRegions = [primary, editor, secondary];
        final leftEdge = allSideRegions.map((rect) => rect.left).reduce(
              (a, b) => a < b ? a : b,
            );
        final rightEdge = allSideRegions.map((rect) => rect.right).reduce(
              (a, b) => a > b ? a : b,
            );

        switch (alignment) {
          case PanelAlignment.center:
            expect(panel.left, closeTo(editor.left, 1));
            expect(panel.right, closeTo(editor.right, 1));
          case PanelAlignment.justify:
            expect(panel.left, closeTo(leftEdge, 1));
            expect(panel.right, closeTo(rightEdge, 1));
          case PanelAlignment.left:
            final leftAlignedRegion =
                side == SideBarPosition.left ? primary : secondary;
            expect(panel.left, closeTo(leftAlignedRegion.left, 1));
            expect(
              panel.right,
              closeTo(
                side == SideBarPosition.left ? editor.right : editor.right,
                1,
              ),
            );
          case PanelAlignment.right:
            expect(panel.left, closeTo(editor.left, 1));
            final rightAlignedRegion =
                side == SideBarPosition.left ? secondary : primary;
            expect(panel.right, closeTo(rightAlignedRegion.right, 1));
        }

        layout.dispose();
        await tester.pumpWidget(const SizedBox.shrink());
      }
    }
  });

  testWidgets('alignment reparent keeps the editor state and keyboard focus',
      (tester) async {
    final layout = WorkbenchLayout();
    final focus = FocusNode();
    final mounts = <int>[];
    await tester.pumpWidget(
      _host(layout, editorFocus: focus, editorMounts: mounts),
    );
    await tester.pump();
    focus.requestFocus();
    await tester.pump();
    expect(focus.hasFocus, isTrue);
    expect(mounts, [1]);

    layout.setPanelAlignment(PanelAlignment.justify);
    await tester.pump();
    expect(focus.hasFocus, isTrue);
    expect(mounts, [1], reason: 'the editor subtree should keep its State');

    focus.dispose();
    layout.dispose();
  });

  testWidgets('projected sidebar and Panel dividers save their weights',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final layout = WorkbenchLayout();
    layout
      ..setRegionCollapsed('panel', false)
      ..setRegionCollapsed('secondarySidebar', false)
      ..setPanelAlignment(PanelAlignment.center);
    await tester.pumpWidget(_host(layout));
    await tester.pump();

    final sidebarBefore = _rect(tester, 'sidebar').width;
    await tester.drag(
      find.byKey(const ValueKey('wb-div-sidebar-panel-alignment-column')),
      const Offset(40, 0),
    );
    await tester.pump();
    expect(_rect(tester, 'sidebar').width, closeTo(sidebarBefore + 40, 2));

    final panelHeightBefore = _rect(tester, 'panel').height;
    await tester.drag(
      find.byKey(
        const ValueKey('wb-div-panel-alignment-editor-row-panel'),
      ),
      const Offset(0, 40),
    );
    await tester.pump();
    expect(
      _rect(tester, 'panel').height,
      closeTo(panelHeightBefore + 40, 2),
    );

    final restored = WorkbenchLayout(
      root: WbNode.fromJson(layout.root.toJson()) as WbSplit,
    );
    expect(restored.root.toJson(), layout.root.toJson());
    expect(restored.panelAlignment, PanelAlignment.center);
    restored.dispose();
    layout.dispose();
  });
}
