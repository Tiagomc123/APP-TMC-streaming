import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mc/core/net/tmc_http.dart';
import 'package:mc/data/models/resolved_stream.dart';
import 'package:mc/services/stream/stream_extractor.dart';

String fixture(String name) => File('test/fixtures/$name').readAsStringSync();

const String masterUrl = 'https://cdn.content.com/hls/998877/master.m3u8';

/// NOTA: os locais usam nomes diferentes do prefixo `http` para nao sombrear
/// o import `package:http/http.dart`.
TmcHttp buildClient(Map<String, http.Response Function()> routes, {List<String>? log}) {
  return TmcHttp(
    client: MockClient((http.Request req) async {
      final String url = req.url.toString();
      log?.add(url);
      for (final MapEntry<String, http.Response Function()> e in routes.entries) {
        if (url.startsWith(e.key)) return e.value();
      }
      return http.Response('not found', 404);
    }),
  );
}

http.Response htmlBody(String body) =>
    http.Response(body, 200, headers: <String, String>{'content-type': 'text/html; charset=utf-8'});

http.Response m3u8Body(String body) =>
    http.Response(body, 200, headers: <String, String>{'content-type': 'application/vnd.apple.mpegurl'});

void main() {
  test('extrai o m3u8 limpo de uma pagina cheia de anuncios', () async {
    final TmcHttp client = buildClient(<String, http.Response Function()>{
      'https://site-player.com/filme/550': () => htmlBody(fixture('player_with_ads.html')),
      masterUrl: () => m3u8Body(fixture('master.m3u8')),
    });

    final ResolvedStream? r = await StreamExtractor(client).resolveFrom(
      Uri.parse('https://site-player.com/filme/550'),
      providerId: 'teste',
      providerLabel: 'Teste',
    );

    expect(r, isNotNull);
    expect(r!.url.toString(), masterUrl);
    expect(r.kind, StreamKind.hls);
    expect(r.providerLabel, 'Teste');

    // headers que o player vai reenviar em toda requisicao
    expect(r.headers['Referer'], contains('site-player.com'));
    expect(r.headers['User-Agent'], isNotEmpty);

    // o master foi lido e as variantes ficaram disponiveis
    expect(r.variants.length, 2);
    expect(r.variants.first.url, contains('720p.m3u8'));
  });

  test('segue iframe ate o player final', () async {
    final TmcHttp client = buildClient(<String, http.Response Function()>{
      'https://embedcine.com/filme/550': () => htmlBody(fixture('embedcine_iframe.html')),
      'https://player.embedcine.com/embed/abc123': () => htmlBody(fixture('player_with_ads.html')),
      masterUrl: () => m3u8Body(fixture('master.m3u8')),
    });

    final ResolvedStream? r = await StreamExtractor(client).resolveFrom(
      Uri.parse('https://embedcine.com/filme/550'),
      providerId: 'embedcine',
      providerLabel: 'EmbedCine',
    );

    expect(r, isNotNull);
    expect(r!.url.toString(), masterUrl);
    expect(r.headers['Referer'], contains('player.embedcine.com'));
  });

  test('descarta candidato morto (probe 404) e tenta o proximo', () async {
    const String first = 'https://cdn.x.com/a/master.m3u8';
    const String second = 'https://cdn.x.com/b/master.m3u8';

    final TmcHttp client = buildClient(<String, http.Response Function()>{
      'https://site-player.com/filme/550': () =>
          htmlBody('<script>var a = "$first"; var b = "$second";</script>'),
      first: () => http.Response('gone', 404),
      second: () => m3u8Body(fixture('master.m3u8')),
    });

    final ResolvedStream? r = await StreamExtractor(client).resolveFrom(
      Uri.parse('https://site-player.com/filme/550'),
      providerId: 'teste',
      providerLabel: 'Teste',
    );

    expect(r, isNotNull);
    expect(r!.url.toString(), second);
  });

  test('pagina so com anuncios devolve null', () async {
    final TmcHttp client = buildClient(<String, http.Response Function()>{
      'https://site-player.com/filme/550': () => htmlBody(fixture('dead_ads_only.html')),
    });

    final ResolvedStream? r = await StreamExtractor(client).resolveFrom(
      Uri.parse('https://site-player.com/filme/550'),
      providerId: 'teste',
      providerLabel: 'Teste',
    );

    expect(r, isNull);
  });
}