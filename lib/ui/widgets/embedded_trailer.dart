import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

import '../../core/focus/dpad.dart';

/// =============================================================================
///  TRAILER EMBUTIDO + CONTROLE DE ROTACAO
///
///  100% dentro da pagina de detalhes. Sem url_launcher, sem abrir o app do
///  YouTube, sem WebView "nudge".
///
///  O botao "GIRAR TELA" forca o app para paisagem por meio de
///  `SystemChrome.setPreferredOrientations`, ignorando a rotacao automatica
///  do aparelho, e devolve o retrato quando o trailer e fechado.
///
///  A leitura do player e feita de forma TOLERANTE A VERSAO do pacote:
///   - `autoPlay` e `startSeconds` vao no factory (nao em YoutubePlayerParams);
///   - o estado vem do `stream` de YoutubePlayerValue, lido por campo;
///   - play/pause/mute/unMute/close sao chamados por despacho dinamico.
/// =============================================================================
class EmbeddedTrailer extends StatefulWidget {
  const EmbeddedTrailer({
    super.key,
    required this.videoKey,
    required this.title,
    this.autoPlay = false,
    this.onClose,
  });

  final String videoKey;
  final String title;
  final bool autoPlay;
  final VoidCallback? onClose;

  @override
  State<EmbeddedTrailer> createState() => _EmbeddedTrailerState();
}

class _EmbeddedTrailerState extends State<EmbeddedTrailer> {
  YoutubePlayerController? _ctl;
  bool _playing = false;
  bool _muted = false;
  bool _rotated = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  StreamSubscription<YoutubePlayerValue>? _subscription;

  @override
  void initState() {
    super.initState();
    _create();
  }

  void _create() {
    _ctl = YoutubePlayerController.fromVideoId(
      videoId: widget.videoKey,
      autoPlay: widget.autoPlay,
      params: const YoutubePlayerParams(
        showControls: true,
        showFullscreenButton: true,
        strictRelatedVideos: true,
        privacyEnhancedMode: true,
      ),
    );
    _subscription = _ctl!.stream.listen(_onValue);
  }

  /// Le o estado do player sem depender do nome exato dos campos.
  void _onValue(dynamic value) {
    if (!mounted || value == null) return;

    final Duration? pos = _readDuration(value, true);
    final Duration? dur = _readDuration(value, false);
    final bool? playing = _readPlaying(value);

    if (pos == null && dur == null && playing == null) return;

    setState(() {
      if (pos != null) _position = pos;
      if (dur != null) _duration = dur;
      if (playing != null) _playing = playing;
    });
  }

  Duration? _readDuration(dynamic value, bool position) {
    try {
      final dynamic raw = position ? value.position : value.duration;
      if (raw is Duration) return raw;
      if (raw is num) return Duration(milliseconds: (raw * 1000).round());
    } catch (_) {}
    return null;
  }

  bool? _readPlaying(dynamic value) {
    try {
      final dynamic state = value.playerState;
      if (state != null) return state.toString().endsWith('playing');
    } catch (_) {}
    try {
      final dynamic flag = value.isPlaying;
      if (flag is bool) return flag;
    } catch (_) {}
    return null;
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _ctl?.close();
    if (_rotated) {
      unawaited(_forcePortrait());
    }
    super.dispose();
  }

  // ------------------------------ rotacao de tela ----------------------------
  Future<void> _forceLandscape() async {
    await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  Future<void> _forcePortrait() async {
    await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
      DeviceOrientation.portraitUp,
    ]);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  Future<void> _toggleRotation() async {
    final bool next = !_rotated;
    if (next) {
      await _forceLandscape();
    } else {
      await _forcePortrait();
    }
    if (mounted) setState(() => _rotated = next);
  }

  void _toggle() {
    final bool next = !_playing;
    if (next) {
      _ctl?.playVideo();
    } else {
      _ctl?.pauseVideo();
    }
    setState(() => _playing = next);
  }

  void _toggleMute() {
    final bool next = !_muted;
    if (next) {
      _ctl?.mute();
    } else {
      _ctl?.unMute();
    }
    setState(() => _muted = next);
  }

  void _expand() {
    _ctl?.pauseVideo();
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        opaque: true,
        transitionDuration: const Duration(milliseconds: 200),
        pageBuilder: (_, _, _) => _FullscreenTrailer(
          videoKey: widget.videoKey,
          title: widget.title,
          startAt: _position,
          muted: _muted,
        ),
      ),
    );
  }

  String _fmt(Duration d) =>
      '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final YoutubePlayerController? ctl = _ctl;
    if (ctl == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: YoutubePlayerControllerProvider(
            controller: ctl,
            child: YoutubePlayer(controller: ctl, aspectRatio: 16 / 9),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            TvButton(
              label: _playing ? 'PAUSAR' : 'REPRODUZIR',
              icon: _playing ? Icons.pause : Icons.play_arrow,
              primary: true,
              onPressed: _toggle,
            ),
            TvButton(
              label: 'GIRAR TELA',
              icon: _rotated ? Icons.stay_current_portrait : Icons.screen_rotation,
              onPressed: () => unawaited(_toggleRotation()),
            ),
            TvButton(
              label: _muted ? 'SOM ON' : 'MUDO',
              icon: _muted ? Icons.volume_up : Icons.volume_off,
              onPressed: _toggleMute,
            ),
            TvButton(
              label: 'TELA CHEIA',
              icon: Icons.fullscreen,
              onPressed: _expand,
            ),
            if (widget.onClose != null)
              TvButton(
                label: 'FECHAR',
                icon: Icons.close,
                onPressed: widget.onClose!,
              ),
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Text(
                '${_fmt(_position)} / ${_fmt(_duration)}',
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Tela cheia reaproveitando o mesmo video, retomando de onde parou.
/// Entra e sai do modo paisagem sozinha.
class _FullscreenTrailer extends StatefulWidget {
  const _FullscreenTrailer({
    required this.videoKey,
    required this.title,
    required this.startAt,
    required this.muted,
  });

  final String videoKey;
  final String title;
  final Duration startAt;
  final bool muted;

  @override
  State<_FullscreenTrailer> createState() => _FullscreenTrailerState();
}

class _FullscreenTrailerState extends State<_FullscreenTrailer> {
  late final YoutubePlayerController _ctl;

  @override
  void initState() {
    super.initState();
    _ctl = YoutubePlayerController.fromVideoId(
      videoId: widget.videoKey,
      autoPlay: true,
      startSeconds: widget.startAt.inSeconds.toDouble(),
      params: YoutubePlayerParams(
        mute: widget.muted,
        showControls: true,
        showFullscreenButton: true,
        strictRelatedVideos: true,
        privacyEnhancedMode: true,
      ),
    );
    unawaited(_enterLandscape());
  }

  Future<void> _enterLandscape() async {
    await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    _ctl.close();
    unawaited(SystemChrome.setPreferredOrientations(<DeviceOrientation>[
      DeviceOrientation.portraitUp,
    ]));
    unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.escape): _CloseTrailerIntent(),
        SingleActivator(LogicalKeyboardKey.goBack): _CloseTrailerIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          _CloseTrailerIntent: CallbackAction<_CloseTrailerIntent>(
            onInvoke: (_) {
              Navigator.of(context).pop();
              return null;
            },
          ),
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            backgroundColor: Colors.black,
            body: Center(
              child: YoutubePlayerControllerProvider(
                controller: _ctl,
                child: YoutubePlayer(controller: _ctl, aspectRatio: 16 / 9),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CloseTrailerIntent extends Intent {
  const _CloseTrailerIntent();
}