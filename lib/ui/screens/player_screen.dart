import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/models/media_ref.dart';
import '../../data/models/resolved_stream.dart';
import '../../services/progress_service.dart';
import '../../services/stream/url_sanitizer.dart';
import '../../services/stream/video_resolver_service.dart';
import '../widgets/custom_video_player.dart';

/// Player 100% nativo. Recebe sempre um manifesto .m3u8/.mp4 sanitizado.
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

  @override
  void initState() {
    super.initState();
    _stream = _sanitize(widget.stream);
    _usedProviders.add(widget.stream.providerId);
    unawaited(_landscape());
  }

  /// Garante que nada de anuncio/rastreador chegue ao player.
  ResolvedStream _sanitize(ResolvedStream stream) {
    final String? clean = UrlSanitizer.extractMedia(stream.url.toString());
    if (clean == null || clean == stream.url.toString()) return stream;
    return stream.copyWith(url: Uri.parse(clean));
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
      if (mounted) setState(() => _stream = _sanitize(alt));
    }
    return alt;
  }

  @override
  Widget build(BuildContext context) {
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