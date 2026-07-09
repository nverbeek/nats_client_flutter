import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nats_client_flutter/security_settings_dialog.dart';

/// Covers the parts of this dialog that don't require `file_picker`'s native
/// OS file dialog (the three Browse buttons are deliberately not tested
/// here — not meaningfully testable without a much larger investment).
void main() {
  Widget buildDialog({
    required VoidCallback onClearTrustedCertificate,
    required VoidCallback onClearCertificateChain,
    required VoidCallback onClearPrivateKey,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: SecuritySettingsDialog(
          trustedCertificateController: TextEditingController(text: 'ca.pem'),
          certificateChainController: TextEditingController(text: 'chain.pem'),
          privateKeyController: TextEditingController(text: 'key.pem'),
          onTrustedCertificatePick: () {},
          onCertificateChainPick: () {},
          onPrivateKeyPick: () {},
          onClearTrustedCertificate: onClearTrustedCertificate,
          onClearCertificateChain: onClearCertificateChain,
          onClearPrivateKey: onClearPrivateKey,
        ),
      ),
    );
  }

  Finder clearButtonFor(String fieldLabel) {
    return find.descendant(
      of: find.widgetWithText(TextFormField, fieldLabel),
      matching: find.byIcon(Icons.clear),
    );
  }

  testWidgets('clearing the Trusted Certificate field calls its callback',
      (tester) async {
    var cleared = false;
    await tester.pumpWidget(buildDialog(
      onClearTrustedCertificate: () => cleared = true,
      onClearCertificateChain: () {},
      onClearPrivateKey: () {},
    ));

    await tester.tap(clearButtonFor('Trusted Certificate'));
    await tester.pump();

    expect(cleared, isTrue);
  });

  testWidgets('clearing the Certificate Chain field calls its callback',
      (tester) async {
    var cleared = false;
    await tester.pumpWidget(buildDialog(
      onClearTrustedCertificate: () {},
      onClearCertificateChain: () => cleared = true,
      onClearPrivateKey: () {},
    ));

    await tester.tap(clearButtonFor('Certificate Chain'));
    await tester.pump();

    expect(cleared, isTrue);
  });

  testWidgets('clearing the Private Key field calls its callback',
      (tester) async {
    var cleared = false;
    await tester.pumpWidget(buildDialog(
      onClearTrustedCertificate: () {},
      onClearCertificateChain: () {},
      onClearPrivateKey: () => cleared = true,
    ));

    await tester.tap(clearButtonFor('Private Key'));
    await tester.pump();

    expect(cleared, isTrue);
  });

  testWidgets('close icon pops the dialog', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (context) => SecuritySettingsDialog(
                  trustedCertificateController: TextEditingController(),
                  certificateChainController: TextEditingController(),
                  privateKeyController: TextEditingController(),
                  onTrustedCertificatePick: () {},
                  onCertificateChainPick: () {},
                  onPrivateKeyPick: () {},
                  onClearTrustedCertificate: () {},
                  onClearCertificateChain: () {},
                  onClearPrivateKey: () {},
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
    expect(find.text('Security Settings'), findsOneWidget);

    await tester.tap(find.widgetWithIcon(IconButton, Icons.close));
    await tester.pumpAndSettle();
    expect(find.text('Security Settings'), findsNothing);
  });

  testWidgets('close button pops the dialog', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (context) => SecuritySettingsDialog(
                  trustedCertificateController: TextEditingController(),
                  certificateChainController: TextEditingController(),
                  privateKeyController: TextEditingController(),
                  onTrustedCertificatePick: () {},
                  onCertificateChainPick: () {},
                  onPrivateKeyPick: () {},
                  onClearTrustedCertificate: () {},
                  onClearCertificateChain: () {},
                  onClearPrivateKey: () {},
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

    await tester.tap(find.widgetWithText(TextButton, 'Close'));
    await tester.pumpAndSettle();
    expect(find.text('Security Settings'), findsNothing);
  });
}
