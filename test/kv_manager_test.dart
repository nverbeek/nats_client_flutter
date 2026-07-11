import 'dart:async';

import 'package:dart_nats/dart_nats.dart' hide Consumer;
import 'package:flutter_test/flutter_test.dart';
import 'package:nats_client_flutter/jetstream_manager.dart';
import 'package:nats_client_flutter/kv_manager.dart';

void main() {
  group('bucketNameFromStream', () {
    test('strips the KV_ prefix', () {
      expect(bucketNameFromStream('KV_app-config'), 'app-config');
    });

    test('leaves a name without the prefix unchanged', () {
      expect(bucketNameFromStream('orders'), 'orders');
    });
  });

  group('describeKvError', () {
    test('recognizes a stale-revision (wrong last sequence) conflict', () {
      final message = describeKvError(
          NatsException('wrong last sequence: 3'));
      expect(message,
          'This key changed since it was loaded — reload and try again.');
    });

    test('recognizes a key-already-exists conflict from create()', () {
      final message = describeKvError(NatsException('key already exists'));
      expect(message, 'That key already exists.');
    });

    test('falls back to describeJetStreamError for other NatsExceptions', () {
      final message = describeKvError(NatsException('stream not found'));
      expect(message, describeJetStreamError(NatsException('stream not found')));
    });

    test('gives a friendly message for timeouts', () {
      final message = describeKvError(TimeoutException('timed out'));
      expect(message, 'Timed out waiting for a response from the server.');
    });

    test('falls back to a generic message for unexpected errors', () {
      final message = describeKvError(Exception('boom'));
      expect(message, contains('JetStream is unavailable'));
    });
  });
}
