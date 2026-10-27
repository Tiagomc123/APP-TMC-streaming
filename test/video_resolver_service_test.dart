// Testes do resolver na arquitetura atual:
//   VidLink   -> API JSON publica (HLS direto)
//   PobreFlix -> scraping HTTP + fallback para a API publica do SuperFlix
// Nenhum HTML renderizado, nenhuma WebView.

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mc/core/net/tmc_http.dart';
import 'package:mc/data/models/media_ref.dart';
import 'package:mc/data/models/resolved_stream.dart';
import 'package:mc/services/stream/video_resolver_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String masterUrl = 'https://cdn.content.com/hls/998877/master.m3u8';
const MediaRef ref = MediaRef(tmdbId: 550, isTv: false, title: 'Filme Teste');

const String masterBody =
    '#EXTM3U\n'
    '#EXT-X-STREAM-INF:BANDWIDTH=800000,RESOLUTION=1280x720\n'
    '720/index.m3u8\n';

http.Response _json(String body) => http.Response(
  body,
  200,
  headers: <String, String>{'content-type': 'application/json'},
);

http.Response _hls(String body) => http.Response(
  body,
  200,
  headers: <String, String>{'content-type': 'application/vnd.apple.mpegurl'},
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  late List<String> calls;

  TmcHttp buildClient({bool api = true}) => TmcHttp(
    client: MockClient((http.Request req) async {
      final String url = req.url.toString();
      calls.add(url);

      if (api && url.startsWith('https://superflixapi.fun/filme/550')) {
        return _json(
          '{"url":"$masterUrl","audio":"dublado","quality":"1080p"}',
        );
      }
      if (api && url.startsWith('https://superflixapi.pro/filme/550')) {
        return _json('{"url":"$masterUrl","audio":"dublado"}');
      }
      if (api && url.startsWith(masterUrl)) {
        return _hls(masterBody);
      }
      return http.Response('not found', 404);
    }),
  );

  VideoResolverService buildResolver({bool api = true}) => VideoResolverService(
    http: buildClient(api: api),
    stagger: const Duration(milliseconds: 15),
  );

  test('resolve o stream via API JSON (sem HTML e sem WebView)', () async {
    calls = <String>[];
    final VideoResolverService resolver = buildResolver();

    final ResolvedStream? r = await resolver.resolve(ref);

    expect(r, isNotNull);
    expect(r!.url.toString(), masterUrl);
    expect(r.kind, StreamKind.hls);
    expect(r.headers, isNotEmpty);
    expect(calls.any((String u) => u.contains('format=json')), isTrue);
    expect(calls.any((String u) => u.contains('superflixapi.fun')), isTrue);

    resolver.dispose();
  });

  test('o cache evita nova resolucao e novas chamadas HTTP', () async {
    calls = <String>[];
    final VideoResolverService resolver = buildResolver();

    final ResolvedStream? first = await resolver.resolve(ref);
    expect(first, isNotNull);

    final int afterFirst = calls.length;
    final ResolvedStream? second = await resolver.resolve(ref);

    expect(second, isNotNull);
    expect(second!.url.toString(), first!.url.toString());
    expect(calls.length, afterFirst);

    resolver.dispose();
  });

  test('exclude derruba as fontes que sabem resolver e devolve null', () async {
    calls = <String>[];
    final VideoResolverService resolver = buildResolver();

    final ResolvedStream? r = await resolver.resolve(
      ref,
      force: true,
      exclude: <String>{
        'pobreflix',
        'vidlink',
        'superflix_api',
        'warezcdn',
        'pontofinal',
        'embedcine',
      },
    );

    expect(r, isNull);

    resolver.dispose();
  });

  test('providerId forca uma fonte especifica', () async {
    calls = <String>[];
    final VideoResolverService resolver = buildResolver();

    final ResolvedStream? r = await resolver.resolve(
      ref,
      providerId: 'pobreflix',
    );

    expect(r, isNotNull);
    expect(r!.providerId, 'pobreflix');

    resolver.dispose();
  });

  test('nenhuma fonte responde -> null (sem excecao)', () async {
    calls = <String>[];
    final VideoResolverService resolver = buildResolver(api: false);

    final ResolvedStream? r = await resolver.resolve(ref);

    expect(r, isNull);

    resolver.dispose();
  });
}
