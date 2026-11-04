import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nats_client_flutter/settings_dialog.dart';

void main() {
  SettingsValues initialValues(
          {int maxMessages = 10000,
          int heartbeatInterval = 120,
          bool serverMonitorEnabled = false,
          int serverMonitorInterval = 2}) =>
      SettingsValues(
        fontSize: 14,
        retryInterval: 5,
        heartbeatInterval: heartbeatInterval,
        jetStreamEnabled: true,
        kvEnabled: true,
        objectStoreEnabled: true,
        serviceDiscoveryEnabled: true,
        serverMonitorEnabled: serverMonitorEnabled,
        serverMonitorPort: 8222,
        serverMonitorInterval: serverMonitorInterval,
        updateCheckEnabled: true,
        showSubscriptionColors: true,
        maxMessages: maxMessages,
        showTimestamps: false,
      );

  Widget buildDialog(void Function(SettingsValues) onSave,
      {int initialMaxMessages = 10000,
      int initialHeartbeatInterval = 120,
      bool serverMonitorEnabled = false,
      int serverMonitorInterval = 2}) {
    return MaterialApp(
      home: Scaffold(
        body: SettingsDialog(
          initial: initialValues(
              maxMessages: initialMaxMessages,
              heartbeatInterval: initialHeartbeatInterval,
              serverMonitorEnabled: serverMonitorEnabled,
              serverMonitorInterval: serverMonitorInterval),
          onSave: onSave,
        ),
      ),
    );
  }

  Finder saveButton() => find.widgetWithText(TextButton, 'Save');

  void noopSave(SettingsValues _) {}

  testWidgets('shows the initial values', (tester) async {
    await tester.pumpWidget(buildDialog(noopSave));

    expect(find.text('14'), findsOneWidget);
    expect(find.text('5 seconds'), findsOneWidget);
    expect(find.text('10k'), findsOneWidget);

    final switches = tester.widgetList<Switch>(find.byType(Switch)).toList();
    final showSubscriptionColorsSwitch = switches[0];
    final jetStreamSwitch = switches[1];
    final kvSwitch = switches[2];
    final objectStoreSwitch = switches[3];
    final serviceDiscoverySwitch = switches[4];
    final serverMonitorSwitch = switches[5];
    final updateCheckSwitch = switches[6];
    final showTimestampsSwitch = switches[7];
    expect(showSubscriptionColorsSwitch.value, isTrue);
    expect(jetStreamSwitch.value, isTrue);
    expect(kvSwitch.value, isTrue);
    expect(objectStoreSwitch.value, isTrue);
    expect(serviceDiscoverySwitch.value, isTrue);
    expect(serverMonitorSwitch.value, isFalse);
    expect(updateCheckSwitch.value, isTrue);
    expect(showTimestampsSwitch.value, isFalse);
    // The port and interval only show while monitoring is on.
    expect(find.byKey(const ValueKey('monitorPortField')), findsNothing);
  });

  testWidgets('turning on Server Monitoring shows its port and interval',
      (tester) async {
    await tester.pumpWidget(buildDialog(noopSave));

    final serverMonitorSwitchFinder = find.byType(Switch).at(5);
    await tester.ensureVisible(serverMonitorSwitchFinder);
    await tester.tap(serverMonitorSwitchFinder);
    await tester.pump();

    expect(find.byKey(const ValueKey('monitorPortField')), findsOneWidget);
    expect(find.text('8222'), findsOneWidget);
    expect(find.text('2 seconds'), findsOneWidget);
  });

  testWidgets('an invalid monitoring port disables Save until fixed',
      (tester) async {
    SettingsValues? saved;
    await tester
        .pumpWidget(buildDialog((v) => saved = v, serverMonitorEnabled: true));

    final portField = find.byKey(const ValueKey('monitorPortField'));
    await tester.ensureVisible(portField);
    await tester.enterText(portField, '70000');
    await tester.pump();
    expect(find.text('Enter a port from 1 to 65535.'), findsOneWidget);
    expect(tester.widget<TextButton>(saveButton()).onPressed, isNull);

    await tester.enterText(portField, '9222');
    await tester.pump();
    expect(find.text('Enter a port from 1 to 65535.'), findsNothing);
    await tester.ensureVisible(saveButton());
    await tester.tap(saveButton());
    await tester.pumpAndSettle();
    expect(saved!.serverMonitorEnabled, isTrue);
    expect(saved!.serverMonitorPort, 9222);
  });

  testWidgets('a bad port does not block Save once monitoring is off again',
      (tester) async {
    SettingsValues? saved;
    await tester
        .pumpWidget(buildDialog((v) => saved = v, serverMonitorEnabled: true));

    final portField = find.byKey(const ValueKey('monitorPortField'));
    await tester.ensureVisible(portField);
    await tester.enterText(portField, 'abc');
    await tester.pump();
    final serverMonitorSwitchFinder = find.byType(Switch).at(5);
    await tester.ensureVisible(serverMonitorSwitchFinder);
    await tester.tap(serverMonitorSwitchFinder);
    await tester.pump();

    await tester.ensureVisible(saveButton());
    await tester.tap(saveButton());
    await tester.pumpAndSettle();
    expect(saved!.serverMonitorEnabled, isFalse);
    // The saved port is left as it was.
    expect(saved!.serverMonitorPort, 8222);
  });

  testWidgets('saves a changed poll interval', (tester) async {
    SettingsValues? saved;
    await tester
        .pumpWidget(buildDialog((v) => saved = v, serverMonitorEnabled: true));

    await tester.ensureVisible(find.text('2 seconds'));
    await tester.tap(find.text('2 seconds'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('10 seconds').last);
    await tester.pumpAndSettle();

    await tester.ensureVisible(saveButton());
    await tester.tap(saveButton());
    await tester.pumpAndSettle();
    expect(saved!.serverMonitorInterval, 10);
  });

  testWidgets(
      'a persisted poll interval outside the standard options still shows '
      'up as a selected item', (tester) async {
    await tester.pumpWidget(buildDialog(noopSave,
        serverMonitorEnabled: true, serverMonitorInterval: 7));

    expect(tester.takeException(), isNull);
    expect(find.text('7 seconds'), findsOneWidget);
  });

  testWidgets('toggling Show Subscription Colors flips its switch',
      (tester) async {
    await tester.pumpWidget(buildDialog(noopSave));

    final showSubscriptionColorsSwitchFinder = find.byType(Switch).at(0);
    await tester.tap(showSubscriptionColorsSwitchFinder);
    await tester.pump();

    final showSubscriptionColorsSwitch =
        tester.widget<Switch>(showSubscriptionColorsSwitchFinder);
    expect(showSubscriptionColorsSwitch.value, isFalse);
  });

  testWidgets('toggling Enable JetStream flips its switch', (tester) async {
    await tester.pumpWidget(buildDialog(noopSave));

    final jetStreamSwitchFinder = find.byType(Switch).at(1);
    await tester.tap(jetStreamSwitchFinder);
    await tester.pump();

    final jetStreamSwitch = tester.widget<Switch>(jetStreamSwitchFinder);
    expect(jetStreamSwitch.value, isFalse);
  });

  testWidgets('toggling Enable Key-Value Stores flips its switch',
      (tester) async {
    await tester.pumpWidget(buildDialog(noopSave));

    final kvSwitchFinder = find.byType(Switch).at(2);
    await tester.tap(kvSwitchFinder);
    await tester.pump();

    final kvSwitch = tester.widget<Switch>(kvSwitchFinder);
    expect(kvSwitch.value, isFalse);
  });

  testWidgets('toggling Enable Object Store flips its switch', (tester) async {
    await tester.pumpWidget(buildDialog(noopSave));

    final objectStoreSwitchFinder = find.byType(Switch).at(3);
    await tester.ensureVisible(objectStoreSwitchFinder);
    await tester.tap(objectStoreSwitchFinder);
    await tester.pump();

    final objectStoreSwitch = tester.widget<Switch>(objectStoreSwitchFinder);
    expect(objectStoreSwitch.value, isFalse);
  });

  testWidgets('toggling Enable Service Discovery flips its switch',
      (tester) async {
    await tester.pumpWidget(buildDialog(noopSave));

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
    await tester.pumpWidget(buildDialog(noopSave));

    final updateCheckSwitchFinder = find.byType(Switch).at(6);
    await tester.ensureVisible(updateCheckSwitchFinder);
    await tester.tap(updateCheckSwitchFinder);
    await tester.pump();

    final updateCheckSwitch = tester.widget<Switch>(updateCheckSwitchFinder);
    expect(updateCheckSwitch.value, isFalse);
  });

  testWidgets('toggling Show Message Timestamps flips its switch',
      (tester) async {
    await tester.pumpWidget(buildDialog(noopSave));

    final showTimestampsSwitchFinder = find.byType(Switch).at(7);
    await tester.ensureVisible(showTimestampsSwitchFinder);
    await tester.tap(showTimestampsSwitchFinder);
    await tester.pump();

    final showTimestampsSwitch =
        tester.widget<Switch>(showTimestampsSwitchFinder);
    expect(showTimestampsSwitch.value, isTrue);
  });

  testWidgets('changing the Reconnect Interval dropdown updates the value',
      (tester) async {
    await tester.pumpWidget(buildDialog(noopSave));

    await tester.tap(find.text('5 seconds'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('10 seconds').last);
    await tester.pumpAndSettle();

    expect(find.text('10 seconds'), findsOneWidget);
  });

  testWidgets('shows the Heartbeat Interval and saves a changed one',
      (tester) async {
    int? saved;
    await tester
        .pumpWidget(buildDialog((values) => saved = values.heartbeatInterval));

    expect(find.text('2 minutes'), findsOneWidget);
    await tester.ensureVisible(find.text('2 minutes'));
    await tester.tap(find.text('2 minutes'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('30 seconds').last);
    await tester.pumpAndSettle();
    expect(find.text('30 seconds'), findsOneWidget);

    await tester.ensureVisible(find.widgetWithText(TextButton, 'Save'));
    await tester.tap(find.widgetWithText(TextButton, 'Save'));
    await tester.pumpAndSettle();
    expect(saved, 30);
  });

  testWidgets(
      'a persisted Heartbeat Interval outside the standard options still '
      'shows up as a selected item', (tester) async {
    await tester
        .pumpWidget(buildDialog(noopSave, initialHeartbeatInterval: 45));

    expect(tester.takeException(), isNull);
    expect(find.text('45 seconds'), findsOneWidget);
  });

  testWidgets('changing the Max Messages Kept dropdown updates the value',
      (tester) async {
    await tester.pumpWidget(buildDialog(noopSave));

    await tester.ensureVisible(find.text('10k'));
    await tester.tap(find.text('10k'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Unlimited').last);
    await tester.pumpAndSettle();

    expect(find.text('Unlimited'), findsOneWidget);
  });

  testWidgets(
      'a persisted Max Messages value outside the standard options still '
      'shows up as a selected item', (tester) async {
    await tester.pumpWidget(buildDialog(noopSave, initialMaxMessages: 42));

    expect(tester.takeException(), isNull);
    expect(find.text('42'), findsOneWidget);
  });

  testWidgets('dragging the font size slider updates the displayed value',
      (tester) async {
    await tester.pumpWidget(buildDialog(noopSave));

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
                  initial: initialValues(),
                  onSave: (_) => saveCalled = true,
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
    SettingsValues? saved;

    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (context) => SettingsDialog(
                  initial: initialValues(),
                  onSave: (values) => saved = values,
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
    final showTimestampsSwitchFinder = find.byType(Switch).at(7);
    await tester.ensureVisible(showTimestampsSwitchFinder);
    await tester.tap(showTimestampsSwitchFinder);
    await tester.pump();
    await tester.tap(find.widgetWithText(TextButton, 'Save'));
    await tester.pumpAndSettle();

    expect(saved!.fontSize, 14);
    expect(saved!.retryInterval, 5);
    expect(saved!.heartbeatInterval, 120);
    expect(saved!.jetStreamEnabled, isFalse);
    expect(saved!.kvEnabled, isTrue);
    expect(saved!.objectStoreEnabled, isTrue);
    expect(saved!.serviceDiscoveryEnabled, isTrue);
    expect(saved!.updateCheckEnabled, isTrue);
    expect(saved!.showSubscriptionColors, isTrue);
    expect(saved!.maxMessages, 10000);
    expect(saved!.showTimestamps, isTrue);
    expect(find.byType(SettingsDialog), findsNothing);
  });
}
