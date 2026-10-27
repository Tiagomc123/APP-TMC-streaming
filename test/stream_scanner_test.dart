import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mc/services/stream/stream_scanner.dart';

String fixture(String name) => File('test/fixtures/$name').readAsStringSync();

final Uri base = Uri.parse('https://site-player.com/filme/550');

/// Hosts que NUNCA podem chegar ao player.
void expectNoAds(List<StreamCandidate> candidates) {
  const List<String> banned = <String>[
    'doubleclick.net',
    'popads.net',
    'adnxs.com',
    'popcash.net',
    'adf.ly',
    'onclckds.com',
    'pubads',
  ];
  for (final StreamCandidate c in candidates) {
    for (final String host in banned) {
      expect(c.url.contains(host), isFalse, reason: 'anuncio vazou: ${c.url}');
    }
  }
}

void main() {
  group('StreamScanner.isAdUrl', () {
    test('marca redes de anuncio e intermediarios', () {
      expect(StreamScanner.isAdUrl('https://pubads.g.doubleclick.net/gampad/ads?iu=/1'), isTrue);
      expect(StreamScanner.isAdUrl('https://ads.popads.net/vast/preroll.mp4'), isTrue);
      expect(StreamScanner.isAdUrl('https://adf.ly/abc'), isTrue);
      expect(StreamScanner.isAdUrl('https://cdn.popcash.net/pop.php'), isTrue);
      expect(StreamScanner.isAdUrl('javascript:void(0)'), isTrue);
      expect(StreamScanner.isAdUrl('https://cdn.content.com/hls/master.m3u8'), isFalse);
      expect(StreamScanner.isAdUrl('https://cdn.superflix.fun/hls/777/playlist.m3u8'), isFalse);
    });
  });

  group('StreamScanner.normalize', () {
    test('desescapa JSON embutido e entidades HTML', () {
      expect(StreamScanner.normalize(r'https:\/\/cdn.x.com\/a.m3u8'), 'https://cdn.x.com/a.m3u8');
      expect(StreamScanner.normalize(r'a\u002Fb'), 'a/b');
      expect(StreamScanner.normalize('x&amp;y'), 'x&y');
    });
  });

  group('StreamScanner.unpackJs', () {
    test('desempacota o packer Dean Edwards', () {
      final String html = fixture('warezcdn_packed.html');
      final String? unpacked = StreamScanner.unpackJs(StreamScanner.normalize(html));
      expect(unpacked, isNotNull);
      expect(unpacked, contains('https://cdn.hls.fun/f/1/2.m3u8'));
    });

    test('devolve null quando nao ha packer', () {
      expect(StreamScanner.unpackJs('<html><body>nada</body></html>'), isNull);
    });
  });

  group('StreamScanner.decodeBase64Blobs', () {
    test('decodifica atob()', () {
      final String decoded = StreamScanner.decodeBase64Blobs(fixture('atob_obfuscated.html'));
      expect(decoded, contains('https://cdn.atob.io/vod/master.m3u8'));
    });
  });

  group('StreamScanner.scan - anti-anuncio', () {
    test('player com preroll + iframe de ad: escolhe o master do conteudo', () {
      final List<StreamCandidate> c =
          StreamScanner.scan(fixture('player_with_ads.html'), base: base);

      expect(c, isNotEmpty);
      expect(c.first.url, 'https://cdn.content.com/hls/998877/master.m3u8');
      expect(c.first.kind, CandidateKind.hls);
      expectNoAds(c);

      // as variantes ficam disponiveis para o seletor de qualidade
      expect(
        c.map((StreamCandidate e) => e.url).toList(),
        contains('https://cdn.content.com/hls/998877/1080p.m3u8'),
      );
    });

    test('JS empacotado: extrai o m3u8 escondido e descarta o iframe de ad', () {
      final List<StreamCandidate> c =
          StreamScanner.scan(fixture('warezcdn_packed.html'), base: base);

      expect(c.length, 1, reason: 'so o m3u8 real deve sobrar');
      expect(c.first.url, 'https://cdn.hls.fun/f/1/2.m3u8');
      expect(c.first.kind, CandidateKind.hls);
      expectNoAds(c);
    });

    test('base64/atob: extrai o m3u8 ofuscado', () {
      final List<StreamCandidate> c =
          StreamScanner.scan(fixture('atob_obfuscated.html'), base: base);

      expect(c.length, 1);
      expect(c.first.url, 'https://cdn.atob.io/vod/master.m3u8');
      expectNoAds(c);
    });

    test('og:video tem prioridade sobre teaser em script', () {
      final List<StreamCandidate> c = StreamScanner.scan(fixture('og_video.html'), base: base);

      expect(c.first.url, 'https://cdn.filmes.tv/hls/4242/master.m3u8');
      expect(c.first.kind, CandidateKind.hls);
      expectNoAds(c);
    });

    test('og:video de preview perde para o stream principal', () {
      final List<StreamCandidate> c =
          StreamScanner.scan(fixture('trailer_penalty.html'), base: base);

      expect(c.first.url, 'https://cdn.movie.io/vod/master.m3u8');
      expect(c.first.kind, CandidateKind.hls);
      expect(
        c.where((StreamCandidate e) => e.url.contains('preview.mp4')).length,
        1,
        reason: 'o preview continua na lista, mas atras',
      );
    });

    test('pagina so com iframe: devolve o embed e descarta o banner', () {
      final List<StreamCandidate> c =
          StreamScanner.scan(fixture('embedcine_iframe.html'), base: base);

      expect(c.length, 1);
      expect(c.first.kind, CandidateKind.iframe);
      expect(c.first.url, 'https://player.embedcine.com/embed/abc123');
      expectNoAds(c);
    });

    test('pagina so com anuncios: lista vazia', () {
      final List<StreamCandidate> c =
          StreamScanner.scan(fixture('dead_ads_only.html'), base: base);
      expect(c, isEmpty);
    });

    test('JSON de API: escolhe o stream e ignora o mp4 de anuncio', () {
      final List<StreamCandidate> c =
          StreamScanner.scan(fixture('superflix_api.json'), base: base);

      expect(c, isNotEmpty);
      expect(c.first.kind, CandidateKind.hls);
      expect(c.first.url, contains('playlist.m3u8'));
      expectNoAds(c);
    });

    test('resolve URLs relativas contra a pagina', () {
      final List<StreamCandidate> c = StreamScanner.scan(
        '<script>var f = "/vod/relativo/master.m3u8";</script>',
        base: Uri.parse('https://site.com/pasta/pagina'),
      );
      expect(c.first.url, 'https://site.com/vod/relativo/master.m3u8');
    });

    test('a lista sai ordenada por score decrescente', () {
      final List<StreamCandidate> c =
          StreamScanner.scan(fixture('player_with_ads.html'), base: base);
      for (int i = 1; i < c.length; i++) {
        expect(c[i - 1].score >= c[i].score, isTrue);
      }
    });

    test('HTML vazio nao explode', () {
      expect(StreamScanner.scan('', base: base), isEmpty);
      expect(StreamScanner.scan('<html></html>', base: base), isEmpty);
    });
  });
}