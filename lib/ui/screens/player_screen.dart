import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/models/media_ref.dart';
import '../../data/models/resolved_stream.dart';
import '../../services/progress_service.dart';
import '../../services/stream/video_resolver_service.dart';
import '../widgets/custom_video_player.dart';

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
    _stream = widget.stream;
    _usedProviders.add(widget.stream.providerId);
    unawaited(_enterLandscape());
  }

  Future<void> _enterLandscape() async {
    await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

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

  @override
  void dispose() {
    unawaited(SystemChrome.setPreferredOrientations(<DeviceOrientation>[
      DeviceOrientation.portraitUp,
    ]));
    super.dispose();
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
        onCompleted: () {
          unawaited(ProgressService.complete(widget.ref));
        },
        onNeedFallback: _fallback,
        onExit: () {
          unawaited(ProgressService.save(
            widget.ref,
            _lastPosition,
            _lastPosition,
          ));
        },
      ),
    );
  }
}