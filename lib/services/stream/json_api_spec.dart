import '../../data/models/media_ref.dart';

enum JsonApiMode { deepCollect, playlistField }

/// =============================================================================
///  DESCRICAO DECLARATIVA DE UMA API JSON
///
///  Adicionar uma fonte nova = adicionar um item em [jsonApiSpecs].
///  Nao existe mais codigo de scraping especifico por site.
///
///  Placeholders suportados nos caminhos: {id} (TMDB), {imdb}, {s}, {e}.
/// =============================================================================
class JsonApiSpec {
  const JsonApiSpec({
    required this.id,
    required this.label,
    required this.priority,
    required this.bases,
    required this.moviePaths,
    required this.tvPaths,
    this.mode = JsonApiMode.deepCollect,
    this.followPages = true,
  });

  final String id;
  final String label;
  final int priority;
  final List<String> bases;
  final List<String> moviePaths;
  final List<String> tvPaths;
  final JsonApiMode mode;

  /// Se o JSON nao trouxer midia, tenta 1 salto HTTP na pagina retornada.
  final bool followPages;

  List<String> pathsFor(MediaRef ref) => ref.isTv ? tvPaths : moviePaths;

  /// Devolve null quando o caminho exige um dado que nao temos.
  String? build(MediaRef ref, String path) {
    if (path.contains('{imdb}') && ref.imdbId.isEmpty) return null;
    return path
        .replaceAll('{id}', '${ref.tmdbId}')
        .replaceAll('{imdb}', ref.imdbId)
        .replaceAll('{s}', '${ref.season}')
        .replaceAll('{e}', '${ref.episode}');
  }
}

const List<JsonApiSpec> jsonApiSpecs = <JsonApiSpec>[
  JsonApiSpec(
    id: 'superflix_api',
    label: 'SuperFlix',
    priority: 10,
    bases: <String>[
      'https://superflixapi.fun',
      'https://superflixapi.pro',
      'https://superflixapi.sbs',
      'https://superflixapi.top',
      'https://superflixapi.online',
      'https://superflixapi.xyz',
    ],
    moviePaths: <String>['filme/{id}?format=json', 'filme/{imdb}?format=json'],
    tvPaths: <String>[
      'serie/{id}/{s}/{e}?format=json',
      'serie/{imdb}/{s}/{e}?format=json',
    ],
  ),
  JsonApiSpec(
    id: 'vidlink',
    label: 'VidLink',
    priority: 12,
    bases: <String>['https://vidlink.pro'],
    moviePaths: <String>[
      'api/b/movie/{id}?multiLang=1',
      'api/b/movie/{id}?multiLang=0',
    ],
    tvPaths: <String>[
      'api/b/tv/{id}/{s}/{e}?multiLang=1',
      'api/b/tv/{id}/{s}/{e}?multiLang=0',
    ],
    mode: JsonApiMode.playlistField,
    followPages: false,
  ),
  JsonApiSpec(
    id: 'warezcdn',
    label: 'WarezCDN',
    priority: 18,
    bases: <String>['https://warezcdn.com', 'https://warezcdn.net'],
    moviePaths: <String>['getPlayer.php?id={id}&type=movie'],
    tvPaths: <String>[
      'getPlayer.php?id={id}&type=serie&season={s}&episode={e}',
    ],
  ),
  JsonApiSpec(
    id: 'pontofinal',
    label: 'PontoFinal',
    priority: 22,
    bases: <String>['https://pontofinal.org'],
    moviePaths: <String>['api/filme/{id}', 'filme/{id}?format=json'],
    tvPaths: <String>[
      'api/serie/{id}/{s}/{e}',
      'serie/{id}/{s}/{e}?format=json',
    ],
  ),
  JsonApiSpec(
    id: 'embedcine',
    label: 'EmbedCine',
    priority: 28,
    bases: <String>[
      'https://embedcine.com',
      'https://embedcine.top',
      'https://embedcine.xyz',
      'https://embedcine.net',
      'https://embedcine.tv',
    ],
    moviePaths: <String>['filme/{id}', 'movie/{id}'],
    tvPaths: <String>['serie/{id}/{s}/{e}', 'tv/{id}/{s}/{e}'],
  ),
];
