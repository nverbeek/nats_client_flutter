import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nats_client_flutter/settings_dialog.dart';

void main() {
  Widget buildDialog(void Function(double, bool, int, bool, bool, bool) onSave) {
    return MaterialApp(
      home: Scaffold(
        body: SettingsDialog(
          initialFontSize: 14,
          initialSingleLine: false,
          initialRetryInterval: 5,
          initialJetStreamEnabled: true,
          initialKvEnabled: true,
          initialUpdateCheckEnabled: true,
          onSave: onSave,
        ),
      ),
    );
  }

  testWidgets('shows the initial values', (tester) async {
    await tester.pumpWidget(buildDialog((_, __, ___, ____, _____, ______) {}));

    expect(find.text('14'), findsOneWidget);
    expect(find.text('5 seconds'), findsOneWidget);

    final switches = tester.widgetList<Switch>(find.byType(Switch)).toList();
    final singleLineSwitch = switches[0];
    final jetStreamSwitch = switches[1];
    final kvSwitch = switches[2];
    final updateCheckSwitch = switches[3];
    expect(singleLineSwitch.value, isFalse);
    expect(jetStreamSwitch.value, isTrue);
    expect(kvSwitch.value, isTrue);
    expect(updateCheckSwitch.value, isTrue);
  });

  testWidgets('toggling Single Line Messages flips its switch', (tester) async {
    await tester.pumpWidget(buildDialog((_, __, ___, ____, _____, ______) {}));

    await tester.tap(find.byType(Switch).first);
    await tester.pump();

    final singleLineSwitch =
        tester.widget<Switch>(find.byType(Switch).first);
    expect(singleLineSwitch.value, isTrue);
  });

  testWidgets('toggling Enable JetStream flips its switch', (tester) async {
    await tester.pumpWidget(buildDialog((_, __, ___, ____, _____, ______) {}));

    final jetStreamSwitchFinder = find.byType(Switch).at(1);
    await tester.tap(jetStreamSwitchFinder);
    await tester.pump();

    final jetStreamSwitch = tester.widget<Switch>(jetStreamSwitchFinder);
    expect(jetStreamSwitch.value, isFalse);
  });

  testWidgets('toggling Enable Key-Value Stores flips its switch',
      (tester) async {
    await tester.pumpWidget(buildDialog((_, __, ___, ____, _____, ______) {}));

    final kvSwitchFinder = find.byType(Switch).at(2);
    await tester.tap(kvSwitchFinder);
    await tester.pump();

    final kvSwitch = tester.widget<Switch>(kvSwitchFinder);
    expect(kvSwitch.value, isFalse);
  });

  testWidgets('toggling Check for Updates flips its switch', (tester) async {
    await tester.pumpWidget(buildDialog((_, __, ___, ____, _____, ______) {}));

    await tester.tap(find.byType(Switch).last);
    await tester.pump();

    final updateCheckSwitch = tester.widget<Switch>(find.byType(Switch).last);
    expect(updateCheckSwitch.value, isFalse);
  });

  testWidgets('changing the Reconnect Interval dropdown updates the value',
      (tester) async {
    await tester.pumpWidget(buildDialog((_, __, ___, ____, _____, ______) {}));

    await tester.tap(find.text('5 seconds'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('10 seconds').last);
    await tester.pumpAndSettle();

    expect(find.text('10 seconds'), findsOneWidget);
  });

  testWidgets('dragging the font size slider updates the displayed value',
      (tester) async {
    await tester.pumpWidget(buildDialog((_, __, ___, ____, _____, ______) {}));

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
                  initialSingleLine: false,
                  initialRetryInterval: 5,
                  initialJetStreamEnabled: true,
                  initialKvEnabled: true,
                  initialUpdateCheckEnabled: true,
                  onSave: (_, __, ___, ____, _____, ______) =>
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
    bool? savedSingleLine;
    int? savedRetryInterval;
    bool? savedJetStreamEnabled;
    bool? savedKvEnabled;
    bool? savedUpdateCheckEnabled;

    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (context) => SettingsDialog(
                  initialFontSize: 14,
                  initialSingleLine: false,
                  initialRetryInterval: 5,
                  initialJetStreamEnabled: true,
                  initialKvEnabled: true,
                  initialUpdateCheckEnabled: true,
                  onSave: (fontSize, singleLine, retryInterval, jetStream,
                      kv, updateCheck) {
                    savedFontSize = fontSize;
                    savedSingleLine = singleLine;
                    savedRetryInterval = retryInterval;
                    savedJetStreamEnabled = jetStream;
                    savedKvEnabled = kv;
                    savedUpdateCheckEnabled = updateCheck;
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

    await tester.tap(find.byType(Switch).first);
    await tester.pump();
    await tester.tap(find.widgetWithText(TextButton, 'Save'));
    await tester.pumpAndSettle();

    expect(savedFontSize, 14);
    expect(savedSingleLine, isTrue);
    expect(savedRetryInterval, 5);
    expect(savedJetStreamEnabled, isTrue);
    expect(savedKvEnabled, isTrue);
    expect(savedUpdateCheckEnabled, isTrue);
    expect(find.byType(SettingsDialog), findsNothing);
  });
}
