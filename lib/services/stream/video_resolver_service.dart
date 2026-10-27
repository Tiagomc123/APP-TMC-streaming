import 'dart:async';
import 'dart:collection';

import 'package:shared_preferences/shared_preferences.dart';

import '../../core/app_config.dart';
import '../../core/net/tmc_http.dart';
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
///  SERVICO DE EXTRACAO DE LINK DIRETO
///
///  Resolve um [MediaRef] em um [ResolvedStream] (URL .m3u8/.mp4 limpa).
///
///  Garantias:
///   - cache em memoria (TTL) + dedupe de chamadas concorrentes;
///   - corrida escalonada entre provedores: o 1o que responder vence e os
///     seguintes ja estao aquecidos para servir de fallback imediato;
///   - ordenacao dinamica por saude do provedor (persistida);
///   - `exclude` para o player pedir "outra fonte" quando o stream morre;
///   - stream de [ResolverStatus] para a UI mostrar "testando fonte 2 de 4".
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

  void _emit(
    String message, {
    String? providerId,
    int attempt = 0,
    int total = 0,
  }) {
    if (!_status.isClosed) {
      _status.add(
        ResolverStatus(
          message: message,
          providerId: providerId,
          attempt: attempt,
          total: total,
        ),
      );
    }
  }

  /// Resolve. `force` ignora cache; `providerId` forca uma fonte;
  /// `exclude` remove fontes ja tentadas.
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

  Future<ResolvedStream?> _resolveInternal(
    MediaRef ref, {
    String? providerId,
    Set<String> exclude = const <String>{},
  }) async {
    final Map<String, List<String>> sources =
        await ExternalSourcesRepository.instance.load();
    final List<StreamProvider> pool = _ordered(
      providerId: providerId,
      exclude: exclude,
    );
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
    } else {
      for (final StreamProvider p in pool) {
        _health.putIfAbsent(p.id, () => _Health()).fail++;
      }
    }
    unawaited(_persistHealth());
    return winner;
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
      final int byHealth = (_health[b.id]?.score ?? 0.5).compareTo(
        _health[a.id]?.score ?? 0.5,
      );
      return byHealth != 0 ? byHealth : a.priority.compareTo(b.priority);
    });
    return list;
  }

  /// Corrida escalonada: a fonte 1 sai na hora, a 2 em 1.2 s, a 3 em 2.4 s...
  /// Se a 1 travar, a 2 ja esta a caminho.
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

          try {
            final ResolvedStream? s = await provider.resolve(ref, ctx);
            if (s != null && !completer.isCompleted) {
              _emit(
                'Reproduzindo via ${provider.label}',
                providerId: provider.id,
              );
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

  /// Pre-aquece a resolucao em background (chamar ao abrir a tela de detalhes).
  void prefetch(MediaRef ref) {
    if (_cache[ref.key]?.alive ?? false) return;
    unawaited(resolve(ref).catchError((Object _) => null));
  }

  void invalidate([String? key]) =>
      key == null ? _cache.clear() : _cache.remove(key);

  // ------------------------------ saude persistida ---------------------------
  static const String _healthKey = 'resolver_health_v1';

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
            .map(
              (MapEntry<String, _Health> e) =>
                  '${e.key},${e.value.ok},${e.value.fail}',
            )
            .join(';'),
      );
    } catch (_) {}
  }

  void dispose() {
    _status.close();
    _http.close();
  }
}
