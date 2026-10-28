import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../core/focus/dpad.dart';
import '../../core/log/tmc_log.dart';
import '../../core/ui/screen_mode.dart';
import '../../data/models/hls_models.dart';
import '../../data/models/resolved_stream.dart';
import 'seek_bar.dart';

class PlayerBackGuard extends StatelessWidget {
  const PlayerBackGuard({super.key, required this.onBack, required this.child});

  final VoidCallback onBack;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? _) {
        if (!didPop) onBack();
      },
      child: child,
    );
  }
}

/// =============================================================================
///  PLAYER NATIVO INTEGRADO
///
///  Nunca sai do app. Nunca abre janela externa.
///
///  - headers customizados em TODAS as requisicoes (playlist, segmentos, chave);
///  - erro de rede com backoff exponencial 1s/2s/4s + fallback de provedor;
///  - watchdog de buffering: rede ruim sugere qualidade menor;
///  - auto-resume, proxima faixa, qualidade/audio/legenda;
///  - controle remoto completo por D-Pad (Shortcuts/Actions + FocusNode).
/// =============================================================================
class CustomVideoPlayer extends StatefulWidget {
  const CustomVideoPlayer({
    super.key,
    required this.stream,
    required this.title,
    this.subtitle,
    this.startAt = Duration.zero,
    this.isLive = false,
    this.autoPlay = true,
    this.onProgress,
    this.onCompleted,
    this.onNeedFallback,
    this.onExit,
  });

  final ResolvedStream stream;
  final String title;
  final String? subtitle;
  final Duration startAt;
  final bool isLive;
  final bool autoPlay;

  final void Function(Duration position, Duration duration)? onProgress;
  final VoidCallback? onCompleted;

  /// Pede outra fonte ao resolver (a atual morreu).
  final Future<ResolvedStream?> Function()? onNeedFallback;

  final VoidCallback? onExit;

  @override
  State<CustomVideoPlayer> createState() => _CustomVideoPlayerState();
}

class _CustomVideoPlayerState extends State<CustomVideoPlayer> {
  late final Player _player;
  late final VideoController _controller;

  final FocusNode _rootFocus = FocusNode(debugLabel: 'player-root');
  final FocusNode _playFocus = FocusNode(debugLabel: 'player-play');

  StreamSubscription<bool>? _bufferingSub;
  StreamSubscription<String>? _errorSub;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<bool>? _completedSub;
  StreamSubscription<Duration>? _durationSub;
  StreamSubscription<Tracks>? _tracksSub;

  Timer? _hideTimer;
  Timer? _watchdog;
  Timer? _saveTimer;
  Timer? _retryTimer;

  bool _uiVisible = true;
  bool _playing = false;
  bool _buffering = true;
  bool _finished = false;
  String? _error;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  Duration _lastPosition = Duration.zero;
  int _stallSeconds = 0;
  int _retries = 0;
  bool _fallbackTried = false;
  bool _retryPending = false; // TMC-FIX v1
  bool _exitRequested = false;
  late ResolvedStream _stream;
  List<AudioTrack> _audioTracks = const <AudioTrack>[];
  List<SubtitleTrack> _subtitleTracks = const <SubtitleTrack>[];
  int _speedIndex = 2;

