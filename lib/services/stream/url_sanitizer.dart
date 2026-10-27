import '../../core/app_config.dart';

/// =============================================================================
///  SANITIZADOR / INTERCEPTOR DE URL
///
///  Recebe QUALQUER string vinda de uma API JSON (mesmo que venha suja, com
///  proxy, com redirecionamento de anuncio ou duplo-encoded) e devolve
///  ESTRITAMENTE o manifesto de video puro.
///
///   - desescapa \/ , \u002F , \u0026 e &amp;
///   - desembrulha proxies ?url= / ?file= / ?src= / ?video= / ?stream=
///   - decodifica duplo percent-encoding (https%3A%2F%2F...)
///   - descarta hosts de anuncio, banner, pop-under e rastreador
///   - remove parametros de tracking (utm_*, gclid, fbclid, zoneid, clickid)
///   - preserva parametros que o CDN exige (token, hash, expires, sig, key)
/// =============================================================================
class UrlSanitizer {
  UrlSanitizer._();

  static const Set<String> adHosts = <String>{
    'doubleclick.net', 'googlesyndication.com', 'googleadservices.com',
    'amazon-adsystem', 'adnxs.com', 'adsrvr.org',
    'popads.net', 'popcash.net', 'propellerads', 'propellerpops', 'onclickads',
    'onclck', 'adcash.com', 'taboola.com', 'outbrain.com', 'mgid.com',
    'revcontent.com', 'adsterra', 'monetag', 'profitableratecpm',
    'highperformanceformat.com', 'hilltopads', 'bidvertiser', 'zedo.com',
    'criteo', 'pubmatic', 'rubiconproject', 'openx.net', 'smartadserver',
    'exoclick', 'juicyads', 'admaven', 'adf.ly', 'shorte.st', 'ouo.io',
    'linkvertise', 'adfoc.us', 'clickadu', 'vidoomy', 'spotxchange', 'primis',
    'teads.tv', 'vungle', 'applovin', 'inmobi', 'prebid', 'adservice', 'adserver',
  };

  static const Set<String> unwrapKeys = <String>{
    'url', 'file', 'src', 'video', 'stream', 'playlist', 'source', 'link', 'embed', 'media',
  };

  static const Set<String> trackingKeys = <String>{
    'utm_source', 'utm_medium', 'utm_campaign', 'utm_term', 'utm_content',
    'gclid', 'fbclid', 'msclkid', 'zoneid', 'clickid', 'ref', 'referrer',
    '_', 'cb', 'cache', 'nocache', 'rand',
  };

  static const Set<String> keepKeys = <String>{
    'token', 'hash', 'expires', 'exp', 'sig', 'signature', 'key', 'auth',
    'authkey', 'md5', 'start', 'end', 'id', 'type', 'quality', 'lang', 'audio',
    'session', 'sid', 'policy',
  };

  static final RegExp _mediaRe = RegExp(r'\.(m3u8|mp4|mkv|webm|mpd)(\?|$)');

  static bool isMedia(String url) => _mediaRe.hasMatch(url.toLowerCase());

  static bool isAd(String url) {
    final String u = url.toLowerCase();
    if (u.startsWith('javascript:') || u.startsWith('about:') || u.startsWith('data:')) {
      return true;
    }
    for (final String host in adHosts) {
      if (u.contains(host)) return true;
    }
    return u.contains('/ads/') || u.contains('?zoneid=') || u.contains('vast') ||
        u.contains('/banner') || u.contains('/pop');
  }

  /// Desescapa tudo que um JSON mal-formado costuma trazer.
  static String unescape(String raw) {
    String s = raw.trim();
    if (s.length > 1) {
      final String first = s.substring(0, 1);
      final String last = s.substring(s.length - 1);
      if ((first == '"' && last == '"') || (first == "'" && last == "'")) {
        s = s.substring(1, s.length - 1);
      }
    }
    s = s
        .replaceAll(r'\u002F', '/')
        .replaceAll(r'\u002f', '/')
        .replaceAll(r'\/', '/')
        .replaceAll(r'\u0026', '&')
        .replaceAll(r'\u003D', '=')
        .replaceAll(r'\u003d', '=')
        .replaceAll('&amp;', '&');

    if (s.startsWith('//')) s = 'https:$s';

    if (s.startsWith('http%3A') || s.startsWith('https%3A')) {
      try {
        s = Uri.decodeComponent(s);
      } catch (_) {}
    }
    return s;
  }

