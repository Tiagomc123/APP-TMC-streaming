import 'package:flutter/services.dart';

/// Fila serializada de mudancas de orientacao / modo de sistema.
///
/// Antes existiam 6 pontos independentes chamando
/// `setPreferredOrientations` + `setEnabledSystemUIMode` (trailer, tela cheia
/// do trailer, PlayerScreen, CustomVideoPlayer, WebPlayerScreen). Chamadas
/// concorrentes podiam chegar fora de ordem e deixar a orientacao errada.
/// Aqui tudo passa por uma unica fila: a ultima intencao vence, na ordem.
class ScreenMode {
  ScreenMode._();

  static Future<void> _chain = Future<void>.value();

  static Future<void> _run(Future<void> Function() action) {
    _chain = _chain.then((_) => action()).catchError((Object _) {});
    return _chain;
  }

  static const List<DeviceOrientation> _landscape = <DeviceOrientation>[
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ];
  static const List<DeviceOrientation> _portrait = <DeviceOrientation>[
    DeviceOrientation.portraitUp,
  ];

  static Future<void> landscape() => _run(() async {
    await SystemChrome.setPreferredOrientations(_landscape);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  });

  static Future<void> portrait() => _run(() async {
    await SystemChrome.setPreferredOrientations(_portrait);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  });

  /// So o modo de sistema, sem mexer na orientacao.
  static Future<void> immersive() => _run(() async {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  });

  static Future<void> edgeToEdge() => _run(() async {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  });
}
