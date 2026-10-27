import 'dart:convert';

import '../../core/app_config.dart';

enum CandidateKind { hls, mp4, iframe, other }

class StreamCandidate {
  const StreamCandidate({
    required this.url,
    required this.score,
    required this.kind,
    required this.reason,
  });

  final String url;
  final int score;
  final CandidateKind kind;
  final String reason;

  bool get playable => kind == CandidateKind.hls || kind == CandidateKind.mp4;

  @override
  String toString() => '[$score] ${kind.name} $url  <- $reason';
}

/// =============================================================================
///  AD-CLEANER
///  Varre HTML/JSON de pagina de player e devolve APENAS os candidatos limpos,
///  ordenados por probabilidade de serem o CONTEUDO (e nao o anuncio).
///
///  Nada de JS injetado, nada de popup killer: as redes de anuncio sao
///  penalizadas no score e simplesmente descartadas antes de chegar ao player.
/// =============================================================================
class StreamScanner {
  StreamScanner._();

  /// Redes de anuncio, rastreadores e intermediarios de pop-under (adfly-like).
  static const Set<String> adHosts = <String>{
    'doubleclick.net', 'googlesyndication.com', 'googleadservices.com',
    'amazon-adsystem', 'adnxs.com', 'adsrvr.org',
    'popads.net', 'popcash.net', 'propellerads', 'propellerpops', 'onclickads',
    'onclck', 'adcash.com', 'taboola.com', 'outbrain.com', 'mgid.com',
    'revcontent.com', 'adsterra', 'monetag', 'profitableratecpm',
    'highperformanceformat.com', 'hilltopads', 'bidvertiser', 'zedo.com',
    'criteo', 'pubmatic', 'rubiconproject', 'openx.net', 'smartadserver',
    '33across', 'trafficjunky', 'exoclick', 'juicyads', 'admaven',
    'adf.ly', 'shorte.st', 'ouo.io', 'linkvertise', 'adfoc.us',
    'clickadu', 'vidoomy', 'spotxchange', 'primis', 'unrulymedia', 'teads.tv',
    'vungle', 'applovin', 'ironsrc', 'chartboost', 'unityads',
    'supersonicads', 'fyber', 'smaato', 'inmobi', 'startapp',
    'pubnative', 'prebid', 'improvedigital', 'adservice', 'adserver',
  };

  /// Pistas de que a URL e o arquivo principal do conteudo.
  static const List<String> goodHints = <String>[
    '/hls/', '/master', '/vod/', '/stream/', '/media/', '/movie/', '/serie/',
    'playlist', 'manifest', 'index.m3u8', 'chunklist',
  ];

  /// Palavras que indicam teaser em vez do filme.
  static const List<String> teaserHints = <String>['trailer', 'preview', 'teaser'];

  static final RegExp _urlRe = RegExp(
    r'''(?:https?:)?//[^\s"'\\<>\)\]\}]+|/[A-Za-z0-9_\-./]+\.(?:m3u8|mp4|mkv|webm)(?:\?[^\s"'\\<>]*)?''',
  );

  static final RegExp _iframeRe = RegExp(
    r'''<iframe[^>]*?src\s*=\s*["']([^"']+)["']''',
    caseSensitive: false,
  );

  static final RegExp _ogVideoRe = RegExp(
    r'''<meta[^>]+(?:property|name)\s*=\s*["'](?:og:video(?::url|:secure_url)?|twitter:player:stream)["'][^>]+content\s*=\s*["']([^"']+)["']''',
    caseSensitive: false,
  );

  static final RegExp _sourceKeywordRe = RegExp(
    r'''(?:file|source|src|url|hls|stream|playlist|contentUrl|content)\s*[:=]\s*["']([^"']{6,400})["']''',
    caseSensitive: false,
  );

  static final RegExp _atobRe = RegExp(
    r"""atob\s*\(\s*['"]([A-Za-z0-9+/=\\]{24,})['"]\s*\)""",
  );

  static const int adPenalty = 120;
  static const int teaserPenalty = 25;

  static bool isAdUrl(String url) {
    final String u = url.toLowerCase();
    if (u.startsWith('javascript:') ||
        u.startsWith('about:') ||
        u.startsWith('data:') ||
        u.startsWith('blob:')) {
      return true;
    }
    for (final String host in adHosts) {
      if (u.contains(host)) return true;
    }
    if (u.contains('/ads/') ||
        u.contains('?zoneid=') ||
        u.contains('vast') ||
        u.contains('/banner') ||
        u.contains('/pop')) {
      return true;
    }
    return false;
  }

  /// Normaliza escapes de JSON embutido e entidades HTML.
  static String normalize(String src) => src
      .replaceAll(r'\u002F', '/')
      .replaceAll(r'\u002f', '/')
      .replaceAll(r'\/', '/')
      .replaceAll(r'\u003D', '=')
      .replaceAll(r'\u003d', '=')
      .replaceAll(r'\u0026', '&')
      .replaceAll('&amp;', '&');

