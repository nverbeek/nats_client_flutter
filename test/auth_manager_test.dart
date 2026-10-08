import 'dart:io' show HandshakeException;

import 'package:dart_nats/dart_nats.dart' hide Consumer;
import 'package:flutter_test/flutter_test.dart';
import 'package:nats_client_flutter/auth_manager.dart';

void main() {
  group('buildAuthConnectOption', () {
    test('returns null for AuthMethod.none', () {
      expect(
        buildAuthConnectOption(
            method: AuthMethod.none, username: 'a', password: 'b'),
        isNull,
      );
    });

    test('builds a user/pass ConnectOption for AuthMethod.usernamePassword',
        () {
      final option = buildAuthConnectOption(
        method: AuthMethod.usernamePassword,
        username: 'alice',
        password: 'hunter2',
      );
      expect(option, isNotNull);
      expect(option!.user, 'alice');
      expect(option.pass, 'hunter2');
    });

    test('returns null for username/password when both fields are empty', () {
      expect(
        buildAuthConnectOption(
            method: AuthMethod.usernamePassword, username: '', password: ''),
        isNull,
      );
      expect(
        buildAuthConnectOption(method: AuthMethod.usernamePassword),
        isNull,
      );
    });

    test('builds a token ConnectOption for AuthMethod.token', () {
      final option =
          buildAuthConnectOption(method: AuthMethod.token, token: 'abc123');
      expect(option, isNotNull);
      expect(option!.authToken, 'abc123');
    });

    test('returns null for an empty token', () {
      expect(
        buildAuthConnectOption(method: AuthMethod.token, token: ''),
        isNull,
      );
      expect(
        buildAuthConnectOption(method: AuthMethod.token),
        isNull,
      );
    });

    test('builds an nkey ConnectOption carrying the derived public key', () {
      // A throwaway seed generated for this test — see Nkeys.createUser().
      const seed = 'SUAOULG3VYH4VIZBYSVY6UXZ32DXVWNRAYGQ2QN3W5HGG6B5FCT2HUYNCY';
      final option =
          buildAuthConnectOption(method: AuthMethod.nkeySeed, nkeySeed: seed);
      expect(option, isNotNull);
      // Setting Client.seed alone only arms nonce-signing — the CONNECT
      // message's `nkey` (public key) field must be set explicitly too, or
      // a real nats-server rejects with `authentication error - Nkey ""`.
      expect(option!.nkey, Nkeys.fromSeed(seed).publicKey());
    });

    test('returns null for an empty NKey seed', () {
      expect(
        buildAuthConnectOption(method: AuthMethod.nkeySeed),
        isNull,
      );
      expect(
        buildAuthConnectOption(method: AuthMethod.nkeySeed, nkeySeed: ''),
        isNull,
      );
    });

    test('returns null for the credentials file method', () {
      expect(
        buildAuthConnectOption(method: AuthMethod.credentialsFile),
        isNull,
      );
    });
  });

  group('isAuthenticationError', () {
    // Built the way the client itself builds them from a server `-ERR` line.
    test('recognizes an authorization violation', () {
      expect(
        isAuthenticationError(
            NatsException.fromServerError("'Authorization Violation'")),
        isTrue,
      );
    });

    test('recognizes an expired authentication', () {
      expect(
        isAuthenticationError(
            NatsException.fromServerError("'Authentication Expired'")),
        isTrue,
      );
    });

    test('recognizes a generic authentication error', () {
      expect(
        isAuthenticationError(NatsException.fromServerError(
            "'authentication error - Nkey \"\"'")),
        isTrue,
      );
    });

    test('returns false for an unrelated server error', () {
      expect(
        isAuthenticationError(
            NatsException.fromServerError("'Maximum Connections Exceeded'")),
        isFalse,
      );
    });

    test('returns false for a plain NatsException', () {
      expect(isAuthenticationError(NatsException('Invalid Subject')), isFalse);
      expect(isAuthenticationError(NatsException(null)), isFalse);
    });

    test('returns false for a non-NatsException error', () {
      expect(
          isAuthenticationError(Exception('Authorization Violation')), isFalse);
    });
  });

  group('isTlsHandshakeError', () {
    test('recognizes the client-wrapped TLS handshake failure', () {
      expect(
        isTlsHandshakeError(NatsException(
            'TLS handshake failed: HandshakeException: CERTIFICATE_VERIFY_FAILED')),
        isTrue,
      );
    });

    test('recognizes a raw TlsException', () {
      expect(isTlsHandshakeError(const HandshakeException('bad cert')), isTrue);
    });

    test('returns false for other errors', () {
      expect(isTlsHandshakeError(NatsException('Connection closed')), isFalse);
      expect(isTlsHandshakeError(NatsException(null)), isFalse);
      expect(isTlsHandshakeError(Exception('TLS handshake failed')), isFalse);
    });
  });
}
