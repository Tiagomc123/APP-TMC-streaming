import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

import '../../core/focus/dpad.dart';
import '../../core/theme/app_theme.dart';

/// =============================================================================
///  TRAILER EMBUTIDO - SEM CONGELAMENTO
///
///  Causa do bug: a tela cheia criava uma SEGUNDA view ligada ao mesmo
///  controller (duas platform views simultaneas) e a orientacao recriava o
///  controlador, perdendo o frame.
///
///  Solucao aplicada:
///   1. [AutomaticKeepAliveClientMixin]: rolar a pagina nunca descarta o State;
///   2. o controlador e criado UMA vez e vive no State;
///   3. a tela cheia reaproveita o MESMO controlador;
///   4. o widget do player usa um [GlobalKey], entao ao entrar/sair da tela
///      cheia o elemento e REPARENTADO (a view nativa nao e destruida);
///   5. enquanto a tela cheia esta aberta, a versao inline vira placeholder,
///      garantindo UMA unica view ativa.
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

class _EmbeddedTrailerState extends State<EmbeddedTrailer>
    with AutomaticKeepAliveClientMixin {
  final GlobalKey _playerKey = GlobalKey(debugLabel: 'tmc-trailer-player');

  YoutubePlayerController? _ctl;
  StreamSubscription<YoutubePlayerValue>? _subscription;
  bool _playing = false;
  bool _muted = false;
  bool _fullscreen = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  @override
  bool get wantKeepAlive => true;

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
        showFullscreenButton: false,
        strictRelatedVideos: true,
        privacyEnhancedMode: true,
      ),
    );
    _subscription = _ctl!.stream.listen(_onValue);
  }

  Widget _player() => YoutubePlayer(
        key: _playerKey,
        controller: _ctl!,
        aspectRatio: 16 / 9,
      );

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

  void _openFullscreen() {
    if (_fullscreen || _ctl == null) return;

    // 1) inline vira placeholder no MESMO frame em que a rota entra:
    //    o GlobalKey reparenta o elemento e a view nativa sobrevive.
    setState(() => _fullscreen = true);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context)
          .push<void>(
            MaterialPageRoute<void>(
              builder: (_) => TrailerFullscreen(
                player: _player(),
                title: widget.title,
                playing: _playing,
                onTogglePlay: _toggle,
              ),
            ),
          )
          .then((_) {
        if (mounted) setState(() => _fullscreen = false);
      });
    });
  }

  String _fmt(Duration d) =>
      '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final YoutubePlayerController? ctl = _ctl;
    if (ctl == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        ClipRRect(
          borderRadius: AppTheme.br,
          child: _fullscreen
              ? const AspectRatio(
                  aspectRatio: 16 / 9,
                  child: ColoredBox(color: Colors.black),
                )
              : _player(),
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
              onPressed: _openFullscreen,
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

/// Tela cheia em paisagem. Nao cria controlador: recebe o widget do player
/// (mesmo GlobalKey) pronto do pai.
class TrailerFullscreen extends StatefulWidget {
  const TrailerFullscreen({
    super.key,
    required this.player,
    required this.title,
    required this.playing,
    required this.onTogglePlay,
  });

  final Widget player;
  final String title;
  final bool playing;
  final VoidCallback onTogglePlay;

  @override
  State<TrailerFullscreen> createState() => _TrailerFullscreenState();
}

class _TrailerFullscreenState extends State<TrailerFullscreen> {
  bool _landscape = true;
  bool _barVisible = true;

  @override
  void initState() {
    super.initState();
    unawaited(_apply(true));
  }

  @override
  void dispose() {
    unawaited(_apply(false));
    super.dispose();
  }

  Future<void> _apply(bool landscape) async {
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
                  Center(child: widget.player),
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
                                  label: widget.playing ? 'PAUSAR' : 'REPRODUZIR',
                                  icon: widget.playing ? Icons.pause : Icons.play_arrow,
                                  onPressed: widget.onTogglePlay,
                                ),
                                const SizedBox(width: 10),
                                TvButton(
                                  label: _landscape ? 'RETRATO' : 'PAISAGEM',
                                  icon: Icons.screen_rotation,
                                  onPressed: () {
                                    setState(() => _landscape = !_landscape);
                                    unawaited(_apply(_landscape));
                                  },
                                ),
                                const SizedBox(width: 10),
                                TvButton(
                                  label: 'OCULTAR',
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