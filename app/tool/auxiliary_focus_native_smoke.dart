import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'package:alula_app/workbench/auxiliary_focus_context.dart';
import 'package:alula_app/workbench/auxiliary_window.dart';
import 'package:alula_app/workbench/keybindings.dart';
import 'package:alula_app/workbench/layout_store.dart';
import 'package:alula_app/workbench/session_store.dart';
import 'package:alula_app/workbench/workbench_page.dart';

const _mainTitle = 'Alula Focus Main';
const _auxiliaryTitle = 'Alula Focus Probe';
const _documentSentinel = 'FOCUS_DOCUMENT_SECRET_DO_NOT_SYNC';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  final current = await WindowController.fromCurrentEngine();
  final payload = AuxiliaryWindowPayload.fromArguments(current.arguments);
  if (payload.isAuxiliary) {
    await runAlulaAuxiliaryEngine(payload.toArguments());
    return;
  }

  await windowManager.ensureInitialized();
  await windowManager.setPreventClose(true);
  await windowManager.waitUntilReadyToShow(
    const WindowOptions(
      title: _mainTitle,
      size: Size(1000, 700),
      minimumSize: Size(700, 480),
    ),
    () async {
      await windowManager.show();
      await windowManager.focus();
    },
  );
  runApp(_FocusSmokeMain(windowId: current.windowId));
}

class _FocusSmokeMain extends StatefulWidget {
  const _FocusSmokeMain({required this.windowId});

  final String windowId;

  @override
  State<_FocusSmokeMain> createState() => _FocusSmokeMainState();
}

class _FocusSmokeMainState extends State<_FocusSmokeMain> {
  Future<void> _traceWrites = Future<void>.value();
  bool _auxiliaryStarted = false;

  String get _stateDirectory =>
      Platform.environment['ALULA_AUXILIARY_FOCUS_SMOKE_DIR'] ??
      Directory.systemTemp.path;

  void _recordSnapshot(AuxiliaryFocusContextSnapshot snapshot) {
    final path = Platform.environment['ALULA_AUXILIARY_FOCUS_TRACE'];
    if (path != null && path.isNotEmpty) {
      final line = '${jsonEncode(snapshot.toMap())}\n';
      _traceWrites = _traceWrites.then((_) async {
        await File(path).writeAsString(
          line,
          mode: FileMode.append,
          flush: true,
        );
      });
    }

    if (snapshot.windowId == widget.windowId && !_auxiliaryStarted) {
      _auxiliaryStarted = true;
      unawaited(_openAuxiliaryWindow());
    }
  }

  Future<void> _openAuxiliaryWindow() async {
    try {
      await _traceWrites;
      final payload = AuxiliaryWindowPayload.forDocument(
        mainWindowId: widget.windowId,
        name: _auxiliaryTitle,
        text: _documentSentinel,
        dirty: true,
      );
      final controller = await WindowController.create(
        WindowConfiguration(arguments: payload.toArguments()),
      );
      await controller.show();
    } on Object catch (error) {
      stderr.writeln('Could not create auxiliary focus window: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: WorkbenchPage(
        layoutStore: LayoutStore(path: '$_stateDirectory/layout.json'),
        sessionStore: SessionStore(path: '$_stateDirectory/session.json'),
        keybindingsStore:
            KeybindingsStore(path: '$_stateDirectory/keybindings.json'),
        onAuxiliaryFocusContextChanged: _recordSnapshot,
      ),
    );
  }
}
