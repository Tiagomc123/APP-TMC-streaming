import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/app_config.dart';

/// Loads editable playback source domains from Supabase. Last known good values
/// are cached locally so temporary network failures do not disable playback.
class ExternalSourcesRepository {
  ExternalSourcesRepository._();

  static final ExternalSourcesRepository instance =
      ExternalSourcesRepository._();

  static const String _cacheKey = 'external_sources_v1';
  static const Duration _refreshInterval = Duration(minutes: 5);

  Map<String, List<String>>? _memory;
  DateTime? _loadedAt;

  Future<Map<String, List<String>>> load({bool forceRefresh = false}) async {
    if (!forceRefresh && _memory != null && _loadedAt != null &&
        DateTime.now().difference(_loadedAt!) < _refreshInterval) {
      return _memory!;
    }

    try {
      final http.Response response = await http
          .get(
            Uri.parse(AppConfig.externalSourcesBase),
            headers: <String, String>{
              'apikey': AppConfig.supabasePublishableKey,
            },
          )
          .timeout(const Duration(seconds: 12));

      if (response.statusCode == 200) {
        final dynamic decoded = json.decode(utf8.decode(response.bodyBytes));
        final dynamic raw = decoded is Map ? decoded['domains'] : null;
        if (raw is Map) {
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
            _loadedAt = DateTime.now();
            final SharedPreferences prefs = await SharedPreferences.getInstance();
            await prefs.setString(_cacheKey, json.encode(sources));
            return sources;
          }
        }
      }
    } catch (_) {
      // Use the last valid Supabase response if offline or temporarily failing.
    }

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
                .where(_isHttpsBase)
                .toList();
          }
        }
        return _memory!;
      }
    } catch (_) {}
    return const <String, List<String>>{};
  }

  bool _isHttpsBase(String value) {
    final Uri? uri = Uri.tryParse(value);
    return uri != null && uri.scheme == 'https' && uri.host.isNotEmpty &&
        uri.userInfo.isEmpty && uri.query.isEmpty && uri.fragment.isEmpty;
  }
}
