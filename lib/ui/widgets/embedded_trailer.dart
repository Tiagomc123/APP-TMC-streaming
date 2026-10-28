import 'dart:async';

import 'package:flutter/material.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

import '../../core/focus/dpad.dart';
import '../../core/ui/screen_mode.dart';

/// =============================================================================
///  TRAILER EMBUTIDO + CONTROLE DE ROTACAO
///
///  100% dentro da pagina de detalhes. Sem url_launcher, sem abrir o app do
///  YouTube, sem WebView "nudge".
///
///  O botao "TELA CHEIA" abre o trailer em paisagem e mostra uma saida
///  persistente para voltar aos detalhes.
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
    this.autoPlay = false,
    this.onClose,
  });

  final String videoKey;
  final bool autoPlay;
  final VoidCallback? onClose;

  @override
  State<EmbeddedTrailer> createState() => _EmbeddedTrailerState();
}

class _EmbeddedTrailerState extends State<EmbeddedTrailer> {
  YoutubePlayerController? _ctl;
  bool _playing = false;
  bool _muted = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  // TMC-FIX v1
  Duration _lastPosTick = Duration.zero;
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
        // Mantem o trailer dentro dos detalhes para preservar a saida do app.
        showFullscreenButton: false,
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

    // TMC-FIX v1: a posicao muda varias vezes por segundo e cada setState
    // re-layouta a WebView do iframe. Atualiza a posicao no maximo a cada
    // 400 ms; duracao e estado de play continuam imediatos.
    final Duration now = Duration(
      milliseconds: DateTime.now().millisecondsSinceEpoch,
    );
    final bool posDue =
        (now - _lastPosTick).inMilliseconds >= 400 ||
        dur != null ||
        playing != null;

    setState(() {
      if (pos != null && posDue) {
        _position = pos;
        _lastPosTick = now;
      }
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
    super.dispose();
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

  Future<void> _expand() async {
    final bool resumePlayback = _playing;
    _ctl?.pauseVideo();
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => _FullscreenTrailer(
          videoKey: widget.videoKey,
          startAt: _position,
          muted: _muted,
          returnToLandscape:
              MediaQuery.orientationOf(context) == Orientation.landscape,
        ),
      ),
    );
    if (mounted && resumePlayback) _ctl?.playVideo();
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
        TrailerControls(
          playing: _playing,
          muted: _muted,
          positionLabel: '${_fmt(_position)} / ${_fmt(_duration)}',
          onTogglePlayback: _toggle,
          onToggleMute: _toggleMute,
          onFullscreen: () => unawaited(_expand()),
          onClose: widget.onClose,
        ),
      ],
    );
  }
}

/// Superfície de tela cheia com saída sempre visível, mesmo em paisagem.
/// Acoes do trailer sem rota de tela cheia.
class TrailerControls extends StatelessWidget {
  const TrailerControls({
    super.key,
    required this.playing,
    required this.muted,
    required this.positionLabel,
    required this.onTogglePlayback,
    required this.onToggleMute,
    required this.onFullscreen,
    this.onClose,
  });

  final bool playing;
  final bool muted;
  final String positionLabel;
  final VoidCallback onTogglePlayback;
  final VoidCallback onToggleMute;
  final VoidCallback onFullscreen;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        TvButton(
          label: playing ? 'PAUSAR' : 'REPRODUZIR',
          icon: playing ? Icons.pause : Icons.play_arrow,
          primary: true,
          onPressed: onTogglePlayback,
        ),
        TvButton(
          label: muted ? 'SOM ON' : 'MUDO',
          icon: muted ? Icons.volume_up : Icons.volume_off,
          onPressed: onToggleMute,
        ),
        TvButton(
          label: 'TELA CHEIA',
          icon: Icons.fullscreen,
          onPressed: onFullscreen,
        ),
        if (onClose != null)
          TvButton(label: 'FECHAR', icon: Icons.close, onPressed: onClose!),
        Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Text(
            positionLabel,
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
        ),
      ],
    );
  }
}

/// Tela cheia com saida sempre visivel sobre o player.
class TrailerFullscreenScaffold extends StatelessWidget {
  const TrailerFullscreenScaffold({
    super.key,
    required this.title,
    required this.player,
  });

  final String title;
  final Widget player;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            Center(child: player),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: <Widget>[
                      Flexible(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      FilledButton.icon(
                        onPressed: () => Navigator.of(context).maybePop(),
                        icon: const Icon(Icons.close),
                        label: const Text('FECHAR'),
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.red.shade700,
                          foregroundColor: Colors.white,
                          minimumSize: const Size(120, 48),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FullscreenTrailer extends StatefulWidget {
  const _FullscreenTrailer({
    required this.videoKey,
    required this.startAt,
    required this.muted,
    required this.returnToLandscape,
  });

  final String videoKey;
  final Duration startAt;
  final bool muted;
  final bool returnToLandscape;

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
        showFullscreenButton: false,
        strictRelatedVideos: true,
        privacyEnhancedMode: true,
      ),
    );
    unawaited(ScreenMode.landscape());
  }

  @override
  void dispose() {
    _ctl.close();
    unawaited(
      widget.returnToLandscape ? ScreenMode.landscape() : ScreenMode.portrait(),
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TrailerFullscreenScaffold(
      title: 'Trailer',
      player: YoutubePlayerControllerProvider(
        controller: _ctl,
        child: YoutubePlayer(controller: _ctl, aspectRatio: 16 / 9),
      ),
    );
  }
}
