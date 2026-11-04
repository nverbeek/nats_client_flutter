import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'format_utils.dart';
import 'tcp_relay.dart';

// Reading nats-server's HTTP monitoring endpoint (`/varz`, `/connz`,
// `/healthz`, `/gatewayz`) for the Server tab. No widgets here, so all of it
// is unit-testable with `package:http/testing.dart`'s MockClient.
//
// nats-server answers every monitoring request with
// `Access-Control-Allow-Origin: *`, so a browser can call it directly; the
// Docker image's relay (`nats-monitor`) is only needed when the browser
// can't reach the host itself (see `RelayMonitorEndpoint`).

int _int(Object? value) => value is num ? value.toInt() : 0;
double _double(Object? value) => value is num ? value.toDouble() : 0;
String _string(Object? value) => value is String ? value : '';
DateTime? _time(Object? value) =>
    value is String ? DateTime.tryParse(value) : null;
Map<String, dynamic>? _map(Object? value) =>
    value is Map<String, dynamic> ? value : null;

/// The parts of `/varz` the Server tab shows.
class ServerVarz {
  const ServerVarz({
    required this.serverId,
    this.serverName = '',
    this.version = '',
    this.goVersion = '',
    this.host = '',
    this.port = 0,
    this.start,
    this.now,
    this.connections = 0,
    this.subscriptions = 0,
    this.cpu = 0,
    this.mem = 0,
    this.cores = 0,
    this.maxPayload = 0,
    this.authRequired = false,
    this.tlsRequired = false,
    this.routes = 0,
    this.leafnodes = 0,
    this.clusterName,
    this.gatewayName,
    this.jetStreamEnabled = false,
    this.jetStreamDomain,
    this.inMsgs = 0,
    this.outMsgs = 0,
    this.inBytes = 0,
    this.outBytes = 0,
  });

  final String serverId;
  final String serverName;
  final String version;
  final String goVersion;
  final String host;
  final int port;
  final DateTime? start;

  /// The server's clock when it answered. Rates use it rather than the
  /// app's clock, so a slow response doesn't skew them.
  final DateTime? now;
  final int connections;
  final int subscriptions;

  /// Percent of one core, as nats-server reports it (can exceed 100).
  final double cpu;

  /// Resident memory in bytes.
  final int mem;
  final int cores;
  final int maxPayload;
  final bool authRequired;
  final bool tlsRequired;
  final int routes;
  final int leafnodes;
  final String? clusterName;
  final String? gatewayName;
  final bool jetStreamEnabled;
  final String? jetStreamDomain;

  // Running totals since the server started.
  final int inMsgs;
  final int outMsgs;
  final int inBytes;
  final int outBytes;

  Duration? get uptime =>
      start == null || now == null ? null : now!.difference(start!);

  factory ServerVarz.fromJson(Map<String, dynamic> json) {
    final cluster = _map(json['cluster']);
    final gateway = _map(json['gateway']);
    final jetStreamConfig = _map(_map(json['jetstream'])?['config']);
    String? nonEmpty(Object? v) => v is String && v.isNotEmpty ? v : null;
    return ServerVarz(
      serverId: _string(json['server_id']),
      serverName: _string(json['server_name']),
      version: _string(json['version']),
      goVersion: _string(json['go']),
      host: _string(json['host']),
      port: _int(json['port']),
      start: _time(json['start']),
      now: _time(json['now']),
      connections: _int(json['connections']),
      subscriptions: _int(json['subscriptions']),
      cpu: _double(json['cpu']),
      mem: _int(json['mem']),
      cores: _int(json['cores']),
      maxPayload: _int(json['max_payload']),
      authRequired: json['auth_required'] == true,
      tlsRequired: json['tls_required'] == true,
      routes: _int(json['routes']),
      leafnodes: _int(json['leafnodes']),
      clusterName: nonEmpty(cluster?['name']),
      gatewayName: nonEmpty(gateway?['name']),
      jetStreamEnabled: jetStreamConfig != null,
      jetStreamDomain: nonEmpty(jetStreamConfig?['domain']),
      inMsgs: _int(json['in_msgs']),
      outMsgs: _int(json['out_msgs']),
      inBytes: _int(json['in_bytes']),
      outBytes: _int(json['out_bytes']),
    );
  }
}

