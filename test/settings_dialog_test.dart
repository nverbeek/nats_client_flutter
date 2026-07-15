import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nats_client_flutter/settings_dialog.dart';

void main() {
  Widget buildDialog(
      void Function(double, int, bool, bool, bool, bool, bool, bool)
          onSave) {
    return MaterialApp(
      home: Scaffold(
        body: SettingsDialog(
          initialFontSize: 14,
          initialRetryInterval: 5,
          initialJetStreamEnabled: true,
          initialKvEnabled: true,
          initialObjectStoreEnabled: true,
          initialServiceDiscoveryEnabled: true,
          initialUpdateCheckEnabled: true,
          initialShowSubscriptionColors: true,
          onSave: onSave,
        ),
      ),
    );
  }

  testWidgets('shows the initial values', (tester) async {
    await tester.pumpWidget(
        buildDialog((_, __, ___, ____, _____, ______, _______, ________) {}));

    expect(find.text('14'), findsOneWidget);
    expect(find.text('5 seconds'), findsOneWidget);

    final switches = tester.widgetList<Switch>(find.byType(Switch)).toList();
    final showSubscriptionColorsSwitch = switches[0];
    final jetStreamSwitch = switches[1];
    final kvSwitch = switches[2];
    final objectStoreSwitch = switches[3];
    final serviceDiscoverySwitch = switches[4];
    final updateCheckSwitch = switches[5];
    expect(showSubscriptionColorsSwitch.value, isTrue);
    expect(jetStreamSwitch.value, isTrue);
    expect(kvSwitch.value, isTrue);
    expect(objectStoreSwitch.value, isTrue);
    expect(serviceDiscoverySwitch.value, isTrue);
    expect(updateCheckSwitch.value, isTrue);
  });

  testWidgets('toggling Show Subscription Colors flips its switch',
      (tester) async {
    await tester.pumpWidget(
        buildDialog((_, __, ___, ____, _____, ______, _______, ________) {}));

    final showSubscriptionColorsSwitchFinder = find.byType(Switch).at(0);
    await tester.tap(showSubscriptionColorsSwitchFinder);
    await tester.pump();

    final showSubscriptionColorsSwitch =
        tester.widget<Switch>(showSubscriptionColorsSwitchFinder);
    expect(showSubscriptionColorsSwitch.value, isFalse);
  });

  testWidgets('toggling Enable JetStream flips its switch', (tester) async {
    await tester.pumpWidget(
        buildDialog((_, __, ___, ____, _____, ______, _______, ________) {}));

    final jetStreamSwitchFinder = find.byType(Switch).at(1);
    await tester.tap(jetStreamSwitchFinder);
    await tester.pump();

    final jetStreamSwitch = tester.widget<Switch>(jetStreamSwitchFinder);
    expect(jetStreamSwitch.value, isFalse);
  });

  testWidgets('toggling Enable Key-Value Stores flips its switch',
      (tester) async {
    await tester.pumpWidget(
        buildDialog((_, __, ___, ____, _____, ______, _______, ________) {}));

    final kvSwitchFinder = find.byType(Switch).at(2);
    await tester.tap(kvSwitchFinder);
    await tester.pump();

    final kvSwitch = tester.widget<Switch>(kvSwitchFinder);
    expect(kvSwitch.value, isFalse);
  });

  testWidgets('toggling Enable Object Store flips its switch', (tester) async {
    await tester.pumpWidget(
        buildDialog((_, __, ___, ____, _____, ______, _______, ________) {}));

    final objectStoreSwitchFinder = find.byType(Switch).at(3);
    await tester.tap(objectStoreSwitchFinder);
    await tester.pump();

    final objectStoreSwitch = tester.widget<Switch>(objectStoreSwitchFinder);
    expect(objectStoreSwitch.value, isFalse);
  });

  testWidgets('toggling Enable Service Discovery flips its switch',
      (tester) async {
    await tester.pumpWidget(
        buildDialog((_, __, ___, ____, _____, ______, _______, ________) {}));

    // The dialog's content is scrollable once this many toggles are present
    // — scroll the switch into view before tapping it, same reasoning as
    // the Check for Updates test below.
    final serviceDiscoverySwitchFinder = find.byType(Switch).at(4);
    await tester.ensureVisible(serviceDiscoverySwitchFinder);
    await tester.tap(serviceDiscoverySwitchFinder);
    await tester.pump();

    final serviceDiscoverySwitch =
        tester.widget<Switch>(serviceDiscoverySwitchFinder);
    expect(serviceDiscoverySwitch.value, isFalse);
  });

  testWidgets('toggling Check for Updates flips its switch', (tester) async {
    await tester.pumpWidget(
        buildDialog((_, __, ___, ____, _____, ______, _______, ________) {}));

    // The dialog's content became scrollable once the Object Store toggle
    // pushed it past the fixed content height — scroll the last switch into
    // view before tapping it, or the tap misses (hits whatever's on top of
    // the still-off-screen widget instead).
    await tester.ensureVisible(find.byType(Switch).last);
    await tester.tap(find.byType(Switch).last);
    await tester.pump();

    final updateCheckSwitch = tester.widget<Switch>(find.byType(Switch).last);
    expect(updateCheckSwitch.value, isFalse);
  });

  testWidgets('changing the Reconnect Interval dropdown updates the value',
      (tester) async {
    await tester.pumpWidget(
        buildDialog((_, __, ___, ____, _____, ______, _______, ________) {}));

    await tester.tap(find.text('5 seconds'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('10 seconds').last);
    await tester.pumpAndSettle();

    expect(find.text('10 seconds'), findsOneWidget);
  });

  testWidgets('dragging the font size slider updates the displayed value',
      (tester) async {
    await tester.pumpWidget(
        buildDialog((_, __, ___, ____, _____, ______, _______, ________) {}));

    expect(find.text('14'), findsOneWidget);
    await tester.drag(find.byType(Slider), const Offset(200, 0));
    await tester.pump();

    expect(find.text('14'), findsNothing);
  });

  testWidgets('Cancel pops without calling onSave', (tester) async {
    var saveCalled = false;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (context) => SettingsDialog(
                  initialFontSize: 14,
                  initialRetryInterval: 5,
                  initialJetStreamEnabled: true,
                  initialKvEnabled: true,
                  initialObjectStoreEnabled: true,
                  initialServiceDiscoveryEnabled: true,
                  initialUpdateCheckEnabled: true,
                  initialShowSubscriptionColors: true,
                  onSave: (_, __, ___, ____, _____, ______, _______,
                          ________) =>
                      saveCalled = true,
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(saveCalled, isFalse);
    expect(find.byType(SettingsDialog), findsNothing);
  });

  testWidgets('Save calls onSave with the current values then pops',
      (tester) async {
    double? savedFontSize;
    int? savedRetryInterval;
    bool? savedJetStreamEnabled;
    bool? savedKvEnabled;
    bool? savedObjectStoreEnabled;
    bool? savedServiceDiscoveryEnabled;
    bool? savedUpdateCheckEnabled;
    bool? savedShowSubscriptionColors;

    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (context) => SettingsDialog(
                  initialFontSize: 14,
                  initialRetryInterval: 5,
                  initialJetStreamEnabled: true,
                  initialKvEnabled: true,
                  initialObjectStoreEnabled: true,
                  initialServiceDiscoveryEnabled: true,
                  initialUpdateCheckEnabled: true,
                  initialShowSubscriptionColors: true,
                  onSave: (fontSize, retryInterval, jetStream, kv,
                      objectStore, serviceDiscovery, updateCheck,
                      showSubscriptionColors) {
                    savedFontSize = fontSize;
                    savedRetryInterval = retryInterval;
                    savedJetStreamEnabled = jetStream;
                    savedKvEnabled = kv;
                    savedObjectStoreEnabled = objectStore;
                    savedServiceDiscoveryEnabled = serviceDiscovery;
                    savedUpdateCheckEnabled = updateCheck;
                    savedShowSubscriptionColors = showSubscriptionColors;
                  },
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    // Index 1 is the JetStream switch now that Show Subscription Colors
    // occupies index 0 — see the widget-order comment in settings_dialog.dart.
    await tester.tap(find.byType(Switch).at(1));
    await tester.pump();
    await tester.tap(find.widgetWithText(TextButton, 'Save'));
    await tester.pumpAndSettle();

    expect(savedFontSize, 14);
    expect(savedRetryInterval, 5);
    expect(savedJetStreamEnabled, isFalse);
    expect(savedKvEnabled, isTrue);
    expect(savedObjectStoreEnabled, isTrue);
    expect(savedServiceDiscoveryEnabled, isTrue);
    expect(savedUpdateCheckEnabled, isTrue);
    expect(savedShowSubscriptionColors, isTrue);
    expect(find.byType(SettingsDialog), findsNothing);
  });
}