  /// Desempacota JS no formato Dean Edwards:
  ///   eval(function(p,a,c,k,e,d){...}('payload',radix,count,'w|o|r|d|s'.split('|'),0,{}))
  static String? unpackJs(String src) {
    final RegExpMatch? m = RegExp(
      r"""}\s*\(\s*'((?:[^'\\]|\\.)*)'\s*,\s*(\d+)\s*,\s*(\d+)\s*,\s*'((?:[^'\\]|\\.)*)'\s*\.split\('\|'\)""",
    ).firstMatch(src);
    if (m == null) return null;

    final String payload = m.group(1)!;
    final int radix = int.parse(m.group(2)!);
    final List<String> words = m.group(4)!.split('|');
    if (words.isEmpty || radix < 2) return null;

    String toBase(int n, int r) {
      const String digits = '0123456789abcdefghijklmnopqrstuvwxyz';
      if (n == 0) return '0';
      final StringBuffer sb = StringBuffer();
      for (int v = n; v > 0; v ~/= r) {
        sb.write(digits[v % r]);
      }
      return sb.toString().split('').reversed.join();
    }

    final Map<String, String> dict = <String, String>{};
    for (int i = 0; i < words.length; i++) {
      dict[toBase(i, radix)] = words[i];
    }

    return payload.replaceAllMapped(
      RegExp(r'\b([0-9a-z]+)\b', caseSensitive: false),
      (Match mm) => dict[mm.group(1)!] ?? mm.group(1)!,
    );
  }

  /// atob('...') pode esconder a URL real do stream.
  static String decodeBase64Blobs(String html) {
    final StringBuffer out = StringBuffer();
    for (final RegExpMatch m in _atobRe.allMatches(html)) {
      try {
        out.writeln(utf8.decode(base64.decode(base64.normalize(m.group(1)!))));
      } catch (_) {}
    }
    return out.toString();
  }

  /// Ponto de entrada. `base` = URL final da pagina (para resolver relativos).
  static List<StreamCandidate> scan(String html, {required Uri base}) {
    final Map<String, int> scores = <String, int>{};
    final Map<String, CandidateKind> kinds = <String, CandidateKind>{};
    final Map<String, String> reasons = <String, String>{};

    final String norm = normalize(html);
    final String? unpacked = unpackJs(norm);
    final String b64 = decodeBase64Blobs(norm);
    final String all = <String>[
      norm,
      ?unpacked,
      if (b64.isNotEmpty) b64,
    ].join('\n');

    void consider(String rawUrl, int score, CandidateKind kind, String reason) {
      final String url = rawUrl.trim();
      if (url.isEmpty) return;

      if (isAdUrl(url)) score -= adPenalty; // <<< coracao do ad-cleaner

      Uri abs;
      try {
        abs = base.resolve(url);
      } catch (_) {
        return;
      }
      final String full = abs.toString();
      if (!full.startsWith('http')) return;

      final String lower = full.toLowerCase();

      CandidateKind k = kind;
      if (k == CandidateKind.other) {
        if (lower.contains('.m3u8')) {
          k = CandidateKind.hls;
        } else if (lower.contains('.mp4') || lower.contains('.mkv') || lower.contains('.webm')) {
          k = CandidateKind.mp4;
        } else {
          return;
        }
      }

      for (final String hint in goodHints) {
        if (lower.contains(hint)) score += 10;
      }
      for (final String teaser in teaserHints) {
        if (lower.contains(teaser)) score -= teaserPenalty;
      }

      if (score > (scores[full] ?? -99999)) {
        scores[full] = score;
        kinds[full] = k;
        reasons[full] = reason;
      }
    }

    // 1) og:video - sinal mais forte de "isto e o video"
    for (final RegExpMatch m in _ogVideoRe.allMatches(norm)) {
      consider(m.group(1)!, 90, CandidateKind.other, 'meta og:video');
    }

    // 2) JSON embutido com contexto de fonte
    for (final RegExpMatch m in _sourceKeywordRe.allMatches(norm)) {
      consider(m.group(1)!, 55, CandidateKind.other, 'contexto de fonte');
    }

    // 3) qualquer URL com extensao de midia (inclui JS empacotado e base64)
    for (final RegExpMatch m in _urlRe.allMatches(all)) {
      consider(m.group(0)!, 50, CandidateKind.other, 'regex de midia');
    }

    // 4) iframes (embed aninhado)
    for (final RegExpMatch m in _iframeRe.allMatches(all)) {
      consider(m.group(1)!, 30, CandidateKind.iframe, 'iframe');
    }

    final List<StreamCandidate> out = scores.entries
        .where((MapEntry<String, int> e) => e.value > -50)
        .map((MapEntry<String, int> e) => StreamCandidate(
              url: e.key,
              score: e.value,
              kind: kinds[e.key] ?? CandidateKind.other,
              reason: reasons[e.key] ?? '',
            ))
        .toList()
      ..sort((StreamCandidate a, StreamCandidate b) => b.score.compareTo(a.score));

    return out.take(AppConfig.maxCandidates).toList();
  }
}