/// One client connection from `/connz`.
class ConnSummary {
  const ConnSummary({
    required this.cid,
    this.name = '',
    this.ip = '',
    this.port = 0,
    this.lang = '',
    this.version = '',
    this.subscriptions = 0,
    this.pendingBytes = 0,
    this.inMsgs = 0,
    this.outMsgs = 0,
    this.uptime,
  });

  final int cid;
  final String name;
  final String ip;
  final int port;
  final String lang;
  final String version;
  final int subscriptions;
  final int pendingBytes;

  /// Messages from the client to the server.
  final int inMsgs;

  /// Messages from the server to the client.
  final int outMsgs;
  final Duration? uptime;

  /// `ip:port`, with an IPv6 address bracketed.
  String get address => ip.contains(':') ? '[$ip]:$port' : '$ip:$port';

  /// `go 1.41.2`, or empty when the client didn't say.
  String get client => [lang, version].where((s) => s.isNotEmpty).join(' ');

  factory ConnSummary.fromJson(Map<String, dynamic> json, DateTime? now) {
    final start = _time(json['start']);
    return ConnSummary(
      cid: _int(json['cid']),
      name: _string(json['name']),
      ip: _string(json['ip']),
      port: _int(json['port']),
      lang: _string(json['lang']),
      version: _string(json['version']),
      subscriptions: _int(json['subscriptions']),
      pendingBytes: _int(json['pending_bytes']),
      inMsgs: _int(json['in_msgs']),
      outMsgs: _int(json['out_msgs']),
      uptime: start == null || now == null ? null : now.difference(start),
    );
  }
}

/// One page of `/connz`.
class ConnzPage {
  const ConnzPage({
    required this.total,
    required this.offset,
    required this.limit,
    required this.connections,
  });

  /// Open connections on the server, across all pages.
  final int total;
  final int offset;
  final int limit;
  final List<ConnSummary> connections;

  factory ConnzPage.fromJson(Map<String, dynamic> json) {
    final now = _time(json['now']);
    final list = json['connections'];
    return ConnzPage(
      total: _int(json['total']),
      offset: _int(json['offset']),
      limit: _int(json['limit']),
      connections: [
        if (list is List)
          for (final c in list)
            if (c is Map<String, dynamic>) ConnSummary.fromJson(c, now),
      ],
    );
  }
}

/// `/healthz`: ok, or the server's reason it isn't.
class HealthStatus {
  const HealthStatus({required this.ok, this.error});
  final bool ok;
  final String? error;
}

/// The `/connz` sort orders the Server tab offers. nats-server sorts on its
/// side (the only way to sort across pages) and picks the direction itself:
/// only `cid` is ascending, everything else descending.
enum ConnzSort {
  cid('cid', ascending: true),
  subs('subs'),
  pending('pending'),
  msgsFrom('msgs_from'),
  msgsTo('msgs_to'),
  uptime('uptime');

  const ConnzSort(this.apiValue, {this.ascending = false});

  /// The `sort=` value.
  final String apiValue;
  final bool ascending;
}

/// Where the monitoring requests go.
sealed class MonitorEndpoint {
  const MonitorEndpoint();

  /// The request URL for monitoring [path] (`varz`, `connz`, …).
  Uri uri(String path, [Map<String, String> query = const {}]);

  /// What to show the user, e.g. `http://127.0.0.1:8222`.
  String get label;
}

/// Straight to the server's monitoring port: desktop, and a browser that
/// can reach the host itself.
///
/// nats-server serves monitoring over either http (`http_port`, `-m`) or
/// https (`https_port`, e.g. demo.nats.io), and nothing says which, so
/// [ServerMonitorClient] starts with http and sets [https] once https is
/// the one that answers.
class DirectMonitorEndpoint extends MonitorEndpoint {
  DirectMonitorEndpoint(this.host, this.port,
      {this.blockedByMixedContent = false})
      : https = blockedByMixedContent;

  final String host;
  final int port;

  /// True on an https page: browsers block an http request from it, so
  /// only https is tried.
  final bool blockedByMixedContent;

  /// Whether requests go over https.
  bool https;

  /// Whether http has answered before. After that, a failed request is
  /// the server being down, not a sign that it speaks https.
  bool httpAnswered = false;

  @override
  Uri uri(String path, [Map<String, String> query = const {}]) =>
      uriOver(path, query, https: https);

