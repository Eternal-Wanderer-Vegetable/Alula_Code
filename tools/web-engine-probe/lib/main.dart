import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

void main() {
  runApp(
    WebEngineProbeApp(autoProbe: Platform.environment['P00_4_WEB_AUTO'] == '1'),
  );
}

class WebEngineProbeApp extends StatelessWidget {
  const WebEngineProbeApp({super.key, this.autoProbe = false});

  final bool autoProbe;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'P00.4 Web Engine Probe',
      theme: ThemeData(colorSchemeSeed: const Color(0xff376dd4)),
      home: WebEngineProbePage(autoProbe: autoProbe),
    );
  }
}

class WebEngineProbePage extends StatefulWidget {
  const WebEngineProbePage({super.key, required this.autoProbe});

  final bool autoProbe;

  @override
  State<WebEngineProbePage> createState() => _WebEngineProbePageState();
}

class _WebEngineProbePageState extends State<WebEngineProbePage> {
  static const _pageHtml = '''
<!doctype html>
<html><head><meta charset="utf-8"><title>Alula Web Probe</title>
<style>body{font:20px sans-serif;background:#f4f7ff;padding:32px}h1{color:#194fa8}</style>
</head><body><h1>WEB_ENGINE_PROBE_OK</h1>
<p id="resource">Offline data URI resource:</p>
<img alt="probe" width="16" height="16" src="data:image/gif;base64,R0lGODlhAQABAAD/ACwAAAAAAQABAAACADs=" />
<script>document.body.dataset.ready = 'true';</script></body></html>
''';

  bool _showWebView = false;
  bool _autoProbeStarted = false;
  InAppWebViewController? _controller;
  final _shortcutFocusNode = FocusNode(
    debugLabel: 'Web Engine Probe shortcuts',
  );
  String _status = 'WebView not created';
  String? _archivePath;
  int? _archiveBytes;

  @override
  void initState() {
    super.initState();
    if (widget.autoProbe) {
      Future<void>.delayed(const Duration(seconds: 4), () {
        if (mounted) _toggleWebView();
      });
    }
  }

  void _toggleWebView() {
    final removing = _showWebView;
    setState(() {
      _showWebView = !_showWebView;
      _controller = null;
      _status = _showWebView
          ? 'Creating WebView2…'
          : 'WebView widget removed; waiting for child cleanup';
    });
    if (widget.autoProbe && removing) {
      unawaited(_writeAutoPhase('webview-destroyed'));
    }
  }

  Future<void> _writeAutoPhase(String phase) async {
    final file = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}p00.4-web-probe-phase.txt',
    );
    await file.writeAsString(phase, flush: true);
  }

  Future<void> _captureRenderedPage(
    InAppWebViewController controller,
    String phase,
  ) async {
    final result = await controller.callDevToolsProtocolMethod(
      methodName: 'Page.captureScreenshot',
      parameters: const {'format': 'png', 'fromSurface': true},
    );
    final data = result is Map ? result['data'] : null;
    if (data is! String || data.isEmpty) {
      throw StateError('CDP returned no screenshot data: $result');
    }
    final file = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}p00.4-web-$phase-render.png',
    );
    await file.writeAsBytes(base64Decode(data), flush: true);
  }

  KeyEventResult _handleShortcut(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    switch (event.logicalKey) {
      case LogicalKeyboardKey.f5:
        _toggleWebView();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.f6:
        _captureMhtml();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.f7:
        _openMhtml();
        return KeyEventResult.handled;
      default:
        return KeyEventResult.ignored;
    }
  }

  Future<void> _captureMhtml() async {
    final controller = _controller;
    if (controller == null) return;

    setState(() => _status = 'Calling Page.captureSnapshot(format=mhtml)…');
    try {
      final result = await controller.callDevToolsProtocolMethod(
        methodName: 'Page.captureSnapshot',
        parameters: const {'format': 'mhtml'},
      );
      final data = result is Map ? result['data'] : null;
      if (data is! String || data.isEmpty) {
        throw StateError('CDP returned no snapshot data: $result');
      }

      final file = File(
        '${Directory.systemTemp.path}${Platform.pathSeparator}p00.4-web-probe.mhtml',
      );
      await file.writeAsString(data, flush: true);
      final hasMimeHeader = data.toLowerCase().contains('mime-version:');
      final hasProbePage = data.contains('WEB_ENGINE_PROBE_OK');
      final archiveBytes = await file.length();
      setState(() {
        _archivePath = file.path;
        _archiveBytes = archiveBytes;
        _status =
            'CDP snapshot saved; MIME header=$hasMimeHeader, page marker=$hasProbePage';
      });
    } catch (error) {
      setState(() => _status = 'CDP/MHTML failed: $error');
    }
  }

  Future<void> _openMhtml() async {
    final controller = _controller;
    final path = _archivePath;
    if (controller == null || path == null) return;

    try {
      await controller.loadUrl(
        urlRequest: URLRequest(url: WebUri(File(path).uri.toString())),
      );
      setState(() => _status = 'Navigated to saved MHTML file');
    } catch (error) {
      setState(() => _status = 'Opening saved MHTML failed: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Focus(
      focusNode: _shortcutFocusNode,
      autofocus: true,
      onKeyEvent: _handleShortcut,
      child: Scaffold(
        appBar: AppBar(title: const Text('P00.4 Web Engine Probe')),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton(
                    onPressed: _toggleWebView,
                    child: Text(
                      _showWebView ? 'Destroy WebView' : 'Create WebView',
                    ),
                  ),
                  OutlinedButton(
                    onPressed: controller == null ? null : _captureMhtml,
                    child: const Text('Capture CDP MHTML'),
                  ),
                  OutlinedButton(
                    onPressed: controller == null || _archivePath == null
                        ? null
                        : _openMhtml,
                    child: const Text('Open saved MHTML'),
                  ),
                ],
              ),
            ),
            Container(
              width: double.infinity,
              color: const Color(0xffeef2f8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: SelectableText(
                [
                  _status,
                  if (_archivePath != null) 'Archive: $_archivePath',
                  if (_archiveBytes != null) 'Archive bytes: $_archiveBytes',
                ].join('\n'),
              ),
            ),
            Expanded(
              child: _showWebView
                  ? InAppWebView(
                      initialData: InAppWebViewInitialData(data: _pageHtml),
                      initialSettings: InAppWebViewSettings(
                        isInspectable: true,
                      ),
                      onWebViewCreated: (value) {
                        setState(() {
                          _controller = value;
                          _status = 'WebView created';
                        });
                        _shortcutFocusNode.requestFocus();
                      },
                      onLoadStop: (value, url) async {
                        final title = await value.evaluateJavascript(
                          source: 'document.title',
                        );
                        if (!mounted) return;
                        setState(() => _status = 'Loaded $url; title=$title');
                        _shortcutFocusNode.requestFocus();
                        final openedArchive = url.toString().contains(
                          'p00.4-web-probe.mhtml',
                        );
                        if (widget.autoProbe) {
                          final phase = openedArchive ? 'mhtml' : 'initial';
                          await _captureRenderedPage(value, phase);
                          await _writeAutoPhase(
                            openedArchive ? 'mhtml-loaded' : 'initial-loaded',
                          );
                        }
                        if (widget.autoProbe &&
                            !openedArchive &&
                            !_autoProbeStarted) {
                          _autoProbeStarted = true;
                          unawaited(_runAutomaticReplay());
                        }
                      },
                      onReceivedError: (value, request, error) {
                        setState(
                          () => _status = 'Load error: ${error.description}',
                        );
                      },
                    )
                  : const Center(
                      child: Text(
                        'Create the WebView only when this feature is used.',
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _runAutomaticReplay() async {
    await Future<void>.delayed(const Duration(seconds: 5));
    await _captureMhtml();
    await Future<void>.delayed(const Duration(seconds: 2));
    await _openMhtml();
    await Future<void>.delayed(const Duration(seconds: 8));
    if (mounted) _toggleWebView();
  }

  @override
  void dispose() {
    _shortcutFocusNode.dispose();
    super.dispose();
  }
}
