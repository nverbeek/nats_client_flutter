import 'dart:convert';
import 'dart:io';

import 'package:dart_nats/dart_nats.dart';

/// One NATS server a context points at.
class ContextServer {
  const ContextServer(this.host, this.port, {this.tls = false});

  final String host;
  final int port;

  /// `tls://` in the context's URL: TLS even if the server doesn't ask.
  final bool tls;

  /// Never includes credentials, even when the context's URL had some.
  @override
  String toString() =>
      '${tls ? 'tls' : 'nats'}://${host.contains(':') ? '[$host]' : host}:$port';
}

/// Why a context's credentials can't be used, in words safe to show the
/// browser: file names but no paths, and never a file's contents.
class ContextError implements Exception {
  ContextError(this.message, {this.detail});

  final String message;

  /// More for the log only, such as a full path or an OS error.
  final String? detail;

  @override
  String toString() => message;
}

/// A context's credentials as they are right now.
class ContextAuth {
  const ContextAuth({
    this.user = '',
    this.password = '',
    this.token = '',
    this.jwt = '',
    this.seed = '',
    this.nkeySeed = '',
  });

  final String user;
  final String password;
  final String token;

  /// User JWT and its signing seed, from a `.creds` file or user_jwt/user_seed.
  final String jwt;
  final String seed;

  /// An NKey user's seed.
  final String nkeySeed;

  bool get isEmpty =>
      jwt.isEmpty && nkeySeed.isEmpty && user.isEmpty && token.isEmpty;

  /// Applies these credentials to a client's CONNECT options, replacing
  /// whatever auth the browser sent. [nonce] is from the server's INFO,
  /// signed for JWT and NKey auth the same way dart_nats signs it.
  Map<String, dynamic> apply(Map<String, dynamic> connect, String? nonce) {
    final result = Map<String, dynamic>.of(connect)
      ..remove('user')
      ..remove('pass')
      ..remove('auth_token')
      ..remove('jwt')
      ..remove('nkey')
      ..remove('sig');
    String sign(String seed) =>
        base64.encode(Nkeys.fromSeed(seed).sign(utf8.encode(nonce ?? '')));
    if (jwt.isNotEmpty) {
      result['jwt'] = jwt;
      result['sig'] = sign(seed);
    } else if (nkeySeed.isNotEmpty) {
      result['nkey'] = Nkeys.fromSeed(nkeySeed).publicKey();
      result['sig'] = sign(nkeySeed);
    } else if (user.isNotEmpty) {
      result['user'] = user;
      result['pass'] = password;
    } else if (token.isNotEmpty) {
      result['auth_token'] = token;
    }
    return result;
  }
}

/// A NATS CLI context (the JSON files `nats context save` writes, under
/// `~/.config/nats/context/`), as far as the relay supports one. Field names
/// match the CLI's own (jsm.go `natscontext`).
///
/// Secrets stay here: the browser only ever sees [toPublicJson].
class NatsContext {
  NatsContext({
    required this.name,
    this.description = '',
    required this.servers,
    this.user = '',
    this.password = '',
    this.token = '',
    this.jwt = '',
    this.seed = '',
    this.nkeySeed = '',
    this.files = const {},
    this.cert,
    this.key,
    this.ca,
    this.tlsFirst = false,
    this.error,
  });

  final String name;
  final String description;
  final List<ContextServer> servers;

  /// Credentials given as values (or `env://` references, already resolved).
  final String user;
  final String password;
  final String token;
  final String jwt;
  final String seed;
  final String nkeySeed;

  /// Credentials kept in files, by context field: `creds`, `nkey`, or
  /// `password`, `token`, `user_jwt` and `user_seed` given as `file://`.
  /// Read again for every connection, so a rotated file (such as a
  /// Kubernetes Secret) takes effect without a restart. A file wins over
  /// the matching value.
  final Map<String, String> files;

  /// TLS files, already resolved to paths that exist.
  final String? cert;
  final String? key;
  final String? ca;
  final bool tlsFirst;

