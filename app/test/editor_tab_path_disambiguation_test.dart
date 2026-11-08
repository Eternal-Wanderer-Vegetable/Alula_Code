import 'dart:io';

import 'package:alula_app/main.dart';
import 'package:alula_app/workbench/layout_model.dart';
import 'package:alula_app/workbench/layout_store.dart';
import 'package:alula_app/workbench/session_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pressChord(
  WidgetTester tester,
  LogicalKeyboardKey key, {
  bool control = false,
  bool shift = false,
}) async {
  if (control) await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyEvent(key);
  if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  if (control) await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pump();
}

void main() {
  testWidgets(
    'tab path labels are group-local, measured, accessible, and recomputed',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final semantics = tester.ensureSemantics();

      final temp = Directory.systemTemp.createTempSync('alula_tab_paths');
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        if (temp.existsSync()) await temp.delete(recursive: true);
      });
      final workspace = Directory('${temp.path}/workspace')..createSync();
      final sourceDirectory = Directory('${workspace.path}/src')..createSync();
      File('${workspace.path}/Cargo.toml').writeAsStringSync('''
[package]
name = "tab-label-fixture"
version = "0.1.0"
edition = "2021"
''');
      File('${sourceDirectory.path}/main.rs')
          .writeAsStringSync('fn main() {}\n');
      final alpha = Directory('${workspace.path}/alpha')..createSync();
      final beta = Directory('${workspace.path}/beta')..createSync();
      final gamma = Directory('${workspace.path}/gamma')..createSync();
      const source = 'fn same_name_fixture() {}\n';
      final alphaFile = File('${alpha.path}/main.rs')
        ..writeAsStringSync(source);
      final betaFile = File('${beta.path}/main.rs')..writeAsStringSync(source);
      final targetPath = '${gamma.path}/main.rs'.replaceAll(r'\', '/');
      final root = temp.path.replaceAll(r'\', '/');
      final layout = defaultLayout();
      expect(
          layout.splitLeaf('editor', 'editor-2', Axis.horizontal), isNotNull);
      final layoutStore = LayoutStore(path: '$root/layout.json')..save(layout);
      final originalLayout = File('$root/layout.json').readAsStringSync();
      final sessionStore = SessionStore(path: '$root/session.json');
      sessionStore.save({
        'v': 1,
        'focused': 'editor',
        'workspace': workspace.path,
        'groups': [
          {
            'region': 'editor',
            'active': 10,
            'docs': [
              {'id': 10, 'path': alphaFile.path},
              {'id': 11, 'path': betaFile.path},
            ],
          },
          {
            'region': 'editor-2',
            'active': 10,
            'docs': [
              {'id': 10, 'path': alphaFile.path},
            ],
          },
        ],
      });

      Future<void> settle(String label) async {
        await tester.pumpAndSettle().timeout(
              const Duration(seconds: 10),
              onTimeout: () =>
                  throw StateError('pumpAndSettle timed out: $label'),
            );
      }

      Finder tab(String region, int id) => find.descendant(
            of: find.byKey(ValueKey('editor-tab-strip-$region')),
            matching: find.byKey(ValueKey('tab-$id')),
          );

      Finder label(String region, int id) =>
          find.byKey(ValueKey('editor-tab-label-$region-$id'));

      Future<void> chooseMode(String labelText) async {
        await tester.tap(find.text('查看(V)'));
        await settle('View menu');
        await tester.tap(find.text('外观(A)'));
        await settle('Appearance submenu');
        await tester.tap(find.text('编辑器标签'));
        await settle('Editor tabs submenu');
        await tester.tap(find.text(labelText));
        await settle('select $labelText');
      }

      Future<void> chooseSizing(String labelText) async {
        await tester.tap(find.text('查看(V)'));
        await settle('View menu');
        await tester.tap(find.text('外观(A)'));
        await settle('Appearance submenu');
        await tester.tap(find.text('编辑器标签'));
        await settle('Editor tabs submenu');
        await tester.tap(find.text('标签尺寸'));
        await settle('Tab sizing submenu');
        await tester.tap(find.text(labelText));
        await settle('select tab sizing $labelText');
      }

      Future<void> toggleWrap() async {
        await tester.tap(find.text('查看(V)'));
        await settle('View menu');
        await tester.tap(find.text('外观(A)'));
        await settle('Appearance submenu');
        await tester.tap(find.text('编辑器标签'));
        await settle('Editor tabs submenu');
        await tester.tap(find.text('标签自动换行'));
        await settle('toggle tab wrapping');
      }

      await tester.pumpWidget(AlulaApp(
        layoutStore: layoutStore,
        sessionStore: sessionStore,
      ));
      await tester.pump(const Duration(milliseconds: 500));

      expect(tester.widget<Text>(label('editor', 10)).data, 'main.rs — alpha');
      expect(tester.widget<Text>(label('editor', 11)).data, 'main.rs — beta');
      expect(tester.widget<Text>(label('editor-2', 10)).data, 'main.rs',
          reason:
              'the second group does not inherit another group’s collision');
      expect(
        tester
            .widget<Tooltip>(find
                .ancestor(
                  of: label('editor', 10),
                  matching: find.byType(Tooltip),
                )
                .first)
            .message,
        'main.rs — alpha',
      );
      expect(tester.getSemantics(label('editor', 10)).label, 'main.rs — alpha');
      expect(
        tester.getSize(tab('editor', 10)).width,
        greaterThan(tester.getSize(tab('editor-2', 10)).width),
        reason: 'the measured fit width includes the path suffix',
      );
      expect(find.byKey(const ValueKey('close-tab-editor-10')), findsOneWidget);

      await chooseSizing('收缩');
      expect(tester.widget<Text>(label('editor', 10)).data, 'main.rs — alpha');
      expect(tester.getSize(tab('editor', 10)).width, greaterThanOrEqualTo(80));
      await toggleWrap();
      expect(tester.widget<Text>(label('editor', 11)).data, 'main.rs — beta');
      await chooseSizing('固定宽度');
      final fixedWidths = [
        tab('editor', 10),
        tab('editor', 11),
        tab('editor', 1),
      ].map((finder) => tester.getSize(finder).width);
      expect(fixedWidths.toSet(), hasLength(1));
      expect(tester.widget<Text>(label('editor', 10)).data, 'main.rs — alpha');
      await toggleWrap();
      await chooseSizing('按内容适配');

      await chooseMode('单标签');
      expect(tab('editor', 10), findsOneWidget);
      expect(tab('editor', 11), findsNothing);
      expect(tester.widget<Text>(label('editor', 10)).data, 'main.rs — alpha',
          reason:
              'single mode derives its active label from all group documents');
      expect(tester.widget<Text>(label('editor-2', 10)).data, 'main.rs');

      await chooseMode('不显示标签');
      expect(find.byKey(const ValueKey('editor-tab-label-editor-10')),
          findsNothing);
      expect(find.byKey(const ValueKey('editor-tab-label-editor-11')),
          findsNothing);
      await chooseMode('多标签');

      await _pressChord(tester, LogicalKeyboardKey.keyS,
          control: true, shift: true);
      await tester.pump(const Duration(milliseconds: 100));
      final savePathField = find.byKey(const ValueKey('save-as-path'));
      expect(savePathField, findsOneWidget);
      await tester.enterText(savePathField, targetPath);
      await tester.tap(find.byKey(const ValueKey('save-as-confirm')));
      await tester.pump(const Duration(milliseconds: 500));
      await settle('Save As path change');

      expect(File(targetPath).readAsStringSync(), source);
      expect(alphaFile.readAsStringSync(), source,
          reason: 'renaming a label does not change the previous file');
      expect(tester.widget<Text>(label('editor', 10)).data, 'main.rs — gamma');
      expect(tester.widget<Text>(label('editor', 11)).data, 'main.rs — beta');
      expect(tester.widget<Text>(label('editor-2', 10)).data, 'main.rs');

      final closeAction = tester.widget<InkWell>(
        find.byKey(const ValueKey('close-tab-editor-11')),
      );
      closeAction.focusNode!.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await settle('close colliding tab');

      expect(tab('editor', 10), findsOneWidget);
      expect(tab('editor', 11), findsNothing);
      expect(tester.widget<Text>(label('editor', 10)).data, 'main.rs',
          reason: 'closing the last colliding tab restores the basename');
      expect(tester.widget<Text>(label('editor-2', 10)).data, 'main.rs');
      expect(File('$root/layout.json').readAsStringSync(), originalLayout,
          reason: 'presentation changes do not rewrite the editor layout');

      await tester.pump(const Duration(milliseconds: 700));
      final session = sessionStore.tryLoad()!;
      final groups = (session['groups']! as List).cast<Map>();
      final editorGroup =
          groups.firstWhere((group) => group['region'] == 'editor');
      final secondGroup =
          groups.firstWhere((group) => group['region'] == 'editor-2');
      expect(editorGroup['active'], 10);
      expect((editorGroup['docs']! as List).map((doc) => doc['id']), [10, 1],
          reason: 'closing one tab preserves the active and welcome documents');
      expect((secondGroup['docs']! as List).map((doc) => doc['id']), [10]);
      expect((editorGroup['docs']! as List).first['path'], targetPath);
      expect((secondGroup['docs']! as List).first['path'], targetPath);
      expect(find.byTooltip('main.rs'), findsNWidgets(2));
      semantics.dispose();
    },
  );
}
