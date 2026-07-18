import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'helpers/nats_test_app.dart';

/// Confirms the AppBar's icon-only buttons (Settings, theme toggle, Help)
/// carry tooltips -- these were the app's main accessibility gap before
/// being fixed. No live server needed: these icons are always present
/// regardless of connection state.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('AppBar icons have tooltips', (tester) async {
    await pumpDisconnectedApp(tester);

    expect(find.byTooltip('Settings'), findsOneWidget);
    expect(find.byTooltip('Toggle light/dark theme'), findsOneWidget);
    expect(find.byTooltip('Help'), findsOneWidget);
  });
}
