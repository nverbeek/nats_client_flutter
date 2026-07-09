import 'package:dart_nats/dart_nats.dart' hide Consumer;

/// Authentication method selectable in the Security Settings dialog.
enum AuthMethod {
  none,
  usernamePassword,
  token,
  nkeySeed,
  credentialsFile,
}

/// Builds the [ConnectOption] carrying username/password, token, or bare
/// NKey credentials for [method]. Returns null when [method] doesn't need a
/// [ConnectOption] (a `.creds` file's JWT is applied directly on the
/// [Client] instead, via `loadCredentials()`) or when the relevant fields
/// are empty.
///
/// For [AuthMethod.nkeySeed], setting `Client.seed` alone is **not**
/// sufficient — it only arms the client to *sign* the server's nonce
/// challenge (see `_sign()` in `dart_nats`'s `client.dart`). The CONNECT
/// message's `nkey` field (the public key) must also be set explicitly, or
/// the server rejects the connection with `authentication error - Nkey ""`
/// (confirmed against a real `nats-server` configured with
/// `authorization { users = [{ nkey: "..." }] }`).
ConnectOption? buildAuthConnectOption({
  required AuthMethod method,
  String? username,
  String? password,
  String? token,
  String? nkeySeed,
}) {
  switch (method) {
    case AuthMethod.usernamePassword:
      if ((username == null || username.isEmpty) &&
          (password == null || password.isEmpty)) {
        return null;
      }
      return ConnectOption(user: username, pass: password);
    case AuthMethod.token:
      if (token == null || token.isEmpty) {
        return null;
      }
      return ConnectOption(authToken: token);
    case AuthMethod.nkeySeed:
      if (nkeySeed == null || nkeySeed.isEmpty) {
        return null;
      }
      return ConnectOption(nkey: Nkeys.fromSeed(nkeySeed).publicKey());
    case AuthMethod.none:
    case AuthMethod.credentialsFile:
      return null;
  }
}

/// Returns true if [error] represents an authentication/authorization
/// failure reported by the NATS server (e.g. a bad password, invalid NKey,
/// or expired/invalid `.creds` JWT), as opposed to a generic connectivity
/// failure. Mirrors the phrase matching `dart_nats` itself uses to decide
/// whether to stop retrying (see its `-ERR` handler in `client.dart`).
bool isAuthenticationError(Object error) {
  if (error is! NatsException) {
    return false;
  }
  final message = error.message?.toLowerCase() ?? '';
  return message.contains('authorization violation') ||
      message.contains('authentication');
}
