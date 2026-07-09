import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nats_client_flutter/settings_dialog.dart';

void main() {
  Widget buildDialog(void Function(double, bool, int, bool) onSave) {
    return MaterialApp(
      home: Scaffold(
        body: SettingsDialog(
          initialFontSize: 14,
          initialSingleLine: false,
          initialRetryInterval: 5,
          initialJetStreamEnabled: true,
          onSave: onSave,
        ),
      ),
    );
  }

  testWidgets('shows the initial values', (tester) async {
    await tester.pumpWidget(buildDialog((_, __, ___, ____) {}));

    expect(find.text('14'), findsOneWidget);
    expect(find.text('5 seconds'), findsOneWidget);

    final singleLineSwitch =
        tester.widget<Switch>(find.byType(Switch).first);
    expect(singleLineSwitch.value, isFalse);

    final jetStreamSwitch = tester.widget<Switch>(find.byType(Switch).last);
    expect(jetStreamSwitch.value, isTrue);
  });

  testWidgets('toggling Single Line Messages flips its switch', (tester) async {
    await tester.pumpWidget(buildDialog((_, __, ___, ____) {}));

    await tester.tap(find.byType(Switch).first);
    await tester.pump();

    final singleLineSwitch =
        tester.widget<Switch>(find.byType(Switch).first);
    expect(singleLineSwitch.value, isTrue);
  });

  testWidgets('toggling Enable JetStream flips its switch', (tester) async {
    await tester.pumpWidget(buildDialog((_, __, ___, ____) {}));

    await tester.tap(find.byType(Switch).last);
    await tester.pump();

    final jetStreamSwitch = tester.widget<Switch>(find.byType(Switch).last);
    expect(jetStreamSwitch.value, isFalse);
  });

  testWidgets('changing the Reconnect Interval dropdown updates the value',
      (tester) async {
    await tester.pumpWidget(buildDialog((_, __, ___, ____) {}));

    await tester.tap(find.text('5 seconds'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('10 seconds').last);
    await tester.pumpAndSettle();

    expect(find.text('10 seconds'), findsOneWidget);
  });

  testWidgets('dragging the font size slider updates the displayed value',
      (tester) async {
    await tester.pumpWidget(buildDialog((_, __, ___, ____) {}));

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
                  onSave: (_, __, ___, ____) => saveCalled = true,
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
                  onSave: (fontSize, singleLine, retryInterval, jetStream) {
                    savedFontSize = fontSize;
                    savedSingleLine = singleLine;
                    savedRetryInterval = retryInterval;
                    savedJetStreamEnabled = jetStream;
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
    expect(find.byType(SettingsDialog), findsNothing);
  });
}
