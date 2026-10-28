import 'dart:async';

import 'package:flutter/material.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

import '../../core/focus/dpad.dart';
import '../../core/log/tmc_log.dart';
import '../../core/ui/screen_mode.dart';

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
  bool _rotated = false;
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

  // TMC-FIX v1: re-sincroniza o estado do botao com a orientacao real.
  // O trailer nao e descartado quando o usuario abre o player, entao
  // _rotated ficava obsoleto depois de voltar do PlayerScreen.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final bool paisagem =
        MediaQuery.of(context).orientation == Orientation.landscape;
    if (paisagem != _rotated) _rotated = paisagem;
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
    // TMC-FIX v1: restaura retrato + UI mode numa unica chamada serializada.
    if (_rotated) {
      unawaited(ScreenMode.portrait());
      TmcLog.i('trailer', 'dispose -> retrato restaurado');
    }
    super.dispose();
  }

  // ------------------------------ rotacao de tela ----------------------------
  // TMC-FIX v1: tudo passa pela fila do ScreenMode para nao competir com o
  // player, com a tela cheia do trailer nem com o PlayerScreen.
  Future<void> _forceLandscape() => ScreenMode.landscape();

  Future<void> _forcePortrait() => ScreenMode.portrait();

  Future<void> _toggleRotation() async {
    final bool next = !_rotated;
    if (mounted) setState(() => _rotated = next);
    try {
      if (next) {
        await _forceLandscape();
      } else {
        await _forcePortrait();
      }
    } catch (err) {
      TmcLog.w('trailer', 'falha ao trocar orientacao: $err');
    }
    TmcLog.i('trailer', 'orientacao -> ${next ? 'paisagem' : 'retrato'}');
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
          rotated: _rotated,
          positionLabel: '${_fmt(_position)} / ${_fmt(_duration)}',
          onTogglePlayback: _toggle,
          onToggleRotation: () => unawaited(_toggleRotation()),
          onToggleMute: _toggleMute,
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
    required this.rotated,
    required this.positionLabel,
    required this.onTogglePlayback,
    required this.onToggleRotation,
    required this.onToggleMute,
    this.onClose,
  });

  final bool playing;
  final bool muted;
  final bool rotated;
  final String positionLabel;
  final VoidCallback onTogglePlayback;
  final VoidCallback onToggleRotation;
  final VoidCallback onToggleMute;
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
          label: 'GIRAR TELA',
          icon: rotated ? Icons.stay_current_portrait : Icons.screen_rotation,
          onPressed: onToggleRotation,
        ),
        TvButton(
          label: muted ? 'SOM ON' : 'MUDO',
          icon: muted ? Icons.volume_up : Icons.volume_off,
          onPressed: onToggleMute,
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