  /// [uri] over https or http, whatever [https] says.
  Uri uriOver(String path, Map<String, String> query, {required bool https}) =>
      Uri(
          scheme: https ? 'https' : 'http',
          host: bareHost(host),
          port: port,
          path: '/$path',
          queryParameters: query.isEmpty ? null : query);

  @override
  String get label {
    final h = host.contains(':') && !host.startsWith('[') ? '[$host]' : host;
    return '${https ? 'https' : 'http'}://$h:$port';
  }
}

/// Through the Docker image's relay, which fetches from inside the
/// container: needed for a host only the container can resolve, a context
/// (whose servers the page never learns), or an https page.
class RelayMonitorEndpoint extends MonitorEndpoint {
  const RelayMonitorEndpoint.host(this.pageBase, String this.host, this.port)
      : context = null;
  const RelayMonitorEndpoint.context(
      this.pageBase, String this.context, this.port)
      : host = null;

  final Uri pageBase;
  final String? host;
  final String? context;
  final int port;

  @override
  Uri uri(String path, [Map<String, String> query = const {}]) =>
      tcpRelayMonitorUri(pageBase,
          host: host, context: context, port: port, path: path, query: query);

  @override
  String get label => context != null
      ? 'context "$context", port $port, via the relay'
      : '$host:$port via the relay';
}

enum MonitorErrorKind {
  /// No answer: refused, timed out, DNS failure.
  unreachable,

  /// Something answered, but not nats-server's monitoring endpoint.
  notMonitoring,

  /// An https page can't make the http request.
  mixedContent,

  /// The Docker image's relay said no, with a reason.
  relayRefused,

  /// Any other HTTP status.
  httpError,
}

class MonitorException implements Exception {
  const MonitorException(this.kind, [this.detail, this.fromRelay = false]);
  final MonitorErrorKind kind;
  final String? detail;

  /// [detail] is the relay's own reason, which names the server it tried,
  /// rather than this app's error reaching the relay.
  final bool fromRelay;

  @override
  String toString() => 'MonitorException($kind, $detail)';
}

/// What to tell the user about [error] reaching [endpoint].
String describeMonitorError(Object error, MonitorEndpoint endpoint) {
  if (error is! MonitorException) {
    return 'Unexpected error: ${truncatedErrorDetail(error)}';
  }
  final detail = error.detail;
  switch (error.kind) {
    // Through the relay, its own words name the server it tried.
    case MonitorErrorKind.unreachable:
      if (error.fromRelay && detail != null) {
        return 'The relay reports: $detail.';
      }
      return endpoint is RelayMonitorEndpoint
          ? 'No response from the relay${detail == null ? '' : ' ($detail)'}.'
          : 'No response from ${endpoint.label}.';
    case MonitorErrorKind.notMonitoring:
      return error.fromRelay && detail != null
          ? 'The relay reports: $detail. Check the port in Settings.'
          : '${endpoint.label} answered, but not as a NATS monitoring '
              'endpoint. Check the port in Settings.';
    case MonitorErrorKind.mixedContent:
      return 'This page was loaded over https, so the browser only allows '
          'https requests, and ${endpoint.label} did not answer. A server '
          'whose monitoring is plain http (-m, http_port) can only be '
          'reached from an http page or the desktop app.';
    case MonitorErrorKind.relayRefused:
      return 'The relay refused: ${detail ?? 'no reason given'}';
    case MonitorErrorKind.httpError:
      return '${endpoint.label} answered with HTTP ${detail ?? '?'}.';
  }
}

/// Fetches from one monitoring endpoint, reusing one HTTP client (and its
/// kept-alive connection) for the life of the session. Methods aren't
/// final, so widget tests can override them.
class ServerMonitorClient {
  /// [client] is closed by [close] only when this created it, or when
  /// [ownsClient] says it was made for this alone. [timeout] defaults to
  /// [directTimeout] or [relayTimeout], by [endpoint].
  ServerMonitorClient(this.endpoint,
      {http.Client? client, bool ownsClient = false, Duration? timeout})
      : timeout = timeout ??
            (endpoint is RelayMonitorEndpoint ? relayTimeout : directTimeout),
        _client = client ?? http.Client(),
        _ownsClient = client == null || ownsClient;

  static const directTimeout = Duration(seconds: 5);