  /// Why this context can't be used (a missing file, a bad URL), or null.
  /// Shown to the browser, so it names files but not their paths.
  final String? error;

  bool get usesTls => cert != null || key != null || ca != null;

  /// The SecurityContext for TLS to this context's servers: system roots,
  /// plus its own CA and client certificate when it names them.
  SecurityContext securityContext() {
    final context = SecurityContext(withTrustedRoots: true);
    if (ca != null) context.setTrustedCertificates(ca!);
    if (cert != null) context.useCertificateChain(cert!);
    if (key != null) context.usePrivateKey(key!);
    return context;
  }

  /// This context's credentials, reading any [files] afresh. Throws a
  /// [ContextError] when a file can't be read or the result can't be used.
  ContextAuth resolveAuth() {
    String read(String field) {
      final path = files[field]!;
      try {
        return File(path).readAsStringSync();
      } on FileSystemException catch (e) {
        throw ContextError(
            _cannotRead('its $field file "${_baseName(path)}"', e),
            detail: '$path: ${e.osError?.message ?? e.message}');
      }
    }

    var jwt = this.jwt;
    var seed = this.seed;
    if (files.containsKey('creds')) {
      try {
        final creds = Credentials.parse(read('creds'));
        jwt = creds.jwt;
        seed = creds.seed;
      } on ContextError {
        rethrow;
      } catch (_) {
        throw ContextError('its creds file "${_baseName(files['creds']!)}" '
            'is not a valid .creds file');
      }
    }
    if (files.containsKey('user_jwt')) jwt = read('user_jwt').trim();
    if (files.containsKey('user_seed')) seed = read('user_seed').trim();
    final nkeySeed =
        files.containsKey('nkey') ? read('nkey').trim() : this.nkeySeed;
    final password =
        files.containsKey('password') ? read('password').trim() : this.password;
    final token =
        files.containsKey('token') ? read('token').trim() : this.token;

    for (final s in [seed, nkeySeed]) {
      if (s.isEmpty) continue;
      try {
        Nkeys.fromSeed(s);
      } catch (_) {
        throw ContextError('its user seed is not a valid NKey seed');
      }
    }
    if (jwt.isNotEmpty && seed.isEmpty) {
      throw ContextError('it has a user JWT but no seed to sign with');
    }
    return ContextAuth(
      user: user,
      password: password,
      token: token,
      jwt: jwt,
      seed: seed,
      nkeySeed: nkeySeed,
    );
  }

  /// [resolveAuth], applied to a client's CONNECT options.
  Map<String, dynamic> applyAuth(Map<String, dynamic> connect, String? nonce) =>
      resolveAuth().apply(connect, nonce);

  /// What the browser may know: no credentials, no file paths.
  Map<String, dynamic> toPublicJson({required bool selected}) => {
        'name': name,
        'description': description,
        'server': servers.isEmpty ? '' : servers.first.toString(),
        'selected': selected,
        if (error != null) 'error': error,
      };
}

/// Everything the relay knows about contexts, loaded once at startup.
class ContextSet {
  ContextSet(this.contexts, {this.selected, this.warnings = const []});

  static final empty = ContextSet(const []);

  final List<NatsContext> contexts;

  /// The context the app should preselect, by name.
  final String? selected;

  /// Things worth a startup log line: unsupported fields, unreadable files.
  /// They may name full paths, but never a file's contents.
  final List<String> warnings;

  bool get isEmpty => contexts.isEmpty;

  NatsContext? byName(String name) {
    for (final c in contexts) {
      if (c.name == name) return c;
    }
    return null;
  }

  List<Map<String, dynamic>> toPublicJson() => [
        for (final c in contexts) c.toPublicJson(selected: c.name == selected),
      ];

