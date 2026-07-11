import 'dart:async';

import 'package:dart_nats/dart_nats.dart' hide Consumer;
import 'package:flutter_test/flutter_test.dart';
import 'package:nats_client_flutter/jetstream_manager.dart';
import 'package:nats_client_flutter/object_store_manager.dart';

void main() {
  group('bucketNameFromObjectStream', () {
    test('strips the OBJ_ prefix', () {
      expect(bucketNameFromObjectStream('OBJ_documents'), 'documents');
    });

    test('leaves a name without the prefix unchanged', () {
      expect(bucketNameFromObjectStream('orders'), 'orders');
    });
  });

  group('describeObjectStoreError', () {
    test('recognizes a digest verification failure', () {
      final message = describeObjectStoreError(
          NatsException('SHA-256 digest verification failed.'));
      expect(message,
          'Download failed integrity verification (digest mismatch) — try again.');
    });

    test('falls back to describeJetStreamError for other NatsExceptions', () {
      final message =
          describeObjectStoreError(NatsException('stream not found'));
      expect(message,
          describeJetStreamError(NatsException('stream not found')));
    });

    test('gives a friendly message for timeouts', () {
      final message = describeObjectStoreError(TimeoutException('timed out'));
      expect(message, 'Timed out waiting for a response from the server.');
    });

    test('falls back to a generic message for unexpected errors', () {
      final message = describeObjectStoreError(Exception('boom'));
      expect(message, contains('JetStream is unavailable'));
    });
  });
}
