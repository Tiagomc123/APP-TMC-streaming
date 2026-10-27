import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../app_config.dart';

class HttpResult {
  HttpResult({
    required this.status,
    required this.body,
    required this.finalUrl,
    required this.headers,
  });

  final int status;
  final String body;
  final Uri finalUrl;
  final Map<String, String> headers;

  bool get ok => status >= 200 && status < 400;

  bool get challenged =>
      status == 403 ||
      status == 503 ||
      body.contains('cf-browser-verification') ||
      body.contains('Just a moment') ||
      body.contains('challenge-platform');
}

class ProbeResult {
  const ProbeResult({
    required this.ok,
    this.isHls = false,
    this.isMp4 = false,
    this.status = 0,
  });

  final bool ok;
  final bool isHls;
  final bool isMp4;
  final int status;
}

/// Cliente HTTP unico do app: parece um Chrome Android limpo, guarda cookies
/// de sessao e sobrevive a Cloudflare - tudo sem abrir WebView.
class TmcHttp {
  TmcHttp({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  final Map<String, Map<String, String>> _jar = <String, Map<String, String>>{};

  Map<String, String> browserHeaders({
    String? referer,
    String? origin,
    bool json = false,
    Map<String, String>? extra,
  }) {
    final String host = referer == null ? '' : (Uri.tryParse(referer)?.host ?? '');
    final Map<String, String> jar = _jar[host] ?? const <String, String>{};

    return <String, String>{
      'User-Agent': AppConfig.userAgent,
      'Accept': json ? AppConfig.acceptJson : AppConfig.acceptHtml,
      'Accept-Language': AppConfig.acceptLang,
      'Cache-Control': 'no-cache',
      'Pragma': 'no-cache',
      if (!json) 'Upgrade-Insecure-Requests': '1',
      'Sec-Fetch-Dest': json ? 'empty' : 'document',
      'Sec-Fetch-Mode': json ? 'cors' : 'navigate',
      'Sec-Fetch-Site': referer == null ? 'none' : 'same-origin',
      'Referer': ?referer,
      'Origin': ?origin,
      if (jar.isNotEmpty)
        'Cookie': jar.entries
            .map((MapEntry<String, String> e) => '${e.key}=${e.value}')
            .join('; '),
      ...?extra,
    };
  }

  void _storeCookies(Uri uri, Map<String, String> headers) {
    final String? raw = headers['set-cookie'];
    if (raw == null || raw.isEmpty) return;
    final Map<String, String> jar = _jar.putIfAbsent(uri.host, () => <String, String>{});
    for (final String part in raw.split(RegExp(r',(?=\s*[A-Za-z0-9_\-]+=)'))) {
      final String pair = part.split(';').first.trim();
      final int eq = pair.indexOf('=');
      if (eq > 0) jar[pair.substring(0, eq)] = pair.substring(eq + 1);
    }
  }

  Future<HttpResult?> getText(
    String url, {
    String? referer,
    String? origin,
    Map<String, String>? extra,
    bool json = false,
    int retries = 1,
    Duration? timeout,
  }) async {
    final Uri? uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme) return null;

    for (int attempt = 0; attempt <= retries; attempt++) {
      try {
        final http.Response res = await _client
            .get(uri, headers: browserHeaders(referer: referer, origin: origin, json: json, extra: extra))
            .timeout(timeout ?? const Duration(seconds: 18));

        _storeCookies(res.request?.url ?? uri, res.headers);

        final HttpResult out = HttpResult(
          status: res.statusCode,
          body: utf8.decode(res.bodyBytes, allowMalformed: true),
          finalUrl: res.request?.url ?? uri,
          headers: res.headers,
        );

        // challenge do Cloudflare -> reenvia ja com os cookies gravados
        if (out.challenged && attempt < retries) {
          await Future<void>.delayed(const Duration(milliseconds: 450));
          continue;
        }
        return out;
      } catch (_) {
        if (attempt >= retries) return null;
        await Future<void>.delayed(Duration(milliseconds: 300 * (attempt + 1)));
      }
    }
    return null;
  }

  Future<Map<String, dynamic>?> getJson(
    String url, {
    String? referer,
    String? origin,
    int retries = 1,
  }) async {
    final HttpResult? r = await getText(url, referer: referer, origin: origin, json: true, retries: retries);
    if (r == null || !r.ok) return null;
    try {
      final dynamic j = jsonDecode(r.body);
      return j is Map ? j.cast<String, dynamic>() : null;
    } catch (_) {
      return null;
    }
  }

  /// Confirma que a URL e jogavel AGORA (evita abrir player em link morto).
  Future<ProbeResult> probe(
    String url, {
    Map<String, String>? headers,
    String? referer,
    Duration? timeout,
  }) async {
    final Uri? uri = Uri.tryParse(url);
    if (uri == null) return const ProbeResult(ok: false);

    try {
      final http.Request req = http.Request('GET', uri)
        ..headers.addAll(browserHeaders(
          referer: referer,
          extra: <String, String>{'Range': 'bytes=0-4095', ...?headers},
        ));

      final http.StreamedResponse res =
          await _client.send(req).timeout(timeout ?? AppConfig.probeTimeout);

      if (res.statusCode != 200 && res.statusCode != 206) {
        return ProbeResult(ok: false, status: res.statusCode);
      }

      final List<int> bytes = <int>[];
      await for (final List<int> chunk in res.stream) {
        bytes.addAll(chunk);
        if (bytes.length >= 4096) break;
      }

      final String head = utf8.decode(bytes, allowMalformed: true);
      final String ctype = (res.headers['content-type'] ?? '').toLowerCase();

      final bool isHls = head.contains('#EXTM3U') || ctype.contains('mpegurl');
      final bool isMp4 = ctype.contains('video/') ||
          ctype.contains('octet-stream') ||
          uri.path.toLowerCase().endsWith('.mp4');

      return ProbeResult(ok: isHls || isMp4, isHls: isHls, isMp4: isMp4, status: res.statusCode);
    } catch (_) {
      return const ProbeResult(ok: false);
    }
  }

  void close() => _client.close();
}