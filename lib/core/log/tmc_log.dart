import 'package:flutter/foundation.dart';

/// Log leve e seguro (nao imprime token/segredo - quem chama decide).
/// Usa debugPrint para nao cair no lint `avoid_print`.
class TmcLog {
  TmcLog._();

  static const String _root = 'TMC';

  static void i(String tag, String message) =>
      debugPrint('[$_root][$tag] $message');

  static void w(String tag, String message) =>
      debugPrint('[$_root][$tag][AVISO] $message');

  static void e(String tag, String message) =>
      debugPrint('[$_root][$tag][ERRO] $message');

  /// host + path, sem query (que costuma carregar token).
  static String where(String url) {
    final Uri? u = Uri.tryParse(url);
    if (u == null) return url;
    return '${u.host}${u.path}';
  }
}
