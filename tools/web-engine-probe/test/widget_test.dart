import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:web_engine_probe/main.dart';

void main() {
  testWidgets('WebView is absent until the browser feature is opened', (
    tester,
  ) async {
    await tester.pumpWidget(const WebEngineProbeApp());

    expect(
      find.text('Create the WebView only when this feature is used.'),
      findsOneWidget,
    );
    expect(find.byType(InAppWebView), findsNothing);
  });
}
