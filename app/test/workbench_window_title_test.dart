import 'package:alula_app/workbench/workbench_window_title.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('title omits missing editor and workspace values', () {
    expect(
      WorkbenchWindowTitle.compose(
        platform: TargetPlatform.linux,
        activeEditorName: null,
        dirty: false,
        workspaceName: null,
      ),
      'Alula Code',
    );
    expect(
      WorkbenchWindowTitle.compose(
        platform: TargetPlatform.windows,
        activeEditorName: '  ',
        dirty: true,
        workspaceName: '  ',
      ),
      'Alula Code',
    );
  });

  test('title includes workspace and optional profile with platform separator',
      () {
    expect(
      WorkbenchWindowTitle.compose(
        platform: TargetPlatform.windows,
        activeEditorName: null,
        dirty: false,
        workspaceName: 'sample',
        profileName: 'Work',
      ),
      'sample - Work - Alula Code',
    );
    expect(
      WorkbenchWindowTitle.compose(
        platform: TargetPlatform.macOS,
        activeEditorName: null,
        dirty: false,
        workspaceName: 'sample',
      ),
      'sample — Alula Code',
    );
  });

  test('title tracks saved, dirty, and untitled active documents', () {
    expect(
      WorkbenchWindowTitle.compose(
        platform: TargetPlatform.linux,
        activeEditorName: 'main.dart',
        dirty: false,
        workspaceName: 'sample',
      ),
      'main.dart - sample - Alula Code',
    );
    expect(
      WorkbenchWindowTitle.compose(
        platform: TargetPlatform.linux,
        activeEditorName: 'main.dart',
        dirty: true,
        workspaceName: 'sample',
      ),
      '● main.dart - sample - Alula Code',
    );
    expect(
      WorkbenchWindowTitle.compose(
        platform: TargetPlatform.linux,
        activeEditorName: '未命名-2',
        dirty: true,
        workspaceName: null,
      ),
      '● 未命名-2 - Alula Code',
    );
  });
}
