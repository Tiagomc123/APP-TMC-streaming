// =============================================================================
//  TMC - Configuracao central (v3 "pure API")
//
//  Nenhuma pagina HTML e interpretada pelo usuario: todo provedor entrega
//  JSON com a URL direta do manifesto (.m3u8 / .mp4).
// =============================================================================
import 'package:flutter/foundation.dart';

class AppConfig {
  AppConfig._();

  // ------------------------- TMDB via proxy Supabase -------------------------
  static const String tmdbProxyBase =
      'https://xjqdiulxrprxegfrufyf.supabase.co/functions/v1/tmdb-proxy';
  static const String externalSourcesBase =
      'https://xjqdiulxrprxegfrufyf.supabase.co/functions/v1/tmc-sources';
  static const String supabasePublishableKey =
      'sb_publishable_XyCk8TPrdGOzUrrr-59PpQ__dBWOFb9';
  static const String tmdbImageBase = 'https://image.tmdb.org/t/p';

  // ------------------------------ Identidade HTTP ----------------------------
  static const String uaMobile =
      'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36';

  static const String uaTv =
      'Mozilla/5.0 (Linux; Android 11; SHIELD Android TV) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';

  static const String uaSamsung =
      'Mozilla/5.0 (Linux; Android 13; SM-S911B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36';

  static const String uaDesktop =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';

  static const String uaMac =
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';

  /// UA usado nas requisicoes de API (rotativo, anti-fingerprint).
  static const List<String> uaPool = <String>[uaMobile, uaSamsung, uaDesktop, uaMac];

  /// UA usado no PLAYER. Mistura Chrome + marcador ExoPlayer, que e o que os
  /// CDNs de terceiros esperam de um aparelho Android/TV Box.
  static const String uaPlayer =
      'Mozilla/5.0 (Linux; Android 11; TMC Player) AppleWebKit/537.36 (KHTML, like Gecko) ExoPlayerLib/2.19.1 TMC/1.0.4';

  static const String acceptHtml =
      'text/html,application/xhtml+xml,application/xml;q=0.9,application/json;q=0.8,*/*;q=0.8';
  static const String acceptJson = 'application/json, text/plain, */*';
  static const String acceptLang = 'pt-BR,pt;q=0.9,en-US;q=0.8,en;q=0.7';

  static bool tvMode = false;
  static bool get isTv => tvMode;

  static int _uaIndex = 0;
  static String userAgent = uaMobile;

  static void useTvUserAgent() {
    tvMode = true;
    userAgent = uaTv;
  }

  static void rotateUserAgent() {
    if (tvMode) {
      userAgent = uaTv;
      return;
    }
    _uaIndex = (_uaIndex + 1) % uaPool.length;
    userAgent = uaPool[_uaIndex];
  }

  /// Headers entregues ao player nativo. Referer/Origin sao obrigatorios em
  /// boa parte dos CDNs (sem eles: 403 e tela preta).
  static Map<String, String> playerHeaders({String? referer, String? origin}) =>
      <String, String>{
        'User-Agent': uaPlayer,
        'Accept': '*/*',
        'Accept-Language': acceptLang,
        if (referer != null && referer.isNotEmpty) 'Referer': referer,
        if (origin != null && origin.isNotEmpty) 'Origin': origin,
      };

  // --------------------------- Preferencia de audio --------------------------
  /// Ligado pelo filtro de Idioma. Quando falso, o dublado continua na frente
  /// mas o legendado perde apenas 1 ponto de prioridade.
  static bool preferDublado = true;

  static const List<String> ptBrMarkers = <String>[
    'dublado', 'dublagem', 'dubla', 'pt-br', 'pt_br', 'ptbr', 'portugues',
    'portuguÃªs', 'brasil', 'brazil', 'nacional', 'dual', '_pt_', '/pt/',
  ];

  static const List<String> legendadoMarkers = <String>[
    'legendado', 'legenda', 'subtitle', '_sub', '/sub/',
  ];

  static const List<String> ptBrLanguages = <String>['pt', 'pt-br', 'pt_br', 'por', 'pob'];

  // ----------------------------- Bases de origem -----------------------------
  static const List<String> superflixBases = <String>[
    'https://superflixapi.fun',
    'https://superflixapi.pro',
    'https://superflixapi.sbs',
    'https://superflixapi.top',
    'https://superflixapi.online',
    'https://superflixapi.xyz',
  ];

  /// Fallback por id, usado quando o endpoint de fontes do Supabase falha.
  static const Map<String, List<String>> fallbackBases = <String, List<String>>{
    'superflix_api': superflixBases,
    'vidlink': <String>['https://vidlink.pro'],
    'warezcdn': <String>['https://warezcdn.com', 'https://warezcdn.net'],
    'pontofinal': <String>['https://pontofinal.org'],
  };

  static List<String> fallbackFor(String id) => fallbackBases[id] ?? const <String>[];

  // --------------------------------- Resolver --------------------------------
  static const Duration resolveTimeout = Duration(seconds: 26);
  static const Duration probeTimeout = Duration(seconds: 8);
  static const Duration streamCacheTtl = Duration(minutes: 30);
  static const int maxIframeDepth = 2;
  static const int maxCandidates = 16;

  // ---------------------------------- Cache ----------------------------------
  static const int cacheMaxMb = 320;
  static const Duration cacheMaxAge = Duration(days: 7);

  static bool get isWeb => kIsWeb;
}