  /// The relay gives each of a context's servers 5 s, and as long again
  /// for https, so it needs longer than one request to say why it failed.
  static const relayTimeout = Duration(seconds: 20);

  final MonitorEndpoint endpoint;
  final Duration timeout;
  final http.Client _client;
  final bool _ownsClient;

  Future<ServerVarz> fetchVarz() async =>
      ServerVarz.fromJson(await _get('varz', requireServerId: true));

  Future<ConnzPage> fetchConnz(
      {required ConnzSort sort, int offset = 0, int limit = 25}) async {
    final json = await _get('connz',
        query: {
          'sort': sort.apiValue,
          'offset': '$offset',
          'limit': '$limit',
        },
        requireServerId: true);
    return ConnzPage.fromJson(json);
  }

  Future<HealthStatus> fetchHealth() async {
    final json = await _get('healthz', unhealthyIsAnswer: true);
    final status = _string(json['status']);
    if (status.isEmpty) {
      throw const MonitorException(MonitorErrorKind.notMonitoring);
    }
    final error = _string(json['error']);
    return HealthStatus(
        ok: status == 'ok', error: error.isEmpty ? null : error);
  }

  /// Gateways this server has outbound connections to.
  Future<int> fetchGatewayCount() async {
    final json = await _get('gatewayz', requireServerId: true);
    return _map(json['outbound_gateways'])?.length ?? 0;
  }

  void close() {
    if (_ownsClient) _client.close();
  }

  Future<Map<String, dynamic>> _get(String path,
      {Map<String, String> query = const {},
      bool requireServerId = false,
      bool unhealthyIsAnswer = false}) async {
    final endpoint = this.endpoint;
    final http.Response response;
    if (endpoint is DirectMonitorEndpoint && !endpoint.https) {
      response = await _getWithHttpsFallback(endpoint, path, query);
    } else {
      try {
        response = await _send(endpoint.uri(path, query));
      } on MonitorException catch (e) {
        if (endpoint is DirectMonitorEndpoint &&
            endpoint.blockedByMixedContent &&
            e.kind == MonitorErrorKind.unreachable) {
          throw MonitorException(MonitorErrorKind.mixedContent, e.detail);
        }
        rethrow;
      }
    }

    Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException {
      decoded = null;
    }
    final json = decoded is Map<String, dynamic> ? decoded : null;

    if (endpoint is RelayMonitorEndpoint &&
        response.statusCode != 200 &&
        json != null &&
        json['error'] is String &&
        json['status'] == null) {
      // The relay answers 504 when the server didn't answer it, and 502
      // when something else did; anything else is the relay saying no.
      final reason = json['error'] as String;
      throw MonitorException(
          switch (response.statusCode) {
            504 => MonitorErrorKind.unreachable,
            502 => MonitorErrorKind.notMonitoring,
            _ => MonitorErrorKind.relayRefused,
          },
          reason,
          true);
    }
    final healthAnswer = unhealthyIsAnswer && response.statusCode == 503;
    if (response.statusCode != 200 && !healthAnswer) {
      throw MonitorException(
          response.statusCode == 404
              ? MonitorErrorKind.notMonitoring
              : MonitorErrorKind.httpError,
          '${response.statusCode}');
    }
    if (json == null ||
        (requireServerId && _string(json['server_id']).isEmpty)) {
      throw const MonitorException(MonitorErrorKind.notMonitoring);
    }
    return json;
  }

  Future<http.Response> _send(Uri uri) async {
    try {
      // Only for the relay: on a direct request from a browser, a custom
      // header would make it ask nats-server for a CORS preflight first.
      return await _client
          .get(uri,
              headers: endpoint is RelayMonitorEndpoint
                  ? const {tcpRelayMonitorHeader: '1'}
                  : null)
          .timeout(timeout);
    } on TimeoutException {
      throw const MonitorException(MonitorErrorKind.unreachable, 'timed out');
    } catch (e) {
      // http.ClientException on every platform, wrapping the socket error.
      throw MonitorException(
          MonitorErrorKind.unreachable, truncatedErrorDetail(e));
    }
  }

  /// Tries http, and https when http says the port speaks https: the 400
  /// Go's server sends, or (in a browser, which hides that 400 because it
  /// has no CORS header) no usable answer at all, as long as http has never
  /// answered. Once https answers, the endpoint stays on it. If https fails
  /// too, the http failure is what's reported, since http is the usual
  /// setup.
  Future<http.Response> _getWithHttpsFallback(DirectMonitorEndpoint endpoint,
      String path, Map<String, String> query) async {
    http.Response? httpResponse;
    MonitorException? httpError;
    try {
      httpResponse = await _send(endpoint.uriOver(path, query, https: false));
      if (!_isHttpsOnlyReply(httpResponse)) {
        endpoint.httpAnswered = true;
        return httpResponse;
      }
    } on MonitorException catch (e) {
      if (endpoint.httpAnswered) rethrow;
      httpError = e;
    }
    try {
      final response = await _send(endpoint.uriOver(path, query, https: true));
      endpoint.https = true;
      return response;
    } on MonitorException {
      if (httpError != null) throw httpError;
      return httpResponse!;
    }
  }

  static bool _isHttpsOnlyReply(http.Response response) =>
      response.statusCode == 400 &&
      response.body.contains('HTTP request to an HTTPS server');
}

/// Message and byte rates for one poll interval, per second.
class ThroughputSample {
  const ThroughputSample({
    required this.time,
    required this.inMsgs,
    required this.outMsgs,
    required this.inBytes,
    required this.outBytes,
    this.gapBefore = false,
  });

  /// The server's clock at the end of the interval.
  final DateTime time;
  final double inMsgs;
  final double outMsgs;
  final double inBytes;
  final double outBytes;

  /// Polls were missed before this one (the tab was hidden, or polls
  /// failed), so the chart shouldn't join it to the previous sample.
  final bool gapBefore;
}

/// The last two minutes of throughput, worked out from `/varz`'s running
/// totals: each rate is the difference between two polls over the time
/// between them. Lives as long as the connection, not the dashboard, so the
/// chart keeps its history when the tab is left and reopened.
class ThroughputHistory {
  static const window = Duration(minutes: 2);

  final List<ThroughputSample> _samples = [];
  ServerVarz? _previous;
  bool _gap = false;
  int _version = 0;

  List<ThroughputSample> get samples => List.unmodifiable(_samples);

  /// Bumped on every change, so a painter can tell whether to repaint.
  int get version => _version;

  /// Adds the rates since the previous [varz]. [interval] is how far apart
  /// polls are expected to be. A much longer wait is a gap: its average rate
  /// isn't added, since it would be plotted (and shown in the legend) as the
  /// current one, and the next sample starts a new line.
  void add(ServerVarz varz, {required Duration interval}) {
    final previous = _previous;
    _previous = varz;
    final now = varz.now;
    if (previous == null || now == null || previous.now == null) return;

    // A restarted server starts its totals over, so nothing before it
    // compares with anything after.
    final restarted = previous.serverId != varz.serverId ||
        previous.start != varz.start ||
        varz.inMsgs < previous.inMsgs ||
        varz.outMsgs < previous.outMsgs ||
        varz.inBytes < previous.inBytes ||
        varz.outBytes < previous.outBytes;
    if (restarted) {
      _samples.clear();
      _version++;
      return;
    }

    final elapsed = now.difference(previous.now!);
    if (elapsed <= Duration.zero) return;
    if (elapsed > interval * 2.5) {
      _gap = _samples.isNotEmpty;
      _samples.removeWhere((s) => now.difference(s.time) > window);
      _version++;
      return;
    }
    final seconds = elapsed.inMicroseconds / Duration.microsecondsPerSecond;
    _samples.add(ThroughputSample(
      time: now,
      inMsgs: (varz.inMsgs - previous.inMsgs) / seconds,
      outMsgs: (varz.outMsgs - previous.outMsgs) / seconds,
      inBytes: (varz.inBytes - previous.inBytes) / seconds,
      outBytes: (varz.outBytes - previous.outBytes) / seconds,
      gapBefore: _gap && _samples.isNotEmpty,
    ));
    _gap = false;
    _samples.removeWhere((s) => now.difference(s.time) > window);
    _version++;
  }
}

/// Everything the Server tab needs for one connection. Created by
/// `main.dart` on connect (only while the tab is enabled), discarded on
/// the next connect or when the tab is turned off.
class ServerMonitorSession {
  ServerMonitorSession(this.client);

  final ServerMonitorClient client;
  final ThroughputHistory history = ThroughputHistory();

  MonitorEndpoint get endpoint => client.endpoint;

  void dispose() => client.close();
}
