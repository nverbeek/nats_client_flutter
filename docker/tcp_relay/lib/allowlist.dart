import 'dart:io';

/// Looks a host name up, like [InternetAddress.lookup]. Replaceable in tests.
typedef HostLookup = Future<List<InternetAddress>> Function(String host);

/// `NATS_TCP_ALLOWED_HOSTS`: which servers a browser may reach by typing a
/// host. Each entry is one of these, optionally followed by `:port`:
///
/// - a host name or IP address (`nats-prod`, `10.0.0.5`),
/// - a wildcard (`*.svc.cluster.local`): any name ending in that suffix,
///   with at least one label before it,
/// - a CIDR range (`10.96.0.0/12`, `fd00::/8`): any IP address in it, and
///   any name that resolves into it. Only the resolved addresses inside the
///   range are connected to, so the DNS answer the check saw is the one
///   used.
///
/// An IPv6 address with a port is written `[fd00::1]:4222`. No entries
/// allows any host.
class HostAllowlist {
  HostAllowlist(Iterable<String> entries, {HostLookup? lookup})
      : _lookup = lookup ?? InternetAddress.lookup {
    for (final entry in entries) {
      final rule = _Rule.parse(entry);
      if (rule != null) _rules.add(rule);
    }
  }

  final HostLookup _lookup;
  final _rules = <_Rule>[];

  bool get isEmpty => _rules.isEmpty;

  /// The comma-separated entries of [value], lower-cased.
  static Set<String> parse(String? value) => {
        for (final entry in (value ?? '').split(','))
          if (entry.trim().isNotEmpty) entry.trim().toLowerCase(),
      };

  /// The entries of [value] that aren't valid, for a startup warning. They
  /// allow nothing.
  static List<String> invalid(String? value) => [
        for (final entry in parse(value))
          if (_Rule.parse(entry) == null) entry
      ];

  /// Whether, and where, the relay may connect for [host]:[port].
  Future<HostCheck> check(String host, int port) async {
    if (_rules.isEmpty) return const HostCheck.byName();
    final name = _normalize(host);
    final ranges = <_Rule>[];
    for (final rule in _rules) {
      if (rule.port != null && rule.port != port) continue;
      if (rule.matchesName(name)) return const HostCheck.byName();
      if (rule.network != null) ranges.add(rule);
    }
    const refused = HostCheck.refused('is not in NATS_TCP_ALLOWED_HOSTS');
    if (ranges.isEmpty) return refused;

    final literal = InternetAddress.tryParse(name);
    final List<InternetAddress> addresses;
    if (literal != null) {
      addresses = [literal];
    } else {
      try {
        addresses = await _lookup(name);
      } on SocketException {
        return const HostCheck.refused(
            'could not be resolved, so NATS_TCP_ALLOWED_HOSTS cannot be '
            'checked');
      }
    }
    final inside = [
      for (final address in addresses)
        if (ranges.any((r) => r.contains(address))) address,
    ];
    return inside.isEmpty ? refused : HostCheck.pinned(inside);
  }

  /// Lower case, without the trailing dot of a fully qualified name or the
  /// brackets of an IPv6 address.
  static String _normalize(String host) {
    var h = host.trim().toLowerCase();
    if (h.startsWith('[') && h.endsWith(']')) h = h.substring(1, h.length - 1);
    if (h.endsWith('.')) h = h.substring(0, h.length - 1);
    return h;
  }
}

/// What [HostAllowlist.check] decided.
class HostCheck {
  const HostCheck.byName()
      : addresses = null,
        refusal = null;
  const HostCheck.pinned(List<InternetAddress> this.addresses) : refusal = null;
  const HostCheck.refused(String this.refusal) : addresses = null;

  /// When a CIDR entry allowed the host: connect only to these, in order.
  /// Addresses from a lookup keep the host name, for TLS. Null when the
  /// host may be connected to by name.
  final List<InternetAddress>? addresses;

  /// Why the host is refused, worded to follow `host:port`, or null when
  /// it is allowed.
  final String? refusal;

  bool get allowed => refusal == null;
}

/// One allowlist entry.
class _Rule {
  _Rule({this.name, this.suffix, this.network, this.prefix = 0, this.port});

  /// An exact host name or address.
  final String? name;

  /// For `*.example.com`: `.example.com`.
  final String? suffix;

  /// For a CIDR range: its address and prefix length.
  final InternetAddress? network;
  final int prefix;

  /// Null: any port.
  final int? port;

  bool matchesName(String host) =>
      host == name ||
      (suffix != null &&
          host.length > suffix!.length &&
          host.endsWith(suffix!));

  bool contains(InternetAddress address) {
    final network = this.network;
    if (network == null || network.type != address.type) return false;
    final a = network.rawAddress;
    final b = address.rawAddress;
    var bits = prefix;
    for (var i = 0; i < a.length && bits > 0; i++, bits -= 8) {
      final mask = bits >= 8 ? 0xff : (0xff << (8 - bits)) & 0xff;
      if ((a[i] & mask) != (b[i] & mask)) return false;
    }
    return true;
  }

  static _Rule? parse(String entry) {
    var host = entry.trim().toLowerCase();
    int? port;
    // A port, unless the colons are an IPv6 address's: `[v6]:p`, `v6/n:p`.
    String? portText;
    if (host.startsWith('[')) {
      final end = host.indexOf(']');
      if (end < 0) return null;
      final rest = host.substring(end + 1);
      if (rest.isNotEmpty) {
        if (!rest.startsWith(':')) return null;
        portText = rest.substring(1);
      }
      host = host.substring(1, end);
    } else if (host.contains('/')) {
      final slash = host.indexOf('/');
      final colon = host.indexOf(':', slash);
      if (colon >= 0) {
        portText = host.substring(colon + 1);
        host = host.substring(0, colon);
      }
    } else if (':'.allMatches(host).length == 1) {
      final colon = host.indexOf(':');
      portText = host.substring(colon + 1);
      host = host.substring(0, colon);
    }
    if (portText != null) {
      port = int.tryParse(portText);
      if (port == null || port < 1 || port > 65535) return null;
    }
    if (host.endsWith('.')) host = host.substring(0, host.length - 1);
    if (host.isEmpty) return null;

    if (host.contains('/')) {
      final slash = host.indexOf('/');
      final network = InternetAddress.tryParse(host.substring(0, slash));
      final prefix = int.tryParse(host.substring(slash + 1));
      if (network == null || prefix == null) return null;
      final max = network.rawAddress.length * 8;
      if (prefix < 0 || prefix > max) return null;
      return _Rule(network: network, prefix: prefix, port: port);
    }
    // Any other colon means a port written after an unbracketed IPv6
    // address (`fd00::1:4222` is itself an address, so it stays one) or a
    // typo: as a name it could never match.
    if (host.contains(':') && InternetAddress.tryParse(host) == null) {
      return null;
    }
    if (host.startsWith('*.')) {
      final suffix = host.substring(1);
      if (suffix.length < 2 || suffix.contains('*')) return null;
      return _Rule(suffix: suffix, port: port);
    }
    if (host.contains('*')) return null;
    return _Rule(name: host, port: port);
  }
}
