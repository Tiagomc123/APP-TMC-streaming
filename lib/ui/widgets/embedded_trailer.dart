import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

import '../../core/focus/dpad.dart';
import '../../core/theme/app_theme.dart';

/// =============================================================================
///  TRAILER EMBUTIDO + TELA CHEIA COM SAIDA GARANTIDA
///
///  Antes o botao "GIRAR TELA" apenas forÃ§ava a paisagem na propria pagina e
///  os controles ficavam fora da area visivel -> parecia travado.
///
///  Agora "GIRAR TELA" abre uma rota dedicada em paisagem com:
///   - barra superior SEMPRE visivel (VOLTAR / GIRAR / RECARREGAR);
///   - botao flutuante de fechar no canto, que nunca esconde;
///   - ESC / botao voltar do controle / back do Android encerram a rota;
///   - ao sair, a orientacao volta para retrato sozinha.
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

  /// Abre a rota de tela cheia (paisagem) â€” a mesma usada por GIRAR e TELA CHEIA.
  void _fullscreen() {
    _ctl?.pauseVideo();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => FullscreenTrailerScreen(
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
          borderRadius: AppTheme.br,
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
              icon: Icons.screen_rotation,
              onPressed: _fullscreen,
            ),
            TvButton(
              label: 'TELA CHEIA',
              icon: Icons.fullscreen,
              onPressed: _fullscreen,
            ),
            TvButton(
              label: _muted ? 'SOM ON' : 'MUDO',
              icon: _muted ? Icons.volume_up : Icons.volume_off,
              onPressed: _toggleMute,
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

/// Tela cheia em paisagem com saida impossivel de perder.
class FullscreenTrailerScreen extends StatefulWidget {
  const FullscreenTrailerScreen({
    super.key,
    required this.videoKey,
    required this.title,
    this.startAt = Duration.zero,
    this.muted = false,
  });

  final String videoKey;
  final String title;
  final Duration startAt;
  final bool muted;

  @override
  State<FullscreenTrailerScreen> createState() => _FullscreenTrailerScreenState();
}

class _FullscreenTrailerScreenState extends State<FullscreenTrailerScreen> {
  late final YoutubePlayerController _ctl;
  bool _landscape = true;
  bool _barVisible = true;

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
    unawaited(_applyOrientation(true));
  }

  Future<void> _applyOrientation(bool landscape) async {
    if (landscape) {
      await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
        DeviceOrientation.portraitUp,
      ]);
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
  }

  @override
  void dispose() {
    _ctl.close();
    unawaited(_applyOrientation(false));
    super.dispose();
  }

  void _exit() {
    if (mounted) Navigator.of(context).pop();
  }

  void _toggleBar() => setState(() => _barVisible = !_barVisible);

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? _) {
        if (!didPop) _exit();
      },
      child: Shortcuts(
        shortcuts: const <ShortcutActivator, Intent>{
          SingleActivator(LogicalKeyboardKey.escape): _ExitIntent(),
          SingleActivator(LogicalKeyboardKey.goBack): _ExitIntent(),
          SingleActivator(LogicalKeyboardKey.select): _ToggleBarIntent(),
          SingleActivator(LogicalKeyboardKey.enter): _ToggleBarIntent(),
          SingleActivator(LogicalKeyboardKey.arrowUp): _ToggleBarIntent(),
          SingleActivator(LogicalKeyboardKey.arrowDown): _ToggleBarIntent(),
        },
        child: Actions(
          actions: <Type, Action<Intent>>{
            _ExitIntent: CallbackAction<_ExitIntent>(
              onInvoke: (_) {
                _exit();
                return null;
              },
            ),
            _ToggleBarIntent: CallbackAction<_ToggleBarIntent>(
              onInvoke: (_) {
                _toggleBar();
                return null;
              },
            ),
          },
          child: Focus(
            autofocus: true,
            child: Scaffold(
              backgroundColor: Colors.black,
              body: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  Center(
                    child: YoutubePlayerControllerProvider(
                      controller: _ctl,
                      child: YoutubePlayer(controller: _ctl, aspectRatio: 16 / 9),
                    ),
                  ),

                  // Botao flutuante de fechar: SEMPRE visivel.
                  Positioned(
                    top: 12,
                    right: 12,
                    child: SafeArea(
                      child: TvButton(
                        label: 'FECHAR',
                        icon: Icons.close,
                        primary: true,
                        autofocus: true,
                        onPressed: _exit,
                      ),
                    ),
                  ),

                  // Barra inferior: so aparece quando pedida, mas o X nunca sai.
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: IgnorePointer(
                      ignoring: !_barVisible,
                      child: AnimatedOpacity(
                        opacity: _barVisible ? 1 : 0,
                        duration: AppTheme.fast,
                        child: Container(
                          color: Colors.black.withValues(alpha: .65),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          child: SafeArea(
                            top: false,
                            child: Row(
                              children: <Widget>[
                                TvButton(
                                  label: 'VOLTAR AO APP',
                                  icon: Icons.arrow_back,
                                  onPressed: _exit,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    widget.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                                  ),
                                ),
                                TvButton(
                                  label: _landscape ? 'RETRATO' : 'PAISAGEM',
                                  icon: Icons.screen_rotation,
                                  onPressed: () {
                                    setState(() => _landscape = !_landscape);
                                    unawaited(_applyOrientation(_landscape));
                                  },
                                ),
                                const SizedBox(width: 10),
                                TvButton(
                                  label: 'OCULTAR BARRA',
                                  icon: Icons.vertical_align_bottom,
                                  onPressed: _toggleBar,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ExitIntent extends Intent {
  const _ExitIntent();
}

class _ToggleBarIntent extends Intent {
  const _ToggleBarIntent();
}