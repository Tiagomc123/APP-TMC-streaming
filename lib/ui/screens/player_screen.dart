import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/app_config.dart';
import '../../core/ui/screen_mode.dart';
import '../../data/models/media_ref.dart';
import '../../data/models/resolved_stream.dart';
import '../../services/progress_service.dart';
import '../../services/stream/url_sanitizer.dart';
import '../../services/stream/video_resolver_service.dart';
import '../widgets/custom_video_player.dart';
import 'web_player_screen.dart';

bool usesWebPlayerFallback(ResolvedStream stream) => !stream.playable;

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
  Duration _lastPosition = Duration.zero;
  Duration _lastDuration = Duration.zero; // TMC-FIX v1

  @override
  void initState() {
    super.initState();
    _stream = widget.stream;
    _usedProviders.add(widget.stream.providerId);
    unawaited(_enterLandscape());
  }

  // TMC-FIX v1: fila unica (ver ScreenMode).
  Future<void> _enterLandscape() => ScreenMode.landscape();

  /// Chamado pelo player quando a fonte morre: pede outra, excluindo as usadas.
  Future<ResolvedStream?> _fallback() async {
    final ResolvedStream? alt = await widget.resolver.resolve(
      widget.ref,
      force: true,
      exclude: _usedProviders,
    );
    if (alt != null) {
      _usedProviders.add(alt.providerId);
      if (mounted) setState(() => _stream = alt);
    }
    return alt;
  }

  void _useNative(String url) {
    final String clean = UrlSanitizer.extractMedia(url) ?? url;
    final Uri media = Uri.parse(clean);
    final bool isHls = media.path.toLowerCase().endsWith('.m3u8');
    setState(() {
      _stream = ResolvedStream(
        url: media,
        kind: isHls ? StreamKind.hls : StreamKind.mp4,
        providerId: 'web',
        providerLabel: 'Player nativo',
        headers: <String, String>{
          'User-Agent': AppConfig.userAgent,
          'Referer': (_stream.embedPage ?? _stream.url).toString(),
        },
      );
    });
  }

  @override
  void dispose() {
    // TMC-FIX v1: orientacao + UI mode na mesma fila do trailer/player.
    unawaited(ScreenMode.portrait());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (usesWebPlayerFallback(_stream)) {
      return WebPlayerScreen(
        url: _stream.embedPage ?? _stream.url,
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
          _lastDuration = d;
          unawaited(ProgressService.save(widget.ref, p, d));
        },
        onCompleted: () {
          unawaited(ProgressService.complete(widget.ref));
        },
        onNeedFallback: _fallback,
        onExit: () {
          // TMC-FIX v1: antes gravava _lastPosition como DURACAO, o que
          // marcava o titulo como concluido e o removia de "continuar
          // assistindo". Agora usa a duracao real vista pelo player.
          final Duration dur = _lastDuration > Duration.zero
              ? _lastDuration
              : _lastPosition;
          unawaited(ProgressService.save(widget.ref, _lastPosition, dur));
        },
      ),
    );
  }
}
