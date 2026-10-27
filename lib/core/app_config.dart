// =============================================================================
//  TMC - Configuracao central
//
//  Tudo que muda entre ambientes (bases de origem, User-Agent, limites de
//  cache e marcadores de idioma) fica aqui, em um unico lugar tipado.
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
  // Chrome Android REAL, sem o marcador 'wv'. O 'wv' faz o Cloudflare tratar
  // como bot e o YouTube devolver erro 153.
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

  /// Pool usado na rotacao de identidade entre provedores. Sites de terceiros
  /// bloqueiam por fingerprint: alternar reduz a chance de tela de verificacao.
  static const List<String> uaPool = <String>[uaMobile, uaSamsung, uaDesktop, uaMac];

  static const String acceptHtml =
      'text/html,application/xhtml+xml,application/xml;q=0.9,application/json;q=0.8,*/*;q=0.8';
  static const String acceptJson = 'application/json, text/plain, */*';
  static const String acceptLang = 'pt-BR,pt;q=0.9,en-US;q=0.8,en;q=0.7';

  static bool tvMode = false;
  static bool get isTv => tvMode;

  static int _uaIndex = 0;

  /// Trocado para UA de TV no boot quando roda em Android TV.
  static String userAgent = uaMobile;

  static void useTvUserAgent() {
    tvMode = true;
    userAgent = uaTv;
  }

  /// Gira o User-Agent. Em TV mantem o UA de TV (sites checam leanback).
  static void rotateUserAgent() {
    if (tvMode) {
      userAgent = uaTv;
      return;
    }
    _uaIndex = (_uaIndex + 1) % uaPool.length;
    userAgent = uaPool[_uaIndex];
  }

  // --------------------------- Preferencia de audio --------------------------
  /// Marcadores de conteudo dublado / nacional (prioridade absoluta).
  static const List<String> ptBrMarkers = <String>[
    'dublado', 'dublagem', 'dubla', 'pt-br', 'pt_br', 'ptbr', 'portugues',
    'portuguÃªs', 'brasil', 'brazil', 'nacional', 'dual', '_pt_', '/pt/',
  ];

  /// Marcadores de conteudo legendado (usados como desempate).
  static const List<String> legendadoMarkers = <String>[
    'legendado', 'legenda', 'subtitle', '_sub', '/sub/',
  ];

  /// Linguagens aceitas como PT-BR na selecao de faixa de audio do HLS.
  static const List<String> ptBrLanguages = <String>['pt', 'pt-br', 'pt_br', 'por', 'pob'];

  // ----------------------------- Bases de origem -----------------------------
  /// Fallbacks embutidos: o site troca de dominio com frequencia.
  static const List<String> pobreflixBases = <String>[
    'https://pobreflixhd.sbs',
    'https://pobreflixhd.top',
    'https://pobreflixhd.online',
    'https://pobreflixhd.tv',
  ];
  /// Bases do VidLink (API JSON publica -> HLS direto).
  static const List<String> vidlinkBases = <String>['https://vidlink.pro','https://vidlink.to'];
  /// Preferencia de audio: true = dublado (PT-BR) primeiro.
  static bool preferDublado = true;

  static const List<String> superflixBases = <String>[
    'https://superflixapi.fun',
    'https://superflixapi.pro',
  ];

  // --------------------------------- Resolver --------------------------------
  static const Duration resolveTimeout = Duration(seconds: 28);
  static const Duration probeTimeout = Duration(seconds: 9);
  static const Duration streamCacheTtl = Duration(minutes: 30);
  static const int maxIframeDepth = 3;
  static const int maxCandidates = 16;
  static const int maxRedirectHops = 3;
  static const int maxPagesPerTitle = 14;

  // ---------------------------------- Cache ----------------------------------
  /// Teto de cache de rede do player (Android TV Box costuma ter pouco disco).
  static const int cacheMaxMb = 320;
  static const Duration cacheMaxAge = Duration(days: 7);

  static bool get isWeb => kIsWeb;
}