import 'package:flutter_test/flutter_test.dart';

/// Opens an Explorer file and pins its preview tab with a double-click.
Future<void> openPinnedExplorerFile(
  WidgetTester tester,
  Finder target,
) async {
  final explorerItem = target.first;
  await tester.tap(explorerItem);
  await tester.tap(explorerItem);
  await tester.pump();
}
