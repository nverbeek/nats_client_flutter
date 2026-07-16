import 'dart:async';
import 'dart:convert';

import 'package:dart_nats/dart_nats.dart' hide Consumer;
import 'package:flutter/material.dart';

import 'constants.dart' as constants;

/// Desired-state model for one NATS subscription the app manages.
///
/// [subject] and [queueGroup] are persisted; [colorIndex], [sid], and
/// [subscription] are not. [sid] is runtime-only: null while disconnected,
/// populated when the subscription is actually placed on the wire, and must
/// be nulled again whenever the underlying `Client` is discarded (see
/// natsConnect/natsDisconnect in main.dart) since sids are only meaningful
/// for the lifetime of one `Client` instance. [subscription] holds the
/// listener `_subscribeOne` (main.dart) attaches to this subscription's
/// message stream, so it can be cancelled before a new one is attached —
/// without that, reconnecting (or any other resubscribe path) would stack a
/// duplicate listener on top of the old one, double-inserting every message.
class SubscriptionInfo {
  String subject;
  String? queueGroup;
  final int colorIndex;
  int? sid;
  StreamSubscription<Message<dynamic>>? subscription;

  SubscriptionInfo({
    required this.subject,
    this.queueGroup,
    required this.colorIndex,
    this.sid,
  });

  Map<String, dynamic> _toJson() => {
        'subject': subject,
        if (queueGroup != null && queueGroup!.isNotEmpty)
          'queueGroup': queueGroup,
      };
}

/// JSON-encodes the persisted portion (subject + queueGroup only) of a
/// subscription list for storage under [constants.prefSubscriptions].
String encodeSubscriptionList(List<SubscriptionInfo> subscriptions) {
  return jsonEncode(subscriptions.map((s) => s._toJson()).toList());
}

/// Decodes a subscription list previously written by [encodeSubscriptionList].
/// Color indices are assigned sequentially starting at [startColorIndex] in
/// list order, since color is never persisted.
List<SubscriptionInfo> decodeSubscriptionList(
  String json, {
  int startColorIndex = 0,
}) {
  final decoded = jsonDecode(json) as List<dynamic>;
  var colorIndex = startColorIndex;
  return decoded.map((entry) {
    final map = entry as Map<String, dynamic>;
    return SubscriptionInfo(
      subject: map['subject'] as String,
      queueGroup: map['queueGroup'] as String?,
      colorIndex: colorIndex++,
    );
  }).toList();
}

/// Migrates the legacy comma-delimited `prefSubject` string into a list of
/// [SubscriptionInfo], mirroring the trim/empty-segment handling of the
/// comma-split loop this replaces. Queue groups are always null here since
/// the legacy format had no concept of one.
List<SubscriptionInfo> migrateFromLegacySubject(
  String commaDelimited, {
  int startColorIndex = 0,
}) {
  var colorIndex = startColorIndex;
  return commaDelimited
      .split(',')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .map((subject) => SubscriptionInfo(
            subject: subject,
            colorIndex: colorIndex++,
          ))
      .toList();
}

/// Resolves a [SubscriptionInfo.colorIndex] to an actual [Color] against the
/// current theme, cycling the palette if there are more subscriptions than
/// palette entries. Never cache the result — call this at render time so a
/// dark/light theme toggle mid-session stays correct.
Color resolveSubscriptionColor(int colorIndex, bool isDark) {
  final palette = isDark
      ? constants.subscriptionPaletteDark
      : constants.subscriptionPaletteLight;
  return palette[colorIndex % palette.length];
}