  static const List<double> _speeds = <double>[0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

  @override
  void initState() {
    super.initState();
    _stream = widget.stream;

    _player = Player(
      configuration: const PlayerConfiguration(
        title: 'TMC',
        logLevel: MPVLogLevel.error,
        bufferSize: 64 * 1024 * 1024,
        protocolWhitelist: <String>[
          'http',
          'https',
          'tcp',
          'tls',
          'hls',
          'file',
          'crypto',
          'data',
        ],
      ),
    );

    _controller = VideoController(
      _player,
      configuration: const VideoControllerConfiguration(
        enableHardwareAcceleration: true,
        androidAttachSurfaceAfterVideoParameters: true,
      ),
    );

    _bindStreams();
    _applyNetworkTuning();

    unawaited(WakelockPlus.enable());
    unawaited(ScreenMode.immersive());

    WidgetsBinding.instance.addPostFrameCallback((_) {
      // TMC-FIX v1: se o usuario sair antes do 1o frame, _player e
      // _rootFocus ja foram descartados -> tocar aqui explodia e o video
      // "as vezes nao carregava".
      if (!mounted) return;
      _rootFocus.requestFocus();
      unawaited(_open(_stream, startAt: widget.startAt));
      _restartHideTimer();
    });
  }

  /// Propriedades do mpv. Chamadas por despacho dinamico porque
  /// `Player.setProperty` existe em algumas versoes do media_kit e nao em outras.
  void _applyNetworkTuning() {
    // TMC-FIX v1: loga o que falhou em vez de engolir tudo.
    const Map<String, String> props = <String, String>{
      'network-timeout': '25',
      'cache-secs': '30',
      'demuxer-max-bytes': '64MiB',
      'demuxer-max-back-bytes': '32MiB',
      'stream-buffer-size': '4MiB',
    };

    props.forEach((String key, String value) {
      try {
        // ignore: avoid_dynamic_calls
        (_player as dynamic).setProperty(key, value);
      } catch (err) {
        TmcLog.w('player', 'mpv nao aceitou $key=$value ($err)');
      }
    });
  }

  void _bindStreams() {
    _bufferingSub = _player.stream.buffering.listen((bool v) {
      if (!mounted) return;
      setState(() => _buffering = v);
      if (!v) _stallSeconds = 0;
    });

    _errorSub = _player.stream.error.listen(_onPlayerError);

    _positionSub = _player.stream.position.listen((Duration p) {
      if (!mounted) return;
      if (p > _position) {
        // Consider the stream healthy only after playback actually advances.
        _retries = 0;
        _fallbackTried = false;
      }
      setState(() {
        _position = p;
        _playing = _player.state.playing;
      });
    });

    _durationSub = _player.stream.duration.listen((Duration d) {
      if (mounted) setState(() => _duration = d);
    });

    _completedSub = _player.stream.completed.listen((bool done) {
      if (!mounted || !done) return;
      setState(() => _finished = true);
      widget.onCompleted?.call();
    });

    _tracksSub = _player.stream.tracks.listen((Tracks t) {
      if (!mounted) return;
      setState(() {
        _audioTracks = t.audio;
        _subtitleTracks = t.subtitle;
      });
    });

    _saveTimer = Timer.periodic(const Duration(seconds: 5), (Timer _) {
      if (_duration > Duration.zero) {
        widget.onProgress?.call(_position, _duration);
      }
    });

    _watchdog = Timer.periodic(const Duration(seconds: 3), (Timer _) {
      if (!mounted || _finished) return;
      if (_buffering && _position == _lastPosition) {
        _stallSeconds += 3;
      } else {
        _stallSeconds = 0;
      }
      _lastPosition = _position;
      if (_stallSeconds >= 12 && _buffering) _onStall();
    });
  }

  String _humanize(String raw) {
    final String e = raw.toLowerCase();
    if (e.contains('403') || e.contains('forbidden')) {
      return 'Acesso negado pela fonte (403)';
    }
    if (e.contains('404')) {
      return 'Stream nao encontrado (404)';
    }
    if (e.contains('timeout') || e.contains('timed out')) {
      return 'Tempo de conexao esgotado';
    }
    if (e.contains('refused')) {
      return 'Conexao recusada';
    }
    if (e.contains('unrecognized') || e.contains('codec')) {
      return 'Codec nao suportado';
    }
    return 'Falha de reproducao';
  }

  // TMC-FIX v1: loga o alvo sem imprimir query (token).
  Future<void> _open(
    ResolvedStream s, {
    Duration startAt = Duration.zero,
  }) async {
    TmcLog.i(
      'player',
      'abrindo ${TmcLog.where(s.url.toString())} '
          '(fonte=${s.providerId}, inicio=${startAt.inSeconds}s)',
    );
    try {
      await _player.open(
        Media(
          s.url.toString(),
          httpHeaders: s.headers, // <<< headers em todas as requisicoes
          start: startAt,
        ),
        play: widget.autoPlay,
      );
      if (mounted) {
        setState(() {
          _error = null;
          _finished = false;
        });
        TmcLog.i('player', 'aberto com sucesso');
      }
    } catch (e) {
      if (mounted) setState(() => _error = _humanize(e.toString()));
      TmcLog.e('player', 'falha ao abrir: $e');
      _scheduleRetry();
    }
  }

  // TMC-FIX v1: erro do mpv nem sempre e fatal. Antes QUALQUER erro pintava
  // a camada preta e transformava o botao PLAY em "reabrir stream".
  void _onPlayerError(String raw) {
    if (!mounted || raw.isEmpty) return;
    final String humano = _humanize(raw);
    final bool jaVisivel = _error != null;
    TmcLog.w('player', 'mpv: ${TmcLog.where(raw)} -> $humano');

    final bool provavelFatal =
        raw.toLowerCase().contains('403') ||
        raw.toLowerCase().contains('404') ||
        raw.toLowerCase().contains('refused') ||
        raw.toLowerCase().contains('unrecognized');

    if (provavelFatal || !jaVisivel) {
      setState(() => _error = humano);
    }
    _scheduleRetry();
  }

  /// Backoff exponencial: 1 s, 2 s, 4 s -> depois troca de fonte.
  void _scheduleRetry() {
    // TMC-FIX v1: guarda contra rajada de erros do mpv (varios eventos por
    // segundo). Sem isto o contador estourava e trocava de fonte com o video
    // funcionando normalmente.
    if (_retryPending) return;
    _retryTimer?.cancel();

    if (_retries >= 3) {
      _retries = 0;
      _retryPending = false;
      TmcLog.w('player', '3 tentativas falharam -> pedindo outra fonte');
      unawaited(_tryFallback());
      return;
    }
    _retries++;
    _retryPending = true;
    final Duration delay = Duration(seconds: 1 << (_retries - 1));
    TmcLog.i('player', 'retry $_retries em ${delay.inSeconds}s');
    _retryTimer = Timer(delay, () {
      _retryPending = false;
      if (!mounted || _error == null) return;
      unawaited(_open(_stream, startAt: _position));
    });
  }

  Future<void> _tryFallback() async {
    if (_fallbackTried || widget.onNeedFallback == null) return;
    _fallbackTried = true;
    setState(() => _error = 'Trocando de servidor...');

    final ResolvedStream? alt = await widget.onNeedFallback!.call();
    if (!mounted) return;

    if (alt == null) {
      setState(
        () => _error = 'Todas as fontes falharam. Toque para tentar novamente.',
      );
      return;
    }

    _stream = alt;
    _retries = 0;
    _fallbackTried = false;
    await _open(alt, startAt: _position);
  }

  void _onStall() {
    _stallSeconds = 0;
    if (_stream.hasQualityOptions && _stream.variants.length > 1) {
      final HlsVariant lowest = _stream.variants.first;
      if (_stream.url.toString() != lowest.url) {
        _snack('Rede lenta - trocando para ${lowest.label}');
        unawaited(
          _open(
            _stream.copyWith(url: Uri.parse(lowest.url)),
            startAt: _position,
          ),
        );
        return;
      }
    }

    if (widget.onNeedFallback == null) {
      setState(
        () => _error =
            'A fonte demorou para iniciar. Toque em TENTAR DE NOVO ou SAIR.',
      );
      return;
    }

    setState(() => _error = 'A fonte travou. Procurando outra fonte...');
    _retries = 3;
    _scheduleRetry();
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
      );
  }

  // --------------------------------- controles -------------------------------
  void _togglePlay() {
    if (_error != null) {
      _retries = 0;
      unawaited(_open(_stream, startAt: _position));
      return;
    }
    if (_finished) {
      unawaited(_player.seek(Duration.zero));
      unawaited(_player.play());
      setState(() => _finished = false);
      return;
    }
    unawaited(_player.playOrPause());
    _restartHideTimer();
  }

  void _seekBy(Duration d) {
    if (_duration == Duration.zero) return;
    Duration target = _position + d;
    if (target < Duration.zero) target = Duration.zero;
    if (target > _duration) target = _duration;
    unawaited(_player.seek(target));
    setState(() => _position = target);
    _restartHideTimer();
  }

  void _showUi() {
    setState(() => _uiVisible = true);
    _restartHideTimer();
    _playFocus.requestFocus();
  }

  void _hideUi() {
    setState(() => _uiVisible = false);
    _rootFocus.requestFocus();
  }

  void _restartHideTimer() {
    _hideTimer?.cancel();
    if (!_playing) return;
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && _playing && _error == null) _hideUi();
    });
  }

  void _exit() {
    if (_exitRequested) return;
    _exitRequested = true;
    widget.onProgress?.call(_position, _duration);
    widget.onExit?.call();
    if (!mounted) return;
    // This screen blocks system back with PopScope. maybePop() respects that
    // veto and only hides the controls; an explicit exit must pop the route.
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _watchdog?.cancel();
    _saveTimer?.cancel();
    _retryTimer?.cancel();
    _bufferingSub?.cancel();
    _errorSub?.cancel();
    _positionSub?.cancel();
    _durationSub?.cancel();
    _completedSub?.cancel();
    _tracksSub?.cancel();

    unawaited(WakelockPlus.disable());
    unawaited(ScreenMode.edgeToEdge());
    unawaited(_player.dispose());

    _rootFocus.dispose();
    _playFocus.dispose();
    super.dispose();
  }

  // ---------------------------------- build ----------------------------------
  @override
  Widget build(BuildContext context) {
    return PlayerBackGuard(
      onBack: _exit,
      child: Shortcuts(
        shortcuts: kPlayerShortcuts,
        child: Actions(
          actions: <Type, Action<Intent>>{
            TogglePlayIntent: CallbackAction<TogglePlayIntent>(
              onInvoke: (_) {
                _togglePlay();
                return null;
              },
            ),
            SeekIntent: CallbackAction<SeekIntent>(
              onInvoke: (SeekIntent i) {
                _seekBy(i.delta);
                return null;
              },
            ),
            ShowOverlayIntent: CallbackAction<ShowOverlayIntent>(
              onInvoke: (_) {
                if (_uiVisible) {
                  _hideUi();
                } else {
                  _showUi();
                }
                return null;
              },
            ),
            ExitPlayerIntent: CallbackAction<ExitPlayerIntent>(
              onInvoke: (_) {
                _exit();
                return null;
              },
            ),
          },
          child: Focus(
            focusNode: _rootFocus,
            autofocus: true,
            child: Scaffold(
              backgroundColor: Colors.black,
              body: FocusTraversalGroup(
                policy: ReadingOrderTraversalPolicy(),
                child: Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    _videoLayer(),
                    if (_buffering && _error == null) _bufferingIndicator(),
                    if (_error != null) _errorLayer(),
                    if (_finished) _finishedLayer(),
                    _overlay(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _videoLayer() {
    final double w = (_player.state.width ?? 0).toDouble();
    final double h = (_player.state.height ?? 0).toDouble();
    return Center(
      child: AspectRatio(
        aspectRatio: (w > 0 && h > 0) ? w / h : 16 / 9,
        child: Video(
          controller: _controller,
          controls: NoVideoControls,
          fit: BoxFit.contain,
          subtitleViewConfiguration: const SubtitleViewConfiguration(
            padding: EdgeInsets.only(bottom: 90, left: 24, right: 24),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }

  Widget _bufferingIndicator() => const Center(
    child: SizedBox(
      width: 52,
      height: 52,
      child: CircularProgressIndicator(strokeWidth: 3),
    ),
  );

  Widget _errorLayer() {
    return Container(
      color: Colors.black87,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.wifi_off_rounded, color: Colors.white54, size: 56),
            const SizedBox(height: 16),
            Text(
              _error!,
              style: const TextStyle(color: Colors.white, fontSize: 17),
            ),
            const SizedBox(height: 6),
            Text(
              'Fonte: ${_stream.providerLabel}',
              style: const TextStyle(color: Colors.white38, fontSize: 12),
            ),
            const SizedBox(height: 22),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 12,
              runSpacing: 8,
              children: <Widget>[
                TvButton(
                  label: 'TENTAR DE NOVO',
                  icon: Icons.refresh,
                  primary: true,
                  onPressed: () {
                    _retries = 0;
                    _fallbackTried = false;
                    unawaited(_open(_stream, startAt: _position));
                  },
                ),
                if (widget.onNeedFallback != null)
                  TvButton(
                    label: 'OUTRA FONTE',
                    icon: Icons.swap_horiz,
                    onPressed: () {
                      _fallbackTried = false;
                      unawaited(_tryFallback());
                    },
                  ),
                TvButton(label: 'SAIR', icon: Icons.close, onPressed: _exit),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _finishedLayer() {
    return Container(
      color: Colors.black87,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Text(
              'FIM',
              style: TextStyle(
                color: Colors.white,
                fontSize: 30,
                letterSpacing: 8,
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                TvButton(
                  label: 'REPETIR',
                  icon: Icons.replay,
                  primary: true,
                  onPressed: () {
                    unawaited(_player.seek(Duration.zero));
                    unawaited(_player.play());
                    setState(() => _finished = false);
                  },
                ),
                const SizedBox(width: 12),
                TvButton(
                  label: 'VOLTAR',
                  icon: Icons.arrow_back,
                  onPressed: _exit,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _overlay() {
    return AnimatedOpacity(
      opacity: _uiVisible ? 1 : 0,
      duration: const Duration(milliseconds: 200),
      child: IgnorePointer(
        ignoring: !_uiVisible,
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[
                Colors.black87,
                Colors.transparent,
                Colors.black87,
              ],
              stops: <double>[0, 0.45, 1],
            ),
          ),
          child: Column(
            children: <Widget>[
              _topBar(),
              const Spacer(),
              if (_buffering && _error == null)
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              _bottomBar(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _topBar() {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Row(
          children: <Widget>[
            TvButton(label: 'VOLTAR', icon: Icons.arrow_back, onPressed: _exit),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    widget.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                  if (widget.subtitle != null)
                    Text(
                      widget.subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                      ),
                    ),
                ],
              ),
            ),
            if (_stream.hasQualityOptions)
              TvButton(
                label: _stream.qualityLabel.isEmpty
                    ? 'QUALIDADE'
                    : _stream.qualityLabel,
                icon: Icons.high_quality,
                onPressed: _qualitySheet,
              ),
          ],
        ),
      ),
    );
  }

  Widget _bottomBar() {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (!widget.isLive)
              SeekBar(
                position: _position,
                duration: _duration,
                onSeek: (Duration d) {
                  unawaited(_player.seek(d));
                  setState(() => _position = d);
                  _restartHideTimer();
                },
                onInteraction: _restartHideTimer,
              ),
            const SizedBox(height: 8),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 10,
              runSpacing: 8,
              children: <Widget>[
                TvButton(
                  label: '-10s',
                  icon: Icons.replay_10,
                  onPressed: () => _seekBy(const Duration(seconds: -10)),
                ),
                TvButton(
                  focusNode: _playFocus,
                  label: _playing ? 'PAUSAR' : 'PLAY',
                  icon: _playing ? Icons.pause : Icons.play_arrow,
                  primary: true,
                  onPressed: _togglePlay,
                ),
                TvButton(
                  label: '+10s',
                  icon: Icons.forward_10,
                  onPressed: () => _seekBy(const Duration(seconds: 10)),
                ),
                TvButton(
                  label: 'VEL ${_speeds[_speedIndex]}x',
                  icon: Icons.speed,
                  onPressed: _speedSheet,
                ),
                TvButton(
                  label: 'AUDIO',
                  icon: Icons.audiotrack,
                  onPressed: _audioSheet,
                ),
                TvButton(
                  label: 'LEGENDA',
                  icon: Icons.subtitles,
                  onPressed: _subtitleSheet,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ------------------- sheets (todas navegaveis por D-Pad) -------------------
  Future<void> _sheet(String title, List<Widget> children) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF141414),
      isScrollControlled: true,
      builder: (_) => FocusTraversalGroup(
        policy: ReadingOrderTraversalPolicy(),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 14),
                ...children,
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _qualitySheet() {
    unawaited(
      _sheet('QUALIDADE', <Widget>[
        for (final HlsVariant v in _stream.variants.reversed)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: TvButton(
              label: v.label,
              primary: _stream.url.toString() == v.url,
              onPressed: () {
                Navigator.of(context).pop();
                final Duration at = _position;
                setState(
                  () => _stream = _stream.copyWith(
                    url: Uri.parse(v.url),
                    qualityLabel: v.label,
                  ),
                );
                unawaited(_open(_stream, startAt: at));
              },
            ),
          ),
      ]),
    );
  }

  void _speedSheet() {
    unawaited(
      _sheet('VELOCIDADE', <Widget>[
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            for (int i = 0; i < _speeds.length; i++)
              TvButton(
                label: '${_speeds[i]}x',
                primary: i == _speedIndex,
                onPressed: () {
                  unawaited(_player.setRate(_speeds[i]));
                  setState(() => _speedIndex = i);
                  Navigator.of(context).pop();
                },
              ),
          ],
        ),
      ]),
    );
  }

  void _audioSheet() {
    unawaited(
      _sheet('FAIXA DE AUDIO', <Widget>[
        TvButton(
          label: 'Automatico',
          onPressed: () {
            unawaited(_player.setAudioTrack(AudioTrack.auto()));
            Navigator.of(context).pop();
          },
        ),
        for (final AudioTrack t in _audioTracks)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: TvButton(
              label: t.title ?? t.language ?? t.id,
              onPressed: () {
                unawaited(_player.setAudioTrack(t));
                Navigator.of(context).pop();
              },
            ),
          ),
      ]),
    );
  }

  void _subtitleSheet() {
    unawaited(
      _sheet('LEGENDA', <Widget>[
        TvButton(
          label: 'Desligada',
          onPressed: () {
            unawaited(_player.setSubtitleTrack(SubtitleTrack.no()));
            Navigator.of(context).pop();
          },
        ),
        for (final SubtitleTrack t in _subtitleTracks)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: TvButton(
              label: t.title ?? t.language ?? t.id,
              onPressed: () {
                unawaited(_player.setSubtitleTrack(t));
                Navigator.of(context).pop();
              },
            ),
          ),
      ]),
    );
  }
}
