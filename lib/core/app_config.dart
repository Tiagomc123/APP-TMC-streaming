// =============================================================================
//  TMC - Configuracao central
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
  // Chrome Android REAL, sem o marcador 'wv'.
  // O 'wv' faz o Cloudflare tratar como bot e o YouTube devolver erro 153.
  static const String uaMobile =
      'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36';

  static const String uaTv =
      'Mozilla/5.0 (Linux; Android 11; SHIELD Android TV) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';

  static const String acceptHtml =
      'text/html,application/xhtml+xml,application/xml;q=0.9,application/json;q=0.8,*/*;q=0.8';
  static const String acceptJson = 'application/json, text/plain, */*';
  static const String acceptLang = 'pt-BR,pt;q=0.9,en-US;q=0.8,en;q=0.7';

  /// Trocado para UA de TV no boot quando roda em Android TV.
  static String userAgent = uaMobile;

  // --------------------------------- Resolver --------------------------------
  static const Duration resolveTimeout = Duration(seconds: 28);
  static const Duration probeTimeout = Duration(seconds: 9);
  static const Duration streamCacheTtl = Duration(minutes: 30);
  static const int maxIframeDepth = 3;
  static const int maxCandidates = 16;

  static bool get isWeb => kIsWeb;
}
