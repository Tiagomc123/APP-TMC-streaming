// =====================================================================
//  TMC - Camada de embutir HTML REAL (somente Web).
//  <iframe> nativo: sem WebView, sem plugin, sem erro 153.
// =====================================================================

import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';

const bool kFrameWeb = true;

/// Container de embutir. Na Web e um <iframe> de verdade.
class TmcFrame extends StatefulWidget {
  final String url;
  const TmcFrame({super.key, required this.url});

  @override
  State<TmcFrame> createState() => _TmcFrameState();
}

class _TmcFrameState extends State<TmcFrame> {
  late final String _viewType;

  @override
  void initState() {
    super.initState();
    _viewType = 'tmc_iframe_${DateTime.now().microsecondsSinceEpoch}';
    final html.IFrameElement el = html.IFrameElement();
    el.src = widget.url;
    el.allowFullscreen = true;
    el.setAttribute('allow',
        'autoplay; fullscreen; encrypted-media; picture-in-picture; clipboard-write; accelerometer; gyroscope');
    el.setAttribute('allowfullscreen', 'true');
    el.setAttribute('frameborder', '0');
    el.setAttribute('scrolling', 'no');
    // manda o Referer (o YouTube exige referer valido -> evita erro 153)
    el.setAttribute('referrerpolicy', 'strict-origin-when-cross-origin');
    el.style.border = 'none';
    el.style.width = '100%';
    el.style.height = '100%';
    el.style.backgroundColor = '#000000';
    ui_web.platformViewRegistry.registerViewFactory(
      _viewType,
      (int viewId) => el,
    );
  }

  @override
  Widget build(BuildContext context) => HtmlElementView(viewType: _viewType);
}

/// Abre a URL numa aba real do navegador (sem iframe, sem gate de origem).
void abrirExterno(String url) {
  try {
    html.window.open(url, '_blank');
  } catch (_) {}
}