  /// Loads every `*.json` context in [dir] (when it exists), plus a
  /// `default` context from the nats CLI's own environment variables when
  /// `NATS_URL` is set. [env] also supplies `HOME` for `~`, `env://`
  /// references, and `NATS_CONTEXT`, the CLI's "selected context".
  static ContextSet load({required String dir, Map<String, String>? env}) {
    env ??= Platform.environment;
    final warnings = <String>[];
    final contexts = <NatsContext>[];
    final directory = Directory(dir);
    var files = <File>[];
    try {
      if (directory.existsSync()) {
        files = directory
            .listSync()
            .whereType<File>()
            .where((f) => f.path.toLowerCase().endsWith('.json'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));
      }
    } on FileSystemException catch (e) {
      warnings.add(_cannotRead('the contexts directory $dir', e));
    }
    for (final file in files) {
      final name = _baseName(file.path).replaceFirst(RegExp(r'\.json$'), '');
      Map<String, dynamic> json;
      try {
        final decoded = jsonDecode(file.readAsStringSync());
        if (decoded is! Map<String, dynamic>) {
          throw const FormatException('not a JSON object');
        }
        json = decoded;
      } on FormatException catch (e) {
        // Never the exception itself: its text quotes the line it failed
        // on, which may hold a password or token.
        warnings.add('context "$name": ${file.path} is not valid JSON '
            '(${_position(e)})');
        continue;
      } on FileSystemException catch (e) {
        warnings.add('context "$name": ${_cannotRead(file.path, e)}');
        continue;
      }
      contexts.add(_fromFields(name, json, dir, env, warnings));
    }

    final url = env['NATS_URL']?.trim() ?? '';
    if (url.isNotEmpty) {
      if (contexts.any((c) => c.name == 'default')) {
        warnings.add('NATS_URL is set, but a context file is already named '
            '"default"; ignoring the environment variables');
      } else {
        contexts.add(_fromFields(
            'default',
            {
              'description': 'From environment variables',
              'url': url,
              'user': env['NATS_USER'],
              'password': env['NATS_PASSWORD'],
              'token': env['NATS_TOKEN'],
              'creds': env['NATS_CREDS'],
              'nkey': env['NATS_NKEY'],
              'user_jwt': env['NATS_JWT'],
              'user_seed': env['NATS_SEED'],
              'cert': env['NATS_CERT'],
              'key': env['NATS_KEY'],
              'ca': env['NATS_CA'],
            },
            dir,
            env,
            warnings));
      }
    }

    String? selected;
    for (final (source, name) in [
      ('NATS_CONTEXT', env['NATS_CONTEXT']?.trim()),
      ('context.txt', _readSelected(dir, warnings)),
    ]) {
      if (name == null || name.isEmpty) continue;
      if (contexts.any((c) => c.name == name)) {
        selected = name;
        break;
      }
      warnings.add('$source selects context "$name", which was not found');
    }
    if (selected == null && contexts.length == 1) {
      selected = contexts.single.name;
    }
    return ContextSet(contexts, selected: selected, warnings: warnings);
  }

  /// The CLI keeps the selected context's name in `context.txt`, next to
  /// the `context` directory; also accept it inside the mounted directory.
  static String? _readSelected(String dir, List<String> warnings) {
    for (final path in ['$dir/context.txt', '$dir/../context.txt']) {
      final file = File(path);
      try {
        if (file.existsSync()) {
          final name = file.readAsStringSync().trim();
          if (name.isNotEmpty) return name;
        }
      } on FileSystemException catch (e) {
        warnings.add(_cannotRead(path, e));
      }
    }
    return null;
  }

  static const _unsupported = {
    'nsc': 'nsc lookups',
    'socks_proxy': 'SOCKS proxies',
    'jetstream_domain': 'JetStream domains',
    'jetstream_api_prefix': 'JetStream API prefixes',
    'jetstream_event_prefix': 'JetStream event prefixes',
    'inbox_prefix': 'custom inbox prefixes',
    'windows_cert_store': 'the Windows certificate store',
  };

