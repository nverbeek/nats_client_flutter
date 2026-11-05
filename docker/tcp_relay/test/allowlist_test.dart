import 'dart:io';

import 'package:nats_tcp_relay/allowlist.dart';
import 'package:test/test.dart';

void main() {
  Future<bool> allowed(Set<String> entries, String host, int port,
          {Map<String, List<String>> dns = const {}}) async =>
      (await HostAllowlist(entries,
              lookup: (name) async => [
                    for (final a in dns[name] ?? <String>[]) InternetAddress(a)
                  ]).check(host, port))
          .allowed;

  test('no entries allow anything', () async {
    expect(await allowed({}, 'anything', 1), isTrue);
  });

  test('names, with and without a port', () async {
    final entries = {'nats-a', 'nats-b:4222'};
    expect(await allowed(entries, 'NATS-A', 1234), isTrue);
    expect(await allowed(entries, 'nats-a.', 1234), isTrue);
    expect(await allowed(entries, 'nats-b', 4222), isTrue);
    expect(await allowed(entries, 'nats-b', 8222), isFalse);
    expect(await allowed(entries, 'nats-c', 4222), isFalse);
  });

  test('wildcards match a suffix, not the bare domain', () async {
    final entries = {'*.svc.cluster.local', '*.tenants:4222'};
    expect(await allowed(entries, 'nats.team-a.svc.cluster.local', 1), isTrue);
    expect(await allowed(entries, 'svc.cluster.local', 1), isFalse);
    expect(await allowed(entries, 'evilsvc.cluster.local', 1), isFalse);
    expect(await allowed(entries, 'nats.tenants', 4222), isTrue);
    expect(await allowed(entries, 'nats.tenants', 8222), isFalse);
  });

  test('CIDR ranges match addresses and names resolving into them', () async {
    final entries = {'10.96.0.0/12', 'fd00::/8:4222'};
    expect(await allowed(entries, '10.100.1.2', 1), isTrue);
    expect(await allowed(entries, '10.112.0.1', 1), isFalse);
    expect(await allowed(entries, '[fd00::1]', 4222), isTrue);
    expect(await allowed(entries, 'fd00::1', 8222), isFalse);
    expect(
        await allowed(entries, 'nats.team-a', 4222, dns: {
          'nats.team-a': ['10.97.3.4']
        }),
        isTrue);
    expect(
        await allowed(entries, 'outside', 4222, dns: {
          'outside': ['1.2.3.4']
        }),
        isFalse);
    // Unresolvable.
    expect(await allowed(entries, 'nowhere', 4222), isFalse);
  });

  test('a name resolving partly into a range is pinned to those addresses',
      () async {
    final check = await HostAllowlist({'10.0.0.0/8'},
        lookup: (_) async => [
              InternetAddress('1.2.3.4'),
              InternetAddress('10.1.2.3')
            ]).check('mixed', 4222);
    expect(check.addresses!.map((a) => a.address), ['10.1.2.3']);
  });

  test('a name allowed by name is not resolved or pinned', () async {
    final check = await HostAllowlist({'nats', '10.0.0.0/8'},
        lookup: (_) => throw StateError('looked up')).check('nats', 4222);
    expect(check.allowed, isTrue);
    expect(check.addresses, isNull);
  });

  test('reports invalid entries', () {
    expect(
        HostAllowlist.invalid('ok, *.ok, 10.0.0.0/8, [::1]:4222, '
            'a*b, *, *., 10.0.0.0/33, nope/8, host:0, host:x, '
            'fd00::1:4222, a:b:4222, fd00::zz'),
        [
          'a*b',
          '*',
          '*.',
          '10.0.0.0/33',
          'nope/8',
          'host:0',
          'host:x',
          'a:b:4222',
          'fd00::zz',
        ]);
  });
}