  /// Devolve o manifesto puro, ou null se a string nao for midia limpa.
  static String? extractMedia(String raw) {
    final String s = unescape(raw);
    if (s.isEmpty) return null;

    final Uri? outer = Uri.tryParse(s);
    if (outer != null && outer.queryParameters.isNotEmpty) {
      for (final String key in unwrapKeys) {
        final String? inner = outer.queryParameters[key];
        if (inner == null || inner.isEmpty) continue;
        final String decoded = unescape(inner);
        if (decoded.startsWith('http') && isMedia(decoded) && !isAd(decoded)) {
          return _strip(decoded);
        }
      }
    }

    if (!s.startsWith('http')) return null;
    if (isAd(s)) return null;
    if (!isMedia(s)) return null;
    return _strip(s);
  }

  /// Remove rastreadores e mantem apenas o que o CDN exige.
  static String _strip(String url) {
    final Uri? uri = Uri.tryParse(url);
    if (uri == null) return url;

    final List<String> keep = <String>[];
    uri.queryParameters.forEach((String k, String v) {
      final String key = k.toLowerCase();
      if (trackingKeys.contains(key)) return;
      if (keepKeys.contains(key) || !key.startsWith('utm')) {
        keep.add('${Uri.encodeQueryComponent(k)}=${Uri.encodeQueryComponent(v)}');
      }
    });

    final String base = '${uri.scheme}://${uri.authority}${uri.path}';
    return keep.isEmpty ? base : '$base?${keep.join('&')}';
  }

  /// Maior pontuacao = mais provavel de ser o conteudo principal.
  static int mediaScore(String url) {
    final String u = url.toLowerCase();
    int score = 0;
    if (u.contains('.m3u8')) score += 30;
    if (u.contains('master')) score += 8;
    if (u.contains('playlist')) score += 6;
    if (u.contains('1080')) score += 6;
    if (u.contains('720')) score += 3;
    for (final String mark in AppConfig.ptBrMarkers) {
      if (u.contains(mark)) {
        score += 12;
        break;
      }
    }
    for (final String mark in AppConfig.legendadoMarkers) {
      if (u.contains(mark)) {
        score += AppConfig.preferDublado ? -6 : 2;
        break;
      }
    }
    if (u.contains('trailer') || u.contains('preview')) score -= 10;
    return score;
  }

  /// Varre um JSON inteiro (recursivo) atras de midia limpa, ordenada.
  static List<String> extractAll(dynamic node) {
    final List<String> out = <String>[];

    void walk(dynamic n) {
      if (n is String) {
        final String? media = extractMedia(n);
        if (media != null && !out.contains(media)) out.add(media);
      } else if (n is List) {
        for (final dynamic item in n) {
          walk(item);
        }
      } else if (n is Map) {
        for (final dynamic value in n.values) {
          walk(value);
        }
      }
    }

    walk(node);
    out.sort((String a, String b) => mediaScore(b).compareTo(mediaScore(a)));
    return out;
  }

  /// URLs http que NAO sao midia (possiveis paginas de player).
  static List<String> extractPages(String body) {
    final List<String> out = <String>[];
    for (final RegExpMatch m in urlRe.allMatches(body)) {
      final String url = unescape(m.group(0)!);
      if (!url.startsWith('http')) continue;
      if (isAd(url)) continue;
      if (isMedia(url)) continue;
      if (!out.contains(url)) out.add(url);
    }
    return out;
  }

  static final RegExp urlRe = RegExp(r'''https?:(?:\\?/){2}[^\s"'<>\\]+''');
}