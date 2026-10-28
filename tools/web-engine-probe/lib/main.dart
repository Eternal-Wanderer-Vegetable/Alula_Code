import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

void main() {
  final autoProbe = Platform.environment['P00_4_WEB_AUTO'] == '1';
  stdout.writeln(
    'P00_4_PROBE_MAIN autoProbe=$autoProbe '
    'systemTemp=${Directory.systemTemp.path} '
    'TMPDIR=${Platform.environment['TMPDIR'] ?? '(unset)'}',
  );
  runApp(WebEngineProbeApp(autoProbe: autoProbe));
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

  bool get _usesWebArchive => Platform.isMacOS;

  bool get _usesLinuxMhtml => Platform.isLinux;

  String get _archiveExtension => _usesWebArchive
      ? 'webarchive'
      : _usesLinuxMhtml
      ? 'mht'
      : 'mhtml';

  String get _archiveReloadedPhase =>
      _usesWebArchive ? 'webarchive-loaded' : 'mhtml-loaded';

  String get _archiveFileName => 'p00.4-web-probe.$_archiveExtension';

  @override
  void initState() {
    super.initState();
    stdout.writeln(
      'P00_4_PROBE_INIT autoProbe=${widget.autoProbe} '
      'systemTemp=${Directory.systemTemp.path} '
      'TMPDIR=${Platform.environment['TMPDIR'] ?? '(unset)'}',
    );
    if (widget.autoProbe) {
      Future<void>.delayed(const Duration(seconds: 4), () {
        stdout.writeln('P00_4_AUTO_TOGGLE mounted=$mounted');
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
    stdout.writeln('P00_4_PHASE phase=$phase path=${file.path}');
    await file.writeAsString(phase, flush: true);
  }

  Future<void> _captureRenderedPage(
    InAppWebViewController controller,
    String phase,
  ) async {
    if (Platform.environment['P00_4_WEB_NO_CAPTURE'] == '1') return;

    if (_usesWebArchive || _usesLinuxMhtml) {
      final capture = _usesLinuxMhtml
          ? await _captureLinuxFrame(controller, phase)
          : null;
      final title = await controller.evaluateJavascript(
        source: 'document.title',
      );
      final hasProbeMarker = await controller.evaluateJavascript(
        source: "document.body.innerText.includes('WEB_ENGINE_PROBE_OK')",
      );
      if (hasProbeMarker != true) {
        throw StateError('WebView page marker is missing after $phase');
      }
      final file = File(
        '${Directory.systemTemp.path}${Platform.pathSeparator}'
        'p00.4-web-$phase-page.json',
      );
      await file.writeAsString(
        jsonEncode({
          'phase': phase,
          'title': title,
          'hasProbeMarker': hasProbeMarker,
          'url': (await controller.getUrl())?.toString(),
          if (_usesLinuxMhtml)
            'cdpMethodSupported': InAppWebViewController.isMethodSupported(
              PlatformInAppWebViewControllerMethod.callDevToolsProtocolMethod,
              platform: TargetPlatform.linux,
            ),
          if (_usesLinuxMhtml)
            'inspectableSettingSupported':
                InAppWebViewSettings.isPropertySupported(
                  InAppWebViewSettingsProperty.isInspectable,
                  platform: TargetPlatform.linux,
                ),
        }),
        flush: true,
      );
      if (capture != null) {
        final imageFile = File(
          '${Directory.systemTemp.path}${Platform.pathSeparator}'
          'p00.4-web-$phase-render.png',
        );
        await imageFile.writeAsBytes(capture.png, flush: true);
        debugPrint(
          'P00.4_WPE_FRAME_CAPTURE phase=$phase '
          'attempts=${capture.attempts} elapsedMs=${capture.elapsedMs}',
        );
      }
      return;
    }

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

  Future<({Uint8List png, int attempts, int elapsedMs})> _captureLinuxFrame(
    InAppWebViewController controller,
    String phase,
  ) async {
    final stopwatch = Stopwatch()..start();
    for (var attempt = 1; attempt <= 30; attempt++) {
      final png = await controller.takeScreenshot();
      if (png != null && png.isNotEmpty && await _hasProbeHeadingPixel(png)) {
        stopwatch.stop();
        return (
          png: png,
          attempts: attempt,
          elapsedMs: stopwatch.elapsedMilliseconds,
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    stopwatch.stop();
    throw StateError(
      'WPE WebKit returned no page-heading frame after $phase '
      '(${stopwatch.elapsedMilliseconds} ms)',
    );
  }

  Future<bool> _hasProbeHeadingPixel(Uint8List png) async {
    final codec = await ui.instantiateImageCodec(png);
    try {
      final frame = await codec.getNextFrame();
      try {
        final pixels = await frame.image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        );
        if (pixels == null) return false;
        for (var offset = 0; offset < pixels.lengthInBytes; offset += 4) {
          final red = pixels.getUint8(offset);
          final green = pixels.getUint8(offset + 1);
          final blue = pixels.getUint8(offset + 2);
          final alpha = pixels.getUint8(offset + 3);
          if (alpha > 0 &&
              red < 60 &&
              green > 40 &&
              green < 120 &&
              blue > 120) {
            return true;
          }
        }
        return false;
      } finally {
        frame.image.dispose();
      }
    } finally {
      codec.dispose();
    }
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

    setState(
      () => _status = _usesWebArchive
          ? 'Creating WKWebView Web Archive…'
          : _usesLinuxMhtml
          ? 'Saving WPE WebKit MHTML…'
          : 'Calling Page.captureSnapshot(format=mhtml)…',
    );
    try {
      if (_usesWebArchive) {
        stdout.writeln('P00_4_ARCHIVE_CAPTURE_BEGIN');
        final data = await controller.createWebArchiveData();
        if (data == null || data.isEmpty) {
          throw StateError('WKWebView returned no Web Archive data');
        }
        stdout.writeln('P00_4_ARCHIVE_CAPTURE_DATA bytes=${data.length}');
        final file = File(
          '${Directory.systemTemp.path}${Platform.pathSeparator}'
          '$_archiveFileName',
        );
        await file.writeAsBytes(data, flush: true);
        final hasProbePage = String.fromCharCodes(data)
            .contains('WEB_ENGINE_PROBE_OK');
        final archiveBytes = await file.length();
        setState(() {
          _archivePath = file.path;
          _archiveBytes = archiveBytes;
          _status = 'WKWebView Web Archive saved; page marker=$hasProbePage';
        });
        stdout.writeln(
          'P00_4_ARCHIVE_SAVED path=${file.path} bytes=$archiveBytes '
          'pageMarker=$hasProbePage',
        );
        return;
      }

      if (_usesLinuxMhtml) {
        final file = File(
          '${Directory.systemTemp.path}${Platform.pathSeparator}'
          '$_archiveFileName',
        );
        final savedPath = await controller.saveWebArchive(
          filePath: file.path,
          autoname: false,
        );
        if (savedPath == null || savedPath.isEmpty) {
          throw StateError('WPE WebKit returned no MHTML archive path');
        }

        final archiveFile = File(savedPath);
        final data = await archiveFile.readAsBytes();
        if (data.isEmpty) {
          throw StateError('WPE WebKit returned an empty MHTML archive');
        }
        final archiveText = String.fromCharCodes(data);
        final hasMimeHeader = archiveText.toLowerCase().contains(
          'mime-version:',
        );
        final hasProbePage = archiveText.contains('WEB_ENGINE_PROBE_OK');
        final archiveBytes = await archiveFile.length();
        setState(() {
          _archivePath = archiveFile.path;
          _archiveBytes = archiveBytes;
          _status =
              'WPE WebKit MHTML saved; MIME header=$hasMimeHeader, page marker=$hasProbePage';
        });
        return;
      }

      final result = await controller.callDevToolsProtocolMethod(
        methodName: 'Page.captureSnapshot',
        parameters: const {'format': 'mhtml'},
      );
      final data = result is Map ? result['data'] : null;
      if (data is! String || data.isEmpty) {
        throw StateError('CDP returned no snapshot data: $result');
      }

      final file = File(
        '${Directory.systemTemp.path}${Platform.pathSeparator}'
        '$_archiveFileName',
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
      if (_usesWebArchive) {
        stdout.writeln('P00_4_ARCHIVE_CAPTURE_ERROR error=$error');
      }
      setState(
        () => _status = _usesWebArchive
            ? 'WKWebView Web Archive failed: $error'
            : _usesLinuxMhtml
            ? 'WPE WebKit MHTML failed: $error'
            : 'CDP/MHTML failed: $error',
      );
    }
  }

  Future<void> _openMhtml() async {
    final controller = _controller;
    final path = _archivePath;
    if (controller == null || path == null) return;

    try {
      final archiveUri = WebUri(File(path).uri.toString());
      stdout.writeln(
        'P00_4_ARCHIVE_LOAD_BEGIN url=$archiveUri readAccess=$archiveUri',
      );
      await controller.loadUrl(
        urlRequest: URLRequest(url: archiveUri),
        allowingReadAccessTo: archiveUri,
      );
      stdout.writeln('P00_4_ARCHIVE_LOAD_REQUEST_RETURNED');
      setState(
        () => _status = _usesWebArchive
            ? 'Navigated to saved Web Archive'
            : 'Navigated to saved MHTML file',
      );
    } catch (error) {
      if (_usesWebArchive) {
        stdout.writeln('P00_4_ARCHIVE_LOAD_REQUEST_ERROR error=$error');
      }
      setState(
        () => _status = _usesWebArchive
            ? 'Opening saved Web Archive failed: $error'
            : 'Opening saved MHTML failed: $error',
      );
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
                    child: Text(
                      _usesWebArchive
                          ? 'Save WKWebView Web Archive'
                          : _usesLinuxMhtml
                          ? 'Save WPE MHTML'
                          : 'Capture CDP MHTML',
                    ),
                  ),
                  OutlinedButton(
                    onPressed: controller == null || _archivePath == null
                        ? null
                        : _openMhtml,
                    child: Text(
                      _usesWebArchive
                          ? 'Open saved Web Archive'
                          : 'Open saved MHTML',
                    ),
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
                        stdout.writeln('P00_4_WEBVIEW_CREATED');
                        setState(() {
                          _controller = value;
                          _status = 'WebView created';
                        });
                        _shortcutFocusNode.requestFocus();
                      },
                      onLoadStart: (value, url) {
                        stdout.writeln('P00_4_LOAD_START url=$url');
                      },
                      onLoadStop: (value, url) async {
                        stdout.writeln('P00_4_LOAD_STOP_BEGIN url=$url');
                        final title = await value.evaluateJavascript(
                          source: 'document.title',
                        );
                        if (!mounted) return;
                        stdout.writeln(
                          'P00_4_LOAD_STOP_READY url=$url title=$title',
                        );
                        setState(() => _status = 'Loaded $url; title=$title');
                        _shortcutFocusNode.requestFocus();
                        final openedArchive = url.toString().endsWith(
                          _archiveFileName,
                        );
                        if (widget.autoProbe) {
                          final phase = openedArchive
                              ? (_usesWebArchive ? 'webarchive' : 'mhtml')
                              : 'initial';
                          await _captureRenderedPage(value, phase);
                          await _writeAutoPhase(
                            openedArchive
                                ? _archiveReloadedPhase
                                : 'initial-loaded',
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
                        stdout.writeln(
                          'P00_4_LOAD_ERROR url=${request.url} '
                          'description=${error.description}',
                        );
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
    if (Platform.environment['P00_4_WEB_NO_CAPTURE'] == '1') {
      await Future<void>.delayed(const Duration(seconds: 8));
      if (mounted) _toggleWebView();
      return;
    }

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
