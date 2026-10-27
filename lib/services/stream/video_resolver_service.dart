import 'dart:async';
import 'dart:collection';

import 'package:shared_preferences/shared_preferences.dart';

import '../../core/app_config.dart';
import '../../core/net/tmc_http.dart';
import '../../data/models/hls_models.dart';
import '../../data/models/media_ref.dart';
import '../../data/models/resolved_stream.dart';
import '../../data/repositories/external_sources_repository.dart';
import 'providers/provider_registry.dart';
import 'providers/stream_provider.dart';

class ResolverStatus {
  const ResolverStatus({
    required this.message,
    this.providerId,
    this.attempt = 0,
    this.total = 0,
  });

  final String message;
  final String? providerId;
  final int attempt;
  final int total;
}

class _CacheEntry {
  _CacheEntry(this.stream) : at = DateTime.now();
  final ResolvedStream stream;
  final DateTime at;
  bool get alive => DateTime.now().difference(at) < AppConfig.streamCacheTtl;
}

class _Health {
  int ok = 0;
  int fail = 0;
  double get score => ok / (ok + fail + 1);
}

/// =============================================================================
///  RESOLVEDOR DE LINK DIRETO
///
///  Sem WebView: o resultado e SEMPRE um manifesto .m3u8/.mp4.
///   - cache em memoria com TTL + dedupe de chamadas concorrentes;
///   - corrida escalonada entre APIs (1a sai na hora, 2a em 1.2s...);
///   - rotacao de User-Agent antes de cada fonte (anti-fingerprint);
///   - audio PT-BR promovido para a primeira faixa quando o HLS oferece varias;
///   - saude por fonte persistida, usada para reordenar.
/// =============================================================================
class VideoResolverService {
  VideoResolverService({
    TmcHttp? http,
    List<StreamProvider>? providers,
    this.stagger = const Duration(milliseconds: 1200),
  }) : _http = http ?? TmcHttp(),
       _providers = providers ?? ProviderRegistry.all() {
    _loadHealth();
  }

  final TmcHttp _http;
  final List<StreamProvider> _providers;
  final Duration stagger;

  final LinkedHashMap<String, _CacheEntry> _cache =
      LinkedHashMap<String, _CacheEntry>();
  final Map<String, Future<ResolvedStream?>> _inflight =
      <String, Future<ResolvedStream?>>{};
  final Map<String, _Health> _health = <String, _Health>{};
  final StreamController<ResolverStatus> _status =
      StreamController<ResolverStatus>.broadcast();

  Stream<ResolverStatus> get status => _status.stream;
  List<StreamProvider> get providers =>
      List<StreamProvider>.unmodifiable(_providers);

  void _emit(String message, {String? providerId, int attempt = 0, int total = 0}) {
    if (!_status.isClosed) {
      _status.add(ResolverStatus(
        message: message,
        providerId: providerId,
        attempt: attempt,
        total: total,
      ));
    }
  }

  Future<ResolvedStream?> resolve(
    MediaRef ref, {
    String? providerId,
    bool force = false,
    Set<String> exclude = const <String>{},
  }) async {
    final bool cacheable = providerId == null && exclude.isEmpty && !force;

    if (cacheable) {
      final _CacheEntry? hit = _cache[ref.key];
      if (hit != null && hit.alive) {
        _emit('Fonte em cache: ${hit.stream.providerLabel}');
        return hit.stream;
      }
      final Future<ResolvedStream?>? pending = _inflight[ref.key];
      if (pending != null) return pending;
    }

    final Future<ResolvedStream?> future = _resolveInternal(
      ref,
      providerId: providerId,
      exclude: exclude,
    );

    if (cacheable) {
      _inflight[ref.key] = future;
      unawaited(future.whenComplete(() => _inflight.remove(ref.key)));
    }

    final ResolvedStream? out = await future;
    if (out != null && cacheable) _cache[ref.key] = _CacheEntry(out);
    return out;
  }

  /// Resolve e, se tudo falhar, tenta a fonte de maior prioridade sozinha
  /// (evita perder por timeout da corrida).
  Future<ResolvedStream?> resolveDirect(MediaRef ref) async {
    final ResolvedStream? first = await resolve(ref);
    if (first != null) return first;

    final List<StreamProvider> pool = _ordered();
    if (pool.isEmpty) return null;

    final StreamProvider fallback = pool.first;
    _emit('Tentando ${fallback.label} novamente...', providerId: fallback.id);
    return resolve(ref, providerId: fallback.id, force: true);
  }

