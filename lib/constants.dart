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

// preference keys
const String prefScheme = "SCHEME";
const String prefHost = "HOST";
const String prefPort = "PORT";
const String prefSubject = "SUBJECT";
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