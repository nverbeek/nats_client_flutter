import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nats_client_flutter/auth_manager.dart';
import 'package:nats_client_flutter/security_settings_dialog.dart';

/// Covers the parts of this dialog that don't require `file_picker`'s native
/// OS file dialog (the Browse buttons are deliberately not tested here — not
/// meaningfully testable without a much larger investment).
void main() {
  Widget buildDialog({
    VoidCallback? onClearTrustedCertificate,
    VoidCallback? onClearCertificateChain,
    VoidCallback? onClearPrivateKey,
    AuthMethod initialAuthMethod = AuthMethod.none,
    ValueChanged<AuthMethod>? onAuthMethodChanged,
    TextEditingController? usernameController,
    TextEditingController? passwordController,
    TextEditingController? tokenController,
    TextEditingController? nkeySeedController,
    TextEditingController? credsFileController,
    ValueChanged<String>? onUsernameChanged,
    ValueChanged<String>? onPasswordChanged,
    ValueChanged<String>? onTokenChanged,
    ValueChanged<String>? onNkeySeedChanged,
    VoidCallback? onCredsFilePick,
    VoidCallback? onClearCredsFile,
    bool initialRememberCredentials = false,
    ValueChanged<bool>? onRememberCredentialsChanged,
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
          onClearTrustedCertificate: onClearTrustedCertificate ?? () {},
          onClearCertificateChain: onClearCertificateChain ?? () {},
          onClearPrivateKey: onClearPrivateKey ?? () {},
          initialAuthMethod: initialAuthMethod,
          onAuthMethodChanged: onAuthMethodChanged ?? (_) {},
          usernameController: usernameController ?? TextEditingController(),
          passwordController: passwordController ?? TextEditingController(),
          tokenController: tokenController ?? TextEditingController(),
          nkeySeedController: nkeySeedController ?? TextEditingController(),
          credsFileController: credsFileController ?? TextEditingController(),
          onUsernameChanged: onUsernameChanged ?? (_) {},
          onPasswordChanged: onPasswordChanged ?? (_) {},
          onTokenChanged: onTokenChanged ?? (_) {},
          onNkeySeedChanged: onNkeySeedChanged ?? (_) {},
          onCredsFilePick: onCredsFilePick ?? () {},
          onClearCredsFile: onClearCredsFile ?? () {},
          initialRememberCredentials: initialRememberCredentials,
          onRememberCredentialsChanged: onRememberCredentialsChanged ?? (_) {},
        ),
      ),
    );
  }

  // The Authentication section can push the dialog's content taller than the
  // default 800x600 test surface, putting later fields out of the hit-test
  // area. Give those tests more room, mirroring what a real (larger) window
  // provides.
  Future<void> pumpTall(WidgetTester tester, Widget widget) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(widget);
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
    ));

    await tester.tap(clearButtonFor('Trusted Certificate'));
    await tester.pump();

    expect(cleared, isTrue);
  });

  testWidgets('clearing the Certificate Chain field calls its callback',
      (tester) async {
    var cleared = false;
    await tester.pumpWidget(buildDialog(
      onClearCertificateChain: () => cleared = true,
    ));

    await tester.tap(clearButtonFor('Certificate Chain'));
    await tester.pump();

    expect(cleared, isTrue);
  });

  testWidgets('clearing the Private Key field calls its callback',
      (tester) async {
    var cleared = false;
    await tester.pumpWidget(buildDialog(
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
                  initialAuthMethod: AuthMethod.none,
                  onAuthMethodChanged: (_) {},
                  usernameController: TextEditingController(),
                  passwordController: TextEditingController(),
                  tokenController: TextEditingController(),
                  nkeySeedController: TextEditingController(),
                  credsFileController: TextEditingController(),
                  onUsernameChanged: (_) {},
                  onPasswordChanged: (_) {},
                  onTokenChanged: (_) {},
                  onNkeySeedChanged: (_) {},
                  onCredsFilePick: () {},
                  onClearCredsFile: () {},
                  initialRememberCredentials: false,
                  onRememberCredentialsChanged: (_) {},
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
                  initialAuthMethod: AuthMethod.none,
                  onAuthMethodChanged: (_) {},
                  usernameController: TextEditingController(),
                  passwordController: TextEditingController(),
                  tokenController: TextEditingController(),
                  nkeySeedController: TextEditingController(),
                  credsFileController: TextEditingController(),
                  onUsernameChanged: (_) {},
                  onPasswordChanged: (_) {},
                  onTokenChanged: (_) {},
                  onNkeySeedChanged: (_) {},
                  onCredsFilePick: () {},
                  onClearCredsFile: () {},
                  initialRememberCredentials: false,
                  onRememberCredentialsChanged: (_) {},
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

  group('Authentication section', () {
    testWidgets('defaults to None with no method-specific fields shown',
        (tester) async {
      await pumpTall(tester, buildDialog());

      expect(find.text('None'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'Username'), findsNothing);
      expect(find.widgetWithText(TextFormField, 'Password'), findsNothing);
      expect(find.widgetWithText(TextFormField, 'Token'), findsNothing);
      expect(find.widgetWithText(TextFormField, 'NKey Seed'), findsNothing);
      expect(find.widgetWithText(TextFormField, 'Credentials File'),
          findsNothing);
      expect(find.text('Remember credentials on this device'), findsNothing);
    });

    testWidgets(
        'selecting Username & Password reveals its fields and reports changes',
        (tester) async {
      AuthMethod? reportedMethod;
      var username = '';
      var password = '';
      await pumpTall(tester, buildDialog(
        onAuthMethodChanged: (m) => reportedMethod = m,
        onUsernameChanged: (v) => username = v,
        onPasswordChanged: (v) => password = v,
      ));

      await tester.tap(find.text('None'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Username & Password').last);
      await tester.pumpAndSettle();

      expect(reportedMethod, AuthMethod.usernamePassword);
      expect(find.widgetWithText(TextFormField, 'Username'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'Password'), findsOneWidget);
      expect(find.text('Remember credentials on this device'), findsOneWidget);

      await tester.enterText(
          find.widgetWithText(TextFormField, 'Username'), 'alice');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Password'), 'hunter2');

      expect(username, 'alice');
      expect(password, 'hunter2');
    });

    testWidgets('selecting Token reveals only the token field',
        (tester) async {
      var token = '';
      await pumpTall(tester, buildDialog(
        onTokenChanged: (v) => token = v,
      ));

      await tester.tap(find.text('None'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Token').last);
      await tester.pumpAndSettle();

      expect(find.widgetWithText(TextFormField, 'Token'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'Username'), findsNothing);

      await tester.enterText(
          find.widgetWithText(TextFormField, 'Token'), 'sekret-token');
      expect(token, 'sekret-token');
    });

    testWidgets('NKey Seed field starts obscured and can be revealed',
        (tester) async {
      await pumpTall(tester, buildDialog(initialAuthMethod: AuthMethod.nkeySeed));

      TextField textField() =>
          tester.widget<TextField>(find.descendant(
              of: find.widgetWithText(TextFormField, 'NKey Seed'),
              matching: find.byType(TextField)));

      expect(textField().obscureText, isTrue);
      expect(find.byIcon(Icons.visibility), findsOneWidget);

      await tester.tap(find.byIcon(Icons.visibility));
      await tester.pump();

      expect(textField().obscureText, isFalse);
      expect(find.byIcon(Icons.visibility_off), findsOneWidget);
    });

    testWidgets('selecting Credentials File reveals the file picker row',
        (tester) async {
      var cleared = false;
      await pumpTall(tester, buildDialog(
        initialAuthMethod: AuthMethod.credentialsFile,
        credsFileController: TextEditingController(text: 'ngs-user.creds'),
        onClearCredsFile: () => cleared = true,
      ));

      // The field's hintText and labelText are both 'Credentials File', and
      // InputDecorator always builds both Text widgets (fading the hint via
      // opacity rather than omitting it), so assert loosely here and rely on
      // find.descendant (which naturally dedupes) for the actual interaction.
      expect(find.text('Credentials File'), findsWidgets);

      await tester.tap(find.descendant(
          of: find.widgetWithText(TextFormField, 'Credentials File'),
          matching: find.byIcon(Icons.clear)));
      await tester.pump();

      expect(cleared, isTrue);
    });

    testWidgets('toggling Remember credentials reports its new value',
        (tester) async {
      bool? remembered;
      await pumpTall(tester, buildDialog(
        initialAuthMethod: AuthMethod.token,
        onRememberCredentialsChanged: (v) => remembered = v,
      ));

      await tester.tap(find.text('Remember credentials on this device'));
      await tester.pump();

      expect(remembered, isTrue);
    });
  });
}
