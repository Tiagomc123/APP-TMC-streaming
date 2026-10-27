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

const String masterBody = '#EXTM3U\n'
    '#EXT-X-STREAM-INF:BANDWIDTH=800000,RESOLUTION=1280x720\n'
    '720p.m3u8\n'
    '#EXT-X-STREAM-INF:BANDWIDTH=3000000,RESOLUTION=1920x1080\n'
    '1080p.m3u8\n';

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

  /// SuperFlix (JSON) responde com o manifesto dublado; todo o resto 404.
  TmcHttp buildClient() => TmcHttp(
        client: MockClient((http.Request req) async {
          final String url = req.url.toString();
          calls.add(url);

          if (url.startsWith('https://superflixapi.fun/filme/550')) {
            return _json('{"url":"$masterUrl","audio":"dublado","quality":"1080p"}');
          }
          if (url.startsWith(masterUrl)) return _hls(masterBody);

          return http.Response('not found', 404);
        }),
      );

  VideoResolverService buildResolver() => VideoResolverService(
        http: buildClient(),
        stagger: const Duration(milliseconds: 15),
      );

  test('resolve direto pela API JSON, sem HTML e sem WebView', () async {
    calls = <String>[];
    final VideoResolverService resolver = buildResolver();

    final ResolvedStream? r = await resolver.resolve(ref);

    expect(r, isNotNull);
    expect(r!.providerId, 'superflix_api');
    expect(r.url.toString(), masterUrl);
    expect(r.kind, StreamKind.hls);
    expect(r.headers['Referer'], isNotNull);
    expect(r.headers['User-Agent'], isNotEmpty);
    expect(calls.any((String u) => u.contains('format=json')), isTrue);

    resolver.dispose();
  });

  test('URL suja de anuncio e sanitizada ate o manifesto puro', () async {
    calls = <String>[];
    final TmcHttp http2 = TmcHttp(
      client: MockClient((http.Request req) async {
        final String url = req.url.toString();
        calls.add(url);

        if (url.startsWith('https://superflixapi.fun/filme/550')) {
          return _json(
            '{"url":"https://ads.popads.net/vast/preroll.mp4",'
            '"stream":"https://proxy.x.com/p?url=https%3A%2F%2Fcdn.content.com'
            '%2Fhls%2F998877%2Fmaster.m3u8&utm_source=tmc&zoneid=9"}',
          );
        }
        if (url.startsWith(masterUrl)) return _hls(masterBody);
        return http.Response('not found', 404);
      }),
    );
    final VideoResolverService resolver =
        VideoResolverService(http: http2, stagger: const Duration(milliseconds: 15));

    final ResolvedStream? r = await resolver.resolve(ref);

    expect(r, isNotNull);
    expect(r!.url.toString(), masterUrl);
    expect(r.url.toString().contains('utm_source'), isFalse);
    expect(r.url.toString().contains('popads'), isFalse);

    resolver.dispose();
  });

  test('cache evita nova resolucao e novas chamadas HTTP', () async {
    calls = <String>[];
    final VideoResolverService resolver = buildResolver();

    final ResolvedStream? first = await resolver.resolve(ref);
    expect(first, isNotNull);

    final int afterFirst = calls.length;
    expect(afterFirst, greaterThan(0));

    final ResolvedStream? second = await resolver.resolve(ref);
    expect(second, isNotNull);
    expect(second!.url.toString(), first!.url.toString());
    expect(calls.length, afterFirst, reason: 'cache deve servir sem tocar a rede');

    resolver.dispose();
  });

  test('dedupe: duas chamadas concorrentes viram uma resolucao', () async {
    calls = <String>[];
    final VideoResolverService resolver = buildResolver();

    final List<ResolvedStream?> r = await Future.wait(<Future<ResolvedStream?>>[
      resolver.resolve(ref),
      resolver.resolve(ref),
    ]);

    expect(r[0], isNotNull);
    expect(r[0]!.url.toString(), r[1]!.url.toString());

    resolver.dispose();
  });

  test('exclude remove a unica fonte boa e devolve null', () async {
    calls = <String>[];
    final VideoResolverService resolver = buildResolver();

    final ResolvedStream? r = await resolver.resolve(
      ref,
      force: true,
      exclude: <String>{'superflix_api'},
    );

    expect(r, isNull);
    resolver.dispose();
  });

  test('providerId forca uma fonte especifica', () async {
    calls = <String>[];
    final VideoResolverService resolver = buildResolver();

    final ResolvedStream? r = await resolver.resolve(ref, providerId: 'superflix_api');
    expect(r, isNotNull);
    expect(r!.providerId, 'superflix_api');

    resolver.dispose();
  });

  test('nenhuma API responde -> null (sem excecao)', () async {
    calls = <String>[];
    final VideoResolverService resolver = VideoResolverService(
      http: TmcHttp(
        client: MockClient((http.Request req) async {
          calls.add(req.url.toString());
          return http.Response('not found', 404);
        }),
      ),
      stagger: const Duration(milliseconds: 15),
    );

    final ResolvedStream? r = await resolver.resolve(ref);
    expect(r, isNull);

    resolver.dispose();
  });
}