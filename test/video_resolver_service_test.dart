import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mc/core/net/tmc_http.dart';
import 'package:mc/data/models/media_ref.dart';
import 'package:mc/data/models/resolved_stream.dart';
import 'package:mc/services/stream/video_resolver_service.dart';
import 'package:mc/services/stream/providers/vidlink_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

String fixture(String name) => File('test/fixtures/$name').readAsStringSync();

const String masterUrl = 'https://cdn.content.com/hls/998877/master.m3u8';
const MediaRef ref = MediaRef(tmdbId: 550, isTv: false, title: 'Filme Teste');

http.Response _html(String body) =>
    http.Response(body, 200, headers: <String, String>{'content-type': 'text/html; charset=utf-8'});

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  late List<String> calls;

  TmcHttp buildClient() => TmcHttp(
        client: MockClient((http.Request req) async {
          final String url = req.url.toString();
          calls.add(url);

          // SuperFlix API responde, mas com URL MORTA -> deve cair para o proximo
          if (url.startsWith('https://superflixapi.fun/filme/550')) {
            return http.Response(fixture('superflix_api_dead.json'), 200,
                headers: <String, String>{'content-type': 'application/json'});
          }
          if (url.startsWith('https://superflixapi.best/filme/550')) {
            return http.Response('gone', 404);
          }

          // WarezCDN: pagina sem stream nem iframe
          if (url.startsWith('https://warezcdn.com/embed/filme.php')) {
            return _html(fixture('dead_ads_only.html'));
          }

          // EmbedCine: iframe -> player -> m3u8 vivo
          if (url.startsWith('https://embedcine.com/filme/550')) {
            return _html(fixture('embedcine_iframe.html'));
          }
          if (url.startsWith('https://player.embedcine.com/embed/abc123')) {
            return _html(fixture('player_with_ads.html'));
          }
          if (url.startsWith(masterUrl)) {
            return http.Response(fixture('master.m3u8'), 200,
                headers: <String, String>{'content-type': 'application/vnd.apple.mpegurl'});
          }

          return http.Response('not found', 404);
        }),
      );

  VideoResolverService buildResolver() => VideoResolverService(
        http: buildClient(),
        stagger: const Duration(milliseconds: 15),
      );

  test('cai para a proxima fonte quando as anteriores falham', () async {
    calls = <String>[];
    final VideoResolverService resolver = buildResolver();

    final ResolvedStream? r = await resolver.resolve(ref);

    expect(r, isNotNull);
    expect(r!.providerId, 'embedcine');
    expect(r.url.toString(), masterUrl);
    expect(r.variants, isNotEmpty);

    expect(calls.any((String u) => u.contains('superflixapi.fun')), isTrue);
    expect(calls.any((String u) => u.contains('warezcdn.com')), isTrue);

    resolver.dispose();
  });

  test('nenhum anuncio vaza para o stream resolvido', () async {
    calls = <String>[];
    final VideoResolverService resolver = buildResolver();

    final ResolvedStream? r = await resolver.resolve(ref);
    expect(r, isNotNull);

    const List<String> banned = <String>[
      'doubleclick', 'popads', 'adnxs', 'popcash', 'adf.ly', 'onclckds',
    ];
    for (final String host in banned) {
      expect(r!.url.toString().contains(host), isFalse, reason: 'ad vazou: ${r.url}');
    }

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

  test('exclude remove a fonte boa e devolve null', () async {
    calls = <String>[];
    final VideoResolverService resolver = buildResolver();

    final ResolvedStream? r = await resolver.resolve(
      ref,
      force: true,
      exclude: <String>{'embedcine'},
    );

    expect(r, isNull);
    resolver.dispose();
  });

  test('providerId forca uma fonte especifica', () async {
    calls = <String>[];
    final VideoResolverService resolver = buildResolver();

    final ResolvedStream? r = await resolver.resolve(ref, providerId: 'embedcine');
    expect(r, isNotNull);
    expect(r!.providerId, 'embedcine');

    resolver.dispose();
  });

  test('fallback do VidLink monta rota de filme e episódio', () {
    expect(
      VidLinkProvider.pageFor(ref).toString(),
      'https://vidlink.pro/movie/550?autoplay=true',
    );
    expect(
      VidLinkProvider.pageFor(
        const MediaRef(
          tmdbId: 1399,
          isTv: true,
          title: 'Série Teste',
          season: 2,
          episode: 3,
        ),
      ).toString(),
      'https://vidlink.pro/tv/1399/2/3?autoplay=true',
    );
  });
}
