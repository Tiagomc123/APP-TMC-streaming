import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_config.dart';
import '../../data/models/media_ref.dart';
import '../../data/models/resolved_stream.dart';
import '../../services/progress_service.dart';
import '../../services/stream/video_resolver_service.dart';
import '../widgets/custom_video_player.dart';
import 'web_player_screen.dart';

/// Decide em runtime entre player nativo (media_kit) e navegador interno.
///
/// REGRA CENTRAL: se o stream nao for arquivo (.m3u8/.mp4), o libmpv NAO
/// consegue abrir (era a causa da tela preta sem erro). Nesse caso vai para
/// a WebView, que toca a pagina normalmente.
class PlayerScreen extends StatefulWidget {
  const PlayerScreen({
    super.key,
    required this.stream,
    required this.ref,
    required this.resolver,
  });

  final ResolvedStream stream;
  final MediaRef ref;
  final VideoResolverService resolver;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  final Set<String> _usedProviders = <String>{};
  late ResolvedStream _stream;
  late bool _webMode;
  String _webUrl = '';
  Duration _lastPosition = Duration.zero;

  @override
  void initState() {
    super.initState();
    _stream = widget.stream;
    _usedProviders.add(widget.stream.providerId);
    _webMode = !_stream.playable;
    _webUrl = _stream.playable ? '' : _stream.url.toString();
    unawaited(_landscape());
  }

  Future<void> _landscape() async {
    await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  @override
  void dispose() {
    unawaited(SystemChrome.setPreferredOrientations(<DeviceOrientation>[
      DeviceOrientation.portraitUp,
    ]));
    super.dispose();
  }

  Future<ResolvedStream?> _fallback() async {
    final ResolvedStream? alt = await widget.resolver.resolve(
      widget.ref,
      force: true,
      exclude: _usedProviders,
    );
    if (alt != null) {
      _usedProviders.add(alt.providerId);
      if (mounted) {
        setState(() {
          _stream = alt;
          _webMode = !alt.playable;
          _webUrl = alt.playable ? '' : alt.url.toString();
        });
      }
    }
    return alt;
  }

  /// O navegador capturou um .m3u8/.mp4 real: troca para o player nativo.
  void _useNative(String url) {
    setState(() {
      _stream = ResolvedStream(
        url: Uri.parse(url),
        kind: url.contains('.m3u8') ? StreamKind.hls : StreamKind.mp4,
        providerId: 'web',
        providerLabel: 'Navegador',
        headers: <String, String>{
          'User-Agent': AppConfig.userAgent,
          if (_webUrl.isNotEmpty) 'Referer': _webUrl,
        },
      );
      _webMode = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_webMode) {
      return WebPlayerScreen(
        url: Uri.parse(_webUrl),
        title: widget.ref.display,
        onUseNative: _useNative,
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: CustomVideoPlayer(
        stream: _stream,
        title: widget.ref.title,
        subtitle: widget.ref.isTv
            ? 'T${widget.ref.season} E${widget.ref.episode} - ${_stream.providerLabel}'
            : _stream.providerLabel,
        startAt: ProgressService.startAt(widget.ref),
        onProgress: (Duration p, Duration d) {
          _lastPosition = p;
          unawaited(ProgressService.save(widget.ref, p, d));
        },
        onCompleted: () => unawaited(ProgressService.complete(widget.ref)),
        onNeedFallback: _fallback,
        onExit: () {
          unawaited(ProgressService.save(widget.ref, _lastPosition, _lastPosition));
        },
      ),
    );
  }
}