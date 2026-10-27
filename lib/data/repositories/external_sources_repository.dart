import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/app_config.dart';

/// Loads editable playback source domains from Supabase. Last known good values
/// are cached locally so temporary network failures do not disable playback.
class ExternalSourcesRepository {
  ExternalSourcesRepository({http.Client? client})
    : _client = client ?? http.Client();

  static final ExternalSourcesRepository instance =
      ExternalSourcesRepository._();

  ExternalSourcesRepository._() : _client = http.Client();

  static const String _cacheKey = 'external_sources_v1';
  static const Duration _refreshInterval = Duration(minutes: 5);

  final http.Client _client;
  Map<String, List<String>>? _memory;
  DateTime? _loadedAt;
  Future<Map<String, List<String>>>? _refreshing;

  Future<Map<String, List<String>>> load({bool forceRefresh = false}) async {
    if (!forceRefresh &&
        _memory != null &&
        _loadedAt != null &&
        DateTime.now().difference(_loadedAt!) < _refreshInterval) {
      return _memory!;
    }

    final Map<String, List<String>> cached = await _readCache();
    final Future<Map<String, List<String>>> refresh = _refresh();
    if (forceRefresh) return refresh;

    // Playback starts from memory/local cache and baked-in provider fallbacks.
    // Supabase updates the source list in the background instead of blocking
    // the first stream resolution for up to 12 seconds.
    unawaited(refresh);
    return cached;
  }

  Future<Map<String, List<String>>> _readCache() async {
    if (_memory != null) return _memory!;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String? cached = prefs.getString(_cacheKey);
      final dynamic decoded = cached == null ? null : json.decode(cached);
      if (decoded is Map) {
        _memory = <String, List<String>>{};
        for (final MapEntry<dynamic, dynamic> entry in decoded.entries) {
          if (entry.key is String && entry.value is List) {
            _memory![entry.key as String] = (entry.value as List)
                .whereType<String>()
                .map((String value) => value.trim())
                .where(_isHttpsBase)
                .toSet()
                .toList();
          }
        }
      }
    } catch (_) {}
    return _memory ??= <String, List<String>>{};
  }

  Future<Map<String, List<String>>> _refresh() {
    return _refreshing ??= _fetchRemote().whenComplete(() {
      _refreshing = null;
    });
  }

  Future<Map<String, List<String>>> _fetchRemote() async {
    _loadedAt = DateTime.now();
    try {
      final http.Response response = await _client
          .get(
            Uri.parse(AppConfig.externalSourcesBase),
            headers: <String, String>{
              'apikey': AppConfig.supabasePublishableKey,
            },
          )
          .timeout(const Duration(seconds: 12));

      if (response.statusCode != 200) {
        return _memory ?? const <String, List<String>>{};
      }

      final dynamic decoded = json.decode(utf8.decode(response.bodyBytes));
      final dynamic raw = decoded is Map ? decoded['domains'] : null;
      if (raw is! Map) return _memory ?? const <String, List<String>>{};

      final Map<String, List<String>> sources = <String, List<String>>{};
      for (final MapEntry<dynamic, dynamic> entry in raw.entries) {
        if (entry.key is! String || entry.value is! List) continue;
        final List<String> urls = (entry.value as List)
            .whereType<String>()
            .map((String value) => value.trim())
            .where(_isHttpsBase)
            .toSet()
            .toList();
        if (urls.isNotEmpty) sources[entry.key as String] = urls;
      }
      if (sources.isNotEmpty) {
        _memory = sources;
        final SharedPreferences prefs = await SharedPreferences.getInstance();
        await prefs.setString(_cacheKey, json.encode(sources));
      }
    } catch (_) {
      // Keep last known sources; providers use local fallback domains as well.
    }
    return _memory ?? const <String, List<String>>{};
  }

  bool _isHttpsBase(String value) {
    final Uri? uri = Uri.tryParse(value);
    return uri != null &&
        uri.scheme == 'https' &&
        uri.host.isNotEmpty &&
        uri.userInfo.isEmpty &&
        uri.query.isEmpty &&
        uri.fragment.isEmpty;
  }
}
