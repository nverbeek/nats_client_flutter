import 'package:flutter/material.dart';

// connection state strings
const String connected = 'Connected';
const String disconnected = 'Disconnected';
const String connectionFailure = 'Failed to connect!';
const String tlsHandshake = 'TLS Handshake';
const String infoHandshake = 'Info Handshake';
const String reconnecting = 'Reconnecting';
const String connecting = 'Connecting';

// default connection info
const defaultScheme = 'nats://';
const defaultHost = '127.0.0.1';
const defaultPort = '4222';
const defaultSubject = '>';

// themes
const darkTheme = 'dark';
const lightTheme = 'light';

// colors
var connectedDark = Colors.green[400];
var connectedLight = Colors.green[700];
var disconnectedDark = Colors.grey[400];
var disconnectedLight = Colors.grey[800];

// per-subscription color indicator palette (Milestone 9/11). Colors are
// assigned to a SubscriptionInfo by cycling through this list and resolved
// at render time (never baked into state) so a dark/light toggle mid-session
// stays correct. Chosen to stay legible against the subtle Live Messages row
// stripe tints (see messageRowEvenColor/messageRowOddColor in main.dart).
final List<Color> subscriptionPaletteDark = [
  Colors.blue[400]!,
  Colors.orange[400]!,
  Colors.purple[300]!,
  Colors.teal[300]!,
  Colors.pink[300]!,
  Colors.indigo[300]!,
  Colors.amber[600]!,
  Colors.cyan[300]!,
];
final List<Color> subscriptionPaletteLight = [
  Colors.blue[700]!,
  Colors.orange[800]!,
  Colors.purple[700]!,
  Colors.teal[700]!,
  Colors.pink[700]!,
  Colors.indigo[700]!,
  Colors.brown[600]!,
  Colors.cyan[800]!,
];

// preference keys
const String prefScheme = "SCHEME";
const String prefHost = "HOST";
const String prefPort = "PORT";
const String prefSubject = "SUBJECT"; // legacy comma-delimited subject list; kept only as a migration source, see prefSubscriptions
const String prefSubscriptions = "SUBSCRIPTIONS"; // JSON list of {subject, queueGroup}
const String prefTheme = "THEME";
const String prefTrustedCertificate = "TRUSTED_CERTIFICATE";
const String prefTrustedCertificateName = "TRUSTED_CERTIFICATE_NAME";
const String prefCertificateChain = "CERTIFICATE_CHAIN";
const String prefCertificateChainName = "CERTIFICATE_CHAIN_NAME";
const String prefPrivateKey = "PRIVATE_KEY";
const String prefPrivateKeyName = "PRIVATE_KEY_NAME";
const String prefLastWidth = "LAST_WIDTH";
const String prefLastHeight = "LAST_HEIGHT";
const String prefLastPositionX = "LAST_POSITION_X";
const String prefLastPositionY = "LAST_POSITION_Y";
const String prefRetryInterval = "RETRY_INTERVAL";
const String prefJetStreamEnabled = "JETSTREAM_ENABLED";
const String prefKvEnabled = "KV_ENABLED";
const String prefObjectStoreEnabled = "OBJECT_STORE_ENABLED";
const String prefUpdateCheckEnabled = "UPDATE_CHECK_ENABLED";

// retry interval options (in seconds)
const int defaultRetryInterval = 10;

// JetStream defaults
const bool defaultJetStreamEnabled = true;

// Key-Value defaults
const bool defaultKvEnabled = true;

// Object Store defaults
const bool defaultObjectStoreEnabled = true;

// update check defaults
const bool defaultUpdateCheckEnabled = true;

// authentication preference keys
const String prefAuthMethod = "AUTH_METHOD";
const String prefAuthUsername = "AUTH_USERNAME";
const String prefAuthPassword = "AUTH_PASSWORD";
const String prefAuthToken = "AUTH_TOKEN";
const String prefAuthNkeySeed = "AUTH_NKEY_SEED";
const String prefAuthCredsFile = "AUTH_CREDS_FILE";
const String prefAuthCredsFileName = "AUTH_CREDS_FILE_NAME";
const String prefRememberCredentials = "REMEMBER_CREDENTIALS";

// authentication failure feedback
const String authenticationFailure =
    'Authentication failed — check your credentials';