  Future<ResolvedStream?> _resolveInternal(
    MediaRef ref, {
    String? providerId,
    Set<String> exclude = const <String>{},
  }) async {
    final Map<String, List<String>> sources =
        await ExternalSourcesRepository.instance.load();
    final List<StreamProvider> pool = _ordered(providerId: providerId, exclude: exclude);
    if (pool.isEmpty) {
      _emit('Nenhuma fonte compativel');
      return null;
    }

    final ResolverContext ctx = ResolverContext(
      http: _http,
      ref: ref,
      emit: _emit,
      sources: sources,
    );
    final ResolvedStream? winner = await _staggeredRace(pool, ref, ctx);

    if (winner != null) {
      _health.putIfAbsent(winner.providerId, () => _Health()).ok++;
      unawaited(_persistHealth());
      return _preferPtBrAudio(winner);
    }

    for (final StreamProvider p in pool) {
      _health.putIfAbsent(p.id, () => _Health()).fail++;
    }
    unawaited(_persistHealth());
    return null;
  }

  /// Coloca a faixa de audio PT-BR na primeira posicao.
  ResolvedStream _preferPtBrAudio(ResolvedStream stream) {
    if (stream.audioTracks.length < 2) return stream;
    final List<HlsAudioTrack> ordered = List<HlsAudioTrack>.of(stream.audioTracks)
      ..sort((HlsAudioTrack a, HlsAudioTrack b) => _ptScore(b).compareTo(_ptScore(a)));
    return stream.reorderAudio(ordered);
  }

  int _ptScore(HlsAudioTrack track) {
    final String s = '${track.lang} ${track.name}'.toLowerCase();
    for (final String lang in AppConfig.ptBrLanguages) {
      if (s.contains(lang)) return 3;
    }
    if (s.contains('portugu') || s.contains('dubla')) return 3;
    if (s.contains('en')) return 1;
    return 2;
  }

  List<StreamProvider> _ordered({
    String? providerId,
    Set<String> exclude = const <String>{},
  }) {
    final List<StreamProvider> list = _providers
        .where((StreamProvider p) => providerId == null || p.id == providerId)
        .where((StreamProvider p) => !exclude.contains(p.id))
        .toList();

    list.sort((StreamProvider a, StreamProvider b) {
      final int byHealth =
          (_health[b.id]?.score ?? 0.5).compareTo(_health[a.id]?.score ?? 0.5);
      return byHealth != 0 ? byHealth : a.priority.compareTo(b.priority);
    });
    return list;
  }

  Future<ResolvedStream?> _staggeredRace(
    List<StreamProvider> pool,
    MediaRef ref,
    ResolverContext ctx,
  ) async {
    final Completer<ResolvedStream?> completer = Completer<ResolvedStream?>();
    int pending = pool.length;

    for (int i = 0; i < pool.length; i++) {
      final StreamProvider provider = pool[i];
      final Duration delay = stagger * i;

      unawaited(
        Future<void>.delayed(delay, () async {
          if (completer.isCompleted) return;

          ctx.emit(
            'Testando ${provider.label}...',
            providerId: provider.id,
            attempt: i + 1,
            total: pool.length,
          );
          AppConfig.rotateUserAgent();

          try {
            final ResolvedStream? s = await provider.resolve(ref, ctx);
            if (s != null && !completer.isCompleted) {
              _emit('Reproduzindo via ${provider.label}', providerId: provider.id);
              completer.complete(s);
            }
          } catch (e) {
            _emit('${provider.label} falhou: $e', providerId: provider.id);
          } finally {
            pending--;
            if (pending <= 0 && !completer.isCompleted) {
              completer.complete(null);
            }
          }
        }),
      );
    }

    return completer.future.timeout(
      AppConfig.resolveTimeout,
      onTimeout: () => null,
    );
  }

  void prefetch(MediaRef ref) {
    if (_cache[ref.key]?.alive ?? false) return;
    unawaited(resolve(ref).catchError((Object _) => null));
  }

  void invalidate([String? key]) =>
      key == null ? _cache.clear() : _cache.remove(key);

  /// Saude atual (0..1) por fonte, para o painel do app.
  Map<String, double> healthScores() => <String, double>{
        for (final StreamProvider p in _providers) p.id: _health[p.id]?.score ?? 0.5,
      };

  void resetHealth() {
    _health.clear();
    unawaited(_persistHealth());
  }

  static const String _healthKey = 'resolver_health_v2';

  Future<void> _loadHealth() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String? raw = prefs.getString(_healthKey);
      if (raw == null) return;

      for (final String row in raw.split(';')) {
        final List<String> parts = row.split(',');
        if (parts.length != 3) continue;
        final _Health h = _health.putIfAbsent(parts[0], () => _Health());
        h.ok = int.tryParse(parts[1]) ?? 0;
        h.fail = int.tryParse(parts[2]) ?? 0;
      }
    } catch (_) {}
  }

  Future<void> _persistHealth() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _healthKey,
        _health.entries
            .map((MapEntry<String, _Health> e) => '${e.key},${e.value.ok},${e.value.fail}')
            .join(';'),
      );
    } catch (_) {}
  }

  void dispose() {
    _status.close();
    _http.close();
  }
}