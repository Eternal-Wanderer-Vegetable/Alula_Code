import 'package:integration_test/integration_test.dart';

import '../test/workbench_multi_selection_test.dart' as multi_selection;
import '../test/workbench_multi_view_test.dart' as multi_view;

/// Runs the P03.7 editor interaction suites inside a real Windows desktop
/// Flutter engine. The scenarios themselves are shared with `flutter test`.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  multi_view.main();
  multi_selection.main();
}
