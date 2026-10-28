import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../../core/app_config.dart';
import '../../core/focus/dpad.dart';
import '../../core/ui/screen_mode.dart';

/// =============================================================================
///  NAVEGADOR INTERNO ("modo web")
///
///  Entra quando a extracao por HTTP devolve uma PAGINA em vez de arquivo
///  (.m3u8/.mp4) â€” que era a causa da tela preta sem erro, porque o libmpv
///  nao toca HTML.
///
///  Aqui a pagina e "hackeada" em runtime:
///   - window.open passa a navegar na propria WebView (mata popup/pop-under);
///   - navegacao de topo para hosts de anuncio e bloqueada;
///   - overlays fixos que cobrem o video sao removidos;
///   - o play e clicado automaticamente;
///   - o <video>.src capturado volta para o Flutter ("PLAYER NATIVO").
///
///  A barra superior e SEMPRE visivel: nunca da para ficar preso.
/// =============================================================================
class WebPlayerScreen extends StatefulWidget {
  const WebPlayerScreen({
    super.key,
    required this.url,
    this.title = '',
    this.onUseNative,
  });

  final Uri url;
  final String title;
  final ValueChanged<String>? onUseNative;

  @override
  State<WebPlayerScreen> createState() => _WebPlayerScreenState();
}

class _WebPlayerScreenState extends State<WebPlayerScreen> {
  late final WebViewController _ctl;
  bool _loading = true;
  bool _landscape = true;
  String? _captured;

  static const List<String> _adHosts = <String>[
    'doubleclick',
    'googlesyndication',
    'amazon-adsystem',
    'popads',
    'popcash',
    'propeller',
    'onclickads',
    'onclck',
    'adcash',
    'adsterra',
    'monetag',
    'highperformanceformat',
    'hilltopads',
    'admaven',
    'ouo.io',
    'linkvertise',
    'adf.ly',
    'vidoomy',
    'pubads',
    'mgid',
    'taboola',
    'outbrain',
    'adservice',
  ];

  static const String _hack = r'''
(function () {
  if (window.__tmcHack) return;
  window.__tmcHack = true;
  try {
    window.open = function (u) {
      if (u && typeof u === 'string') { try { location.href = u; } catch (e) {} }
      return window;
    };
  } catch (e) {}
  function kill() {
    var sel = 'div[id*=ad],div[class*=ad-],div[class*=-ad],div[id*=pop],div[class*=pop],div[id*=overlay],div[class*=overlay],div[class*=banner]';
    var nodes = document.querySelectorAll(sel);
    for (var i = 0; i < nodes.length; i++) {
      var n = nodes[i];
      if (!n || !n.getBoundingClientRect) continue;
      var s = window.getComputedStyle(n);
      if (!s || s.position !== 'fixed') continue;
      if (n.querySelector && n.querySelector('video,iframe')) continue;
      if (n.offsetHeight > window.innerHeight * 0.6) continue;
      n.style.display = 'none';
    }
  }
  function play() {
    var v = document.querySelector('video');
    if (v) { try { var p = v.play(); if (p && p.catch) p.catch(function () {}); } catch (e) {} }
    var b = document.querySelector('.play,.btn-play,[class*=play-button],[id*=play-button],button[class*=play],a[class*=play]');
    if (b && b.click) { try { b.click(); } catch (e) {} }
  }
  function report() {
    var v = document.querySelector('video');
    if (v && v.src && v.src.indexOf('blob:') !== 0) {
      window.TmcBridge.postMessage(JSON.stringify({ type: 'src', url: v.src }));
    }
  }
  kill(); play();
  setInterval(function () { kill(); report(); }, 1500);
  setTimeout(play, 900); setTimeout(play, 2200); setTimeout(play, 4500);
})();
''';

  @override
  void initState() {
    super.initState();
    unawaited(_applyOrientation(true));

    _ctl = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..setUserAgent(AppConfig.userAgent)
      ..addJavaScriptChannel('TmcBridge', onMessageReceived: _onBridge)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (String _) {
            if (mounted) setState(() => _loading = true);
          },
          onPageFinished: (String _) {
            if (mounted) setState(() => _loading = false);
            unawaited(_inject());
          },
          onNavigationRequest: _onRequest,
        ),
      );

    if (_ctl.platform is AndroidWebViewController) {
      unawaited(
        (_ctl.platform as AndroidWebViewController)
            .setMediaPlaybackRequiresUserGesture(false),
      );
    }

    unawaited(_ctl.loadRequest(widget.url));
  }

  @override
  void dispose() {
    unawaited(_applyOrientation(false));
    super.dispose();
  }

  // TMC-FIX v1: fila unica (ver ScreenMode).
  Future<void> _applyOrientation(bool landscape) =>
      landscape ? ScreenMode.landscape() : ScreenMode.portrait();

  Future<void> _inject() async {
    try {
      await _ctl.runJavaScript(_hack);
    } catch (_) {}
  }

  void _onBridge(JavaScriptMessage message) {
    try {
      final dynamic data = jsonDecode(message.message);
      if (data is! Map) return;
      if (data['type'] != 'src') return;
      final String url = (data['url'] ?? '').toString();
      if (url.isEmpty || !url.startsWith('http')) return;
      if (!url.contains('.m3u8') && !url.contains('.mp4')) return;
      if (_captured == url) return;
      if (mounted) setState(() => _captured = url);
    } catch (_) {}
  }

  NavigationDecision _onRequest(NavigationRequest request) {
    if (!request.isMainFrame) return NavigationDecision.navigate;
    final String url = request.url.toLowerCase();
    if (url.startsWith('about:blank') ||
        url.startsWith('data:') ||
        url.startsWith('blob:')) {
      return NavigationDecision.navigate;
    }
    for (final String host in _adHosts) {
      if (url.contains(host)) return NavigationDecision.prevent;
    }
    return NavigationDecision.navigate;
  }

  Future<void> _back() async {
    try {
      if (await _ctl.canGoBack()) {
        await _ctl.goBack();
        return;
      }
    } catch (_) {}
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _toggleRotation() async {
    _landscape = !_landscape;
    await _applyOrientation(_landscape);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? _) {
        if (!didPop) unawaited(_back());
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Column(
            children: <Widget>[
              _bar(),
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    WebViewWidget(controller: _ctl),
                    if (_loading)
                      const ColoredBox(
                        color: Color(0xCC000000),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              CircularProgressIndicator(),
                              SizedBox(height: 14),
                              Text(
                                'Abrindo o player do site...',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bar() {
    return Container(
      color: const Color(0xFF0B0F1A),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Row(
        children: <Widget>[
          TvButton(
            label: 'VOLTAR',
            icon: Icons.arrow_back,
            autofocus: true,
            onPressed: () => unawaited(_back()),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              widget.title.isEmpty ? 'Modo web' : widget.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ),
          if (_captured != null)
            TvButton(
              label: 'PLAYER NATIVO',
              icon: Icons.high_quality,
              primary: true,
              onPressed: () => widget.onUseNative?.call(_captured!),
            ),
          const SizedBox(width: 8),
          TvButton(
            label: 'GIRAR',
            icon: Icons.screen_rotation,
            onPressed: () => unawaited(_toggleRotation()),
          ),
          const SizedBox(width: 8),
          TvButton(
            label: 'RECARREGAR',
            icon: Icons.refresh,
            onPressed: () => unawaited(_ctl.reload()),
          ),
        ],
      ),
    );
  }
}
