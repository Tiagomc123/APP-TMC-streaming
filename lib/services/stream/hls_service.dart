import 'dart:convert';

import '../../core/net/tmc_http.dart';
import '../../data/models/hls_models.dart';

class HlsManifest {
  const HlsManifest({
    this.variants = const <HlsVariant>[],
    this.audios = const <HlsAudioTrack>[],
    this.subtitles = const <HlsSubtitleTrack>[],
  });

  final List<HlsVariant> variants;
  final List<HlsAudioTrack> audios;
  final List<HlsSubtitleTrack> subtitles;
}

class HlsService {
  HlsService(this._http);
  final TmcHttp _http;

  Future<HlsManifest?> parseMaster(String url, {String? referer}) async {
    if (!url.contains('.m3u8')) return null;

    final HttpResult? res = await _http.getText(url, referer: referer);
    if (res == null || !res.ok) return null;

    if (!res.body.contains('#EXT-X-STREAM-INF') && !res.body.contains('#EXT-X-MEDIA')) {
      return HlsManifest(
        variants: <HlsVariant>[HlsVariant(url: url, bandwidth: 0, label: 'FONTE')],
      );
    }

    final List<String> lines = const LineSplitter().convert(res.body);
    final List<HlsVariant> variants = <HlsVariant>[];
    final List<HlsAudioTrack> audios = <HlsAudioTrack>[];
    final List<HlsSubtitleTrack> subs = <HlsSubtitleTrack>[];

    for (int i = 0; i < lines.length; i++) {
      final String line = lines[i].trim();

      if (line.startsWith('#EXT-X-MEDIA')) {
        final bool isAudio = line.contains('TYPE=AUDIO');
        final bool isSub = line.contains('TYPE=SUBTITLES');
        if (!isAudio && !isSub) continue;

        final String? uri = _attr(line, 'URI');
        if (uri == null) continue;

        final String name = _attr(line, 'NAME') ?? _attr(line, 'LANGUAGE')?.toUpperCase() ?? 'FAIXA';
        final String abs = _abs(uri, url);

        if (isAudio) {
          audios.add(HlsAudioTrack(name: name, lang: _attr(line, 'LANGUAGE') ?? '', url: abs));
        } else {
          subs.add(HlsSubtitleTrack(name: name, lang: _attr(line, 'LANGUAGE') ?? '', url: abs));
        }
        continue;
      }

      if (!line.startsWith('#EXT-X-STREAM-INF')) continue;

      final String? resolution = _attr(line, 'RESOLUTION');
      final int bw = int.tryParse(_attr(line, 'BANDWIDTH') ?? '0') ?? 0;

      for (int k = i + 1; k < lines.length; k++) {
        final String next = lines[k].trim();
        if (next.isEmpty || next.startsWith('#')) continue;
        variants.add(HlsVariant(
          url: _abs(next, url),
          bandwidth: bw,
          label: resolution ?? '${(bw / 1000).round()}k',
        ));
        break;
      }
    }

    variants.sort((HlsVariant a, HlsVariant b) => a.bandwidth.compareTo(b.bandwidth));
    return HlsManifest(variants: variants, audios: audios, subtitles: subs);
  }

  String _abs(String url, String base) {
    try {
      return Uri.parse(base).resolve(url).toString();
    } catch (_) {
      return url;
    }
  }

  String? _attr(String line, String key) =>
      RegExp('$key="([^"]+)"').firstMatch(line)?.group(1);
}