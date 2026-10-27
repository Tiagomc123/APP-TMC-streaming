import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mc/core/net/tmc_http.dart';
import 'package:mc/data/models/media_ref.dart';
import 'package:mc/data/models/resolved_stream.dart';
import 'package:mc/services/stream/providers/pobreflix_provider.dart';
import 'package:mc/services/stream/providers/provider_registry.dart';
import 'package:mc/services/stream/providers/stream_provider.dart';
import 'package:mc/ui/screens/player_screen.dart';

void main() {
  test('mantém registradas as seis fontes anteriores e atuais', () {
    final Set<String> ids = ProviderRegistry.all()
        .map((StreamProvider provider) => provider.id)
        .toSet();
    expect(
      ids,
      containsAll(<String>{
        'superflix_api',
        'vidlink',
        'warezcdn',
        'pontofinal',
        'embedcine',
        'pobreflix',
      }),
    );
  });

  test(
    'página embed é direcionada para o player web, não para o player MPV',
    () {
      final ResolvedStream embed = ResolvedStream(
        url: Uri.parse('https://player.example/embed/550'),
        kind: StreamKind.embed,
        providerId: 'pobreflix',
        providerLabel: 'PobreFlix',
        headers: <String, String>{},
      );
      final ResolvedStream hls = ResolvedStream(
        url: Uri.parse('https://cdn.example/movie.m3u8'),
        kind: StreamKind.hls,
        providerId: 'vidlink',
        providerLabel: 'VidLink',
        headers: <String, String>{},
      );

      expect(usesWebPlayerFallback(embed), isTrue);
      expect(usesWebPlayerFallback(hls), isFalse);
    },
  );

  test(
    'limita tentativas sequenciais para não estourar o timeout do player',
    () async {
      final List<Uri> requests = <Uri>[];
      final TmcHttp httpClient = TmcHttp(
        client: MockClient((http.Request request) async {
          requests.add(request.url);
          return http.Response('not found', 404);
        }),
      );
      const MediaRef ref = MediaRef(
        tmdbId: 550,
        isTv: false,
        title: 'Fight Club',
      );
      final ResolverContext context = ResolverContext(
        http: httpClient,
        ref: ref,
        emit: (
          String _, {
          String? providerId,
          int attempt = 0,
          int total = 0,
        }) {},
        sources: const <String, List<String>>{},
      );

      await PobreFlixProvider().resolve(ref, context);

      expect(requests, hasLength(lessThanOrEqualTo(10)));
      httpClient.close();
    },
  );
}
