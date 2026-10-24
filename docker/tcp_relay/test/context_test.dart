import 'dart:convert';
import 'dart:io';

import 'package:dart_nats/dart_nats.dart';
import 'package:nats_tcp_relay/context.dart';
import 'package:test/test.dart';

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('relay_contexts');
  });

  tearDown(() => dir.delete(recursive: true));

  void writeContext(String name, Map<String, dynamic> json) =>
      File('${dir.path}/$name.json').writeAsStringSync(jsonEncode(json));

  ContextSet load([Map<String, String> env = const {}]) =>
      ContextSet.load(dir: dir.path, env: env);

  test('loads every context file, named by file name', () {
    writeContext('prod', {
      'description': 'Production',
      'url': 'nats://nats-a:4222, tls://nats-b',
      'user': 'alice',
      'password': 's3cret',
    });
    writeContext('dev', {'url': 'localhost:4333', 'token': 't0ken'});
    File('${dir.path}/notes.txt').writeAsStringSync('not a context');

    final set = load();
    expect(set.contexts.map((c) => c.name), ['dev', 'prod']);
    final prod = set.byName('prod')!;
    expect(prod.description, 'Production');
    expect(prod.servers.map((s) => '$s'),
        ['nats://nats-a:4222', 'tls://nats-b:4222']);
    expect(prod.user, 'alice');
    expect(prod.password, 's3cret');
    expect(prod.error, isNull);
    expect(set.byName('dev')!.servers.single.port, 4333);
  });

  test('builds a default context from the nats CLI environment variables', () {
    final set = load({
      'NATS_URL': 'nats://env-host:4222',
      'NATS_USER': 'bob',
      'NATS_PASSWORD': 'pw',
    });
    final ctx = set.byName('default')!;
    expect(ctx.servers.single.host, 'env-host');
    expect(ctx.user, 'bob');
    expect(set.selected, 'default', reason: 'the only context');
  });

  test('reads a .creds file, by path or by file name next to the context', () {
    final user = Nkeys.createUser();
    File('${dir.path}/app.creds').writeAsStringSync('''
-----BEGIN NATS USER JWT-----
eyJhbGciOiJlZDI1NTE5In0.payload.signature
------END NATS USER JWT------

-----BEGIN USER NKEY SEED-----
${user.seed}
------END USER NKEY SEED------
''');
    writeContext(
        'direct', {'url': 'nats://h', 'creds': '${dir.path}/app.creds'});
    // Written on another machine: only the file name matches.
    writeContext('moved',
        {'url': 'nats://h', 'creds': '/Users/someone/.nats/app.creds'});

    final set = load();
    for (final name in ['direct', 'moved']) {
      final ctx = set.byName(name)!;
      expect(ctx.error, isNull, reason: name);
      final auth = ctx.resolveAuth();
      expect(auth.jwt, 'eyJhbGciOiJlZDI1NTE5In0.payload.signature');
      expect(auth.seed, user.seed);
    }
  });

  test('expands ~ in file paths', () {
    final home = Directory('${dir.path}/home')..createSync();
    final user = Nkeys.createUser();
    File('${home.path}/user.nk').writeAsStringSync('${user.seed}\n');
    writeContext('nk', {'url': 'nats://h', 'nkey': '~/user.nk'});

    final ctx = load({'HOME': home.path}).byName('nk')!;
    expect(ctx.error, isNull);
    expect(ctx.resolveAuth().nkeySeed, user.seed);
  });

  test('marks a context unusable when a file it names is missing', () {
    writeContext('broken', {'url': 'nats://h', 'ca': '/nowhere/ca.pem'});
    final set = load();
    final ctx = set.byName('broken')!;
    expect(ctx.error, contains('its ca file "ca.pem" was not found'));
    expect(ctx.error, isNot(contains('/nowhere')),
        reason: 'the browser sees the file name, not where it was looked for');
    final warnings = set.warnings.join('\n');
    expect(warnings, contains('"broken" is unusable'));
    expect(warnings, contains('/nowhere/ca.pem'), reason: 'the log has it all');
    expect(ctx.toPublicJson(selected: false)['error'], ctx.error);
  });

  test('never logs the contents of a context file it cannot parse', () {
    File('${dir.path}/typo.json').writeAsStringSync(
        '{\n  "url": "nats://h",\n  "password": "hunter2-s3cret"\n  "x": 1\n}');
    final set = load();
    expect(set.contexts, isEmpty);
    final warnings = set.warnings.join('\n');
    expect(warnings, contains('is not valid JSON'));
    expect(warnings, contains('line 4'));
    expect(warnings, isNot(contains('hunter2')));
  });

  test('takes credentials from the URL when the context has none', () {
    writeContext('userpass', {'url': 'nats://bob:p%40ss@h:4222'});
    writeContext('token', {'url': 'nats://t0ken@h'});
    writeContext('own', {'url': 'nats://bob:pw@h', 'token': 'explicit'});
    final set = load();
    final userpass = set.byName('userpass')!.resolveAuth();
    expect(userpass.user, 'bob');
    expect(userpass.password, 'p@ss');
    expect(set.byName('token')!.resolveAuth().token, 't0ken');
    final own = set.byName('own')!.resolveAuth();
    expect(own.token, 'explicit');
    expect(own.user, isEmpty, reason: 'the context\'s own fields win');

    final public = jsonEncode(set.toPublicJson());
    expect(public, isNot(contains('bob')));
    expect(public, isNot(contains('t0ken')));
    expect('${set.byName('userpass')!.servers.single}', 'nats://h:4222');
  });

  test('never echoes credentials from a URL it rejects', () {
    writeContext('bad', {'url': 'ws://bob:s3cret@h'});
    final error = load().byName('bad')!.error!;
    expect(error, contains('***@h'));
    expect(error, isNot(contains('s3cret')));
  });

  test('resolves env:// and file:// references, and rejects others', () {
    File('${dir.path}/token.txt').writeAsStringSync('from-a-file\n');
    writeContext(
        'env', {'url': 'nats://h', 'user': 'u', 'password': 'env://PW'});
    writeContext('file', {'url': 'nats://h', 'token': 'file://token.txt'});
    writeContext('unset', {'url': 'nats://h', 'token': 'env://NOPE'});
    writeContext('vault', {'url': 'nats://h', 'token': 'op://vault/item/x'});
    final set = load({'PW': 'from-env'});
    expect(set.byName('env')!.resolveAuth().password, 'from-env');
    expect(set.byName('file')!.resolveAuth().token, 'from-a-file');
    expect(set.byName('unset')!.error, contains('NOPE, which is not set'));
    final vault = set.byName('vault')!.error!;
    expect(vault, contains('op: references, which are not supported'));
    expect(vault, isNot(contains('vault/item')));
  });

  test('reads credential files again on every connection', () {
    final first = Nkeys.createUser();
    final second = Nkeys.createUser();
    final nk = File('${dir.path}/user.nk')..writeAsStringSync(first.seed);
    writeContext('nk', {'url': 'nats://h', 'nkey': 'user.nk'});
    final ctx = load().byName('nk')!;
    expect(ctx.resolveAuth().nkeySeed, first.seed);
    nk.writeAsStringSync(second.seed);
    expect(ctx.resolveAuth().nkeySeed, second.seed);
    nk.deleteSync();
    expect(ctx.resolveAuth, throwsA(isA<ContextError>()));
  });

  test('marks contexts unusable that would only fail when connecting', () {
    File('${dir.path}/cert.pem').writeAsStringSync('not a certificate');
    writeContext('jwt', {'url': 'nats://h', 'user_jwt': 'a.b.c'});
    writeContext('half', {'url': 'nats://h', 'cert': 'cert.pem'});
    writeContext('pem', {'url': 'nats://h', 'ca': 'cert.pem'});
    final set = load();
    expect(set.byName('jwt')!.error, contains('no seed to sign with'));
    expect(set.byName('half')!.error, contains('cert and key'));
    expect(set.byName('pem')!.error, contains('TLS files cannot be loaded'));
  });

  test('survives a file path with no file name in it', () {
    writeContext('slash', {'url': 'nats://h', 'ca': '/'});
    expect(load().byName('slash')!.error, contains('was not found'));
  });

  test('writes IPv6 servers with brackets', () {
    writeContext('v6', {'url': 'nats://[::1]:4222'});
    final ctx = load().byName('v6')!;
    expect(ctx.servers.single.host, '::1');
    expect('${ctx.servers.single}', 'nats://[::1]:4222');
  });

  test('rejects URLs the relay cannot connect to', () {
    writeContext('ws', {'url': 'ws://h:8080'});
    writeContext('none', {'description': 'no url'});
    final set = load();
    expect(set.byName('ws')!.error, contains('not a nats:// or tls:// URL'));
    expect(set.byName('none')!.error, contains('no url'));
  });

  test('warns about fields it does not support', () {
    writeContext('js', {'url': 'nats://h', 'jetstream_domain': 'hub'});
    expect(load().warnings.join('\n'), contains('JetStream domains'));
  });

  test('picks the selected context from NATS_CONTEXT, then context.txt', () {
    writeContext('a', {'url': 'nats://a'});
    writeContext('b', {'url': 'nats://b'});
    expect(load().selected, isNull, reason: 'two contexts, none chosen');
    File('${dir.path}/context.txt').writeAsStringSync('b\n');
    expect(load().selected, 'b');
    expect(load({'NATS_CONTEXT': 'a'}).selected, 'a');
    final missing = load({'NATS_CONTEXT': 'zzz'});
    expect(missing.selected, 'b', reason: 'falls back to context.txt');
  });

  test('never puts secrets in what the browser sees', () {
    writeContext('prod', {
      'url': 'nats://h',
      'user': 'alice',
      'password': 's3cret',
      'token': 't0ken',
    });
    final json = jsonEncode(load().toPublicJson());
    expect(json, isNot(contains('s3cret')));
    expect(json, isNot(contains('t0ken')));
    expect(json, isNot(contains('alice')));
    expect(jsonDecode(json), [
      {
        'name': 'prod',
        'description': '',
        'server': 'nats://h:4222',
        'selected': true,
      }
    ]);
  });

  group('applyAuth', () {
    final nonce = 'abc123nonce';

    bool verify(String publicKey, String sig) =>
        Nkeys.verify(publicKey, utf8.encode(nonce), base64.decode(sig));

    test('replaces the browser\'s auth with user and password', () {
      final ctx =
          NatsContext(name: 'x', servers: const [], user: 'u', password: 'p');
      final out = ctx.applyAuth(
          {'verbose': false, 'auth_token': 'from-browser', 'user': 'b'}, nonce);
      expect(out, {'verbose': false, 'user': 'u', 'pass': 'p'});
    });

    test('sends a token', () {
      final ctx = NatsContext(name: 'x', servers: const [], token: 't');
      expect(ctx.applyAuth({}, nonce), {'auth_token': 't'});
    });

    test('signs the nonce for an NKey user', () {
      final user = Nkeys.createUser();
      final ctx =
          NatsContext(name: 'x', servers: const [], nkeySeed: user.seed);
      final out = ctx.applyAuth({}, nonce);
      expect(out['nkey'], user.publicKey());
      expect(verify(user.publicKey(), out['sig'] as String), isTrue);
    });

    test('sends the JWT and signs the nonce with its seed', () {
      final user = Nkeys.createUser();
      final ctx = NatsContext(
          name: 'x', servers: const [], jwt: 'the.jwt', seed: user.seed);
      final out = ctx.applyAuth({'nkey': 'from-browser'}, nonce);
      expect(out['jwt'], 'the.jwt');
      expect(out.containsKey('nkey'), isFalse);
      expect(verify(user.publicKey(), out['sig'] as String), isTrue);
    });
  });
}