  /// A `scheme://` the CLI resolves a value through (jsm.go
  /// `resolveLiteral`), or `data:`.
  static final _reference = RegExp(r'^([a-zA-Z][a-zA-Z0-9+.-]*)://|^data:');

  static NatsContext _fromFields(String name, Map<String, dynamic> json,
      String dir, Map<String, String> env, List<String> warnings) {
    String field(String key) => (json[key] as Object?)?.toString().trim() ?? '';
    for (final entry in _unsupported.entries) {
      if (field(entry.key).isNotEmpty) {
        warnings.add('context "$name": ${entry.value} are not supported, '
            'ignoring "${entry.key}"');
      }
    }

    // problems are shown to the browser; details only go to the log.
    final problems = <String>[];
    final details = <String>[];
    final servers = <ContextServer>[];
    String? userInfo;
    for (final raw in field('url').split(',')) {
      final url = raw.trim();
      if (url.isEmpty) continue;
      final uri = Uri.tryParse(url.contains('://') ? url : 'nats://$url');
      // Credentials in a URL are never echoed back.
      final shown = url.replaceFirstMapped(
          RegExp(r'^([^/]*//)?[^/@]*@'), (m) => '${m[1] ?? ''}***@');
      if (uri == null || uri.host.isEmpty) {
        problems.add('"$shown" is not a server URL');
      } else if (uri.scheme != 'nats' && uri.scheme != 'tls') {
        problems.add('"$shown" is not a nats:// or tls:// URL');
      } else {
        servers.add(ContextServer(uri.host, uri.hasPort ? uri.port : 4222,
            tls: uri.scheme == 'tls'));
        if (uri.userInfo.isNotEmpty) userInfo ??= uri.userInfo;
      }
    }
    if (servers.isEmpty && problems.isEmpty) problems.add('it has no url');

    // A file the context names: as written (with ~ expanded), else the same
    // file name next to the context, for contexts made on another machine.
    String? file(String key, String value) {
      if (value.startsWith('file://')) value = value.substring(7);
      if (value.isEmpty) return null;
      final home = env['HOME'] ?? '';
      final expanded = value.startsWith('~/') && home.isNotEmpty
          ? '$home${value.substring(1)}'
          : value;
      final beside = '$dir/${_baseName(value)}';
      final found = [expanded, beside].where((p) => File(p).existsSync());
      if (found.isEmpty) {
        problems.add('its $key file "${_baseName(value)}" was not found (mount '
            'it at the path the context names, or put it next to the context)');
        details.add('$key: $value');
        return null;
      }
      final path = found.first;
      try {
        File(path).openSync().closeSync();
      } on FileSystemException catch (e) {
        problems.add(_cannotRead('its $key file "${_baseName(value)}"', e));
        details.add('$key: $path: ${e.osError?.message ?? e.message}');
        return null;
      }
      return path;
    }

    // Values the CLI resolves through a reference: env:// and file:// are
    // supported, others (op://, nsc://, data:) aren't.
    final values = <String, String>{};
    final files = <String, String>{};
    for (final key in ['password', 'token', 'user_jwt', 'user_seed']) {
      final value = field(key);
      final reference = _reference.firstMatch(value);
      if (value.isEmpty) continue;
      if (value.startsWith('env://')) {
        final variable = value.substring(6);
        final resolved = env[variable] ?? '';
        if (resolved.isEmpty) {
          problems.add('its $key names the environment variable $variable, '
              'which is not set');
        } else {
          values[key] = resolved.trim();
        }
      } else if (value.startsWith('file://')) {
        final path = file(key, value);
        if (path != null) files[key] = path;
      } else if (reference != null) {
        problems.add('its $key uses ${reference.group(1) ?? 'data'}: '
            'references, which are not supported');
      } else {
        values[key] = value;
      }
    }
    for (final key in ['creds', 'nkey']) {
      final value = field(key);
      if (value.isEmpty) continue;
      // The CLI's nkey names a seed file; accept the seed itself as well.
      if (key == 'nkey' && value.startsWith('SU')) {
        values[key] = value;
        continue;
      }
      final reference = _reference.firstMatch(value);
      if (reference != null && !value.startsWith('file://')) {
        problems.add('its $key uses ${reference.group(1) ?? 'data'}: '
            'references, which are not supported');
        continue;
      }
      final path = file(key, value);
      if (path != null) files[key] = path;
    }

    var user = field('user');
    var password = values['password'] ?? '';
    var token = values['token'] ?? '';
    // Credentials in the URL, as nats.go reads them, when the context has
    // none of its own: user:password@ or token@.
    final hasOwn = user.isNotEmpty ||
        ['password', 'token', 'user_jwt', 'user_seed', 'creds', 'nkey']
            .any((k) => field(k).isNotEmpty);
    if (userInfo != null && !hasOwn) {
      String decode(String s) {
        try {
          return Uri.decodeComponent(s);
        } on ArgumentError {
          return s;
        }
      }

      final colon = userInfo.indexOf(':');
      if (colon < 0) {
        token = decode(userInfo);
      } else {
        user = decode(userInfo.substring(0, colon));
        password = decode(userInfo.substring(colon + 1));
      }
    }

    final cert = field('cert').isEmpty ? null : file('cert', field('cert'));
    final key = field('key').isEmpty ? null : file('key', field('key'));
    final ca = field('ca').isEmpty ? null : file('ca', field('ca'));
    if (field('cert').isEmpty != field('key').isEmpty) {
      problems.add('cert and key must be given together');
    }

    NatsContext build(String? error) => NatsContext(
          name: name,
          description: field('description'),
          servers: servers,
          user: user,
          password: password,
          token: token,
          jwt: values['user_jwt'] ?? '',
          seed: values['user_seed'] ?? '',
          nkeySeed: values['nkey'] ?? '',
          files: files,
          cert: cert,
          key: key,
          ca: ca,
          tlsFirst: json['tls_first'] == true,
          error: error,
        );

    // Everything named was found: check it can actually be used now, rather
    // than on the first connection.
    if (problems.isEmpty) {
      final candidate = build(null);
      try {
        candidate.resolveAuth();
      } on ContextError catch (e) {
        problems.add(e.message);
        if (e.detail != null) details.add(e.detail!);
      }
      if (candidate.usesTls) {
        try {
          candidate.securityContext();
        } catch (e) {
          problems.add('its TLS files cannot be loaded (not PEM, or an '
              'encrypted key)');
          details.add('$e');
        }
      }
    }

    final context = build(problems.isEmpty ? null : problems.join('; '));
    if (context.error != null) {
      warnings.add('context "$name" is unusable: ${context.error}'
          '${details.isEmpty ? '' : ' [${details.join('; ')}]'}');
    }
    return context;
  }
}

/// Why a file can't be read, safe for the browser: [what] names it, and a
/// permission problem gets a hint, since the image doesn't run as root.
String _cannotRead(String what, FileSystemException e) {
  final message = (e.osError?.message ?? '').toLowerCase();
  final denied = e.osError?.errorCode == 13 ||
      message.contains('permission denied') ||
      message.contains('access is denied');
  return denied
      ? 'cannot read $what: permission denied (the container does not run '
          'as root; see the README)'
      : 'cannot read $what';
}

/// Where a JSON parse failed, without quoting any of the text.
String _position(FormatException e) {
  final source = e.source;
  final offset = e.offset;
  if (source is! String || offset == null) return e.message;
  final before = source.substring(0, offset.clamp(0, source.length));
  final line = '\n'.allMatches(before).length + 1;
  final column = before.length - before.lastIndexOf('\n');
  return '${e.message} at line $line, column $column';
}

/// The last part of [path], or [path] itself when it has none (`/`).
String _baseName(String path) =>
    path.split(RegExp(r'[/\\]')).where((p) => p.isNotEmpty).lastOrNull ?? path;
