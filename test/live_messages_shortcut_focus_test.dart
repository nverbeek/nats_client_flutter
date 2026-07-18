import 'dart:convert';

import 'package:dart_nats/dart_nats.dart' hide Consumer;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loader_overlay/loader_overlay.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nats_client_flutter/main.dart';
import 'package:nats_client_flutter/message_detail_dialog.dart';
import 'package:nats_client_flutter/subscription_info.dart';

/// Regression tests for two Live Messages interaction bugs:
///
/// 1. The single-key message shortcuts (D/R/E, Escape, Ctrl+C) are handled by
///    an outer `Focus(onKeyEvent: ...)` that receives every key event bubbling
///    up from focused descendants — including the Filter/Find text fields.
///    With a row selected, typing a letter like 'd' into Filter used to open
///    the Detail dialog (and 'r' would *re-publish the message*) instead of
///    going into the field.
///
/// 2. The 300ms single/double-tap disambiguation timer used to capture the
///    tapped row's *index*; messages arriving during that window prepend to
///    the list and shift every index, so the selection landed on whichever
///    row slid into the tapped position.
Widget buildApp() {
  return ChangeNotifierProvider<ThemeModel>(
    create: (_) => ThemeModel('dark'),
    child: MaterialApp(
      home: LoaderOverlay(
        child: MyHomePage(
          '1.0.0',
          'NATS Client',
          'nats://',
          '127.0.0.1',
          '4222',
          [SubscriptionInfo(subject: '>', colorIndex: 0)],
          const [],
        ),
      ),
    ),
  );
}

Message<dynamic> makeMessage(String subject, String payload, Client client,
    {int sid = 1}) {
  return Message<dynamic>(
      subject, sid, Uint8List.fromList(utf8.encode(payload)), client);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  // The full home page (connection toolbar + list + bottom toolbar) is laid
  // out for a desktop window, not the default 800x600 test surface.
  Future<void> pumpAppAtDesktopSize(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();
  }

  testWidgets(
      'typing a shortcut letter in the Filter field with a row selected does '
      'NOT trigger the message shortcut', (tester) async {
    await pumpAppAtDesktopSize(tester);

    final state = tester.state(find.byType(MyHomePage)) as dynamic;
    final client = Client();
    state.handleIncomingMessage(makeMessage('foo.bar', 'hello world', client));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump();

    expect(find.text('hello world'), findsOneWidget);

    // Select the row (single tap, wait out the double-tap timer).
    await tester.tap(find.text('hello world'));
    await tester.pump(const Duration(milliseconds: 350));
    expect(state.selectedIndex, 0);

    // Focus the Filter field, as a user about to type a filter would.
    final filterField = find.ancestor(
        of: find.text('Filter').first, matching: find.byType(TextFormField));
    await tester.tap(filterField.first);
    await tester.pump();

    // Type 'd' — this belongs to the text field, and must not open the
    // Detail dialog for the still-selected row.
    await tester.sendKeyEvent(LogicalKeyboardKey.keyD);
    await tester.pumpAndSettle();

    expect(find.byType(MessageDetailDialog), findsNothing,
        reason: 'Typing "d" in the Filter field must not open the Detail '
            'dialog for the selected row');
  });

  testWidgets(
      'the D shortcut still opens Detail when the message list itself has '
      'focus', (tester) async {
    await pumpAppAtDesktopSize(tester);

    final state = tester.state(find.byType(MyHomePage)) as dynamic;
    final client = Client();
    state.handleIncomingMessage(makeMessage('foo.bar', 'hello world', client));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump();

    // Tapping the row selects it and reclaims keyboard focus for the list.
    await tester.tap(find.text('hello world'));
    await tester.pump(const Duration(milliseconds: 350));
    expect(state.selectedIndex, 0);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyD);
    await tester.pumpAndSettle();

    expect(find.byType(MessageDetailDialog), findsOneWidget,
        reason: 'With the list focused, D should open the Detail dialog');
  });

  testWidgets(
      'a message arriving during the 300ms single-tap window does not shift '
      'the selection off the tapped row', (tester) async {
    await pumpAppAtDesktopSize(tester);

    final state = tester.state(find.byType(MyHomePage)) as dynamic;
    final client = Client();
    state.handleIncomingMessage(makeMessage('foo.a', 'message A', client));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump();

    // Tap message A (index 0), then a new message arrives before the
    // single-tap timer fires — prepending shifts A to index 1.
    await tester.tap(find.text('message A'));
    await tester.pump(const Duration(milliseconds: 100));
    state.handleIncomingMessage(makeMessage('foo.b', 'message B', client));
    await tester.pump(const Duration(milliseconds: 50));
    // Let the tap timer expire.
    await tester.pump(const Duration(milliseconds: 300));

    final selectedIndex = state.selectedIndex as int;
    expect(selectedIndex, isNot(-1));
    final selectedText =
        utf8.decode((state.filteredItems[selectedIndex] as Message).byte);
    expect(selectedText, 'message A',
        reason: 'Selection should stay on the message the user tapped even '
            'if new messages arrive during the tap-disambiguation window');
  });
}
