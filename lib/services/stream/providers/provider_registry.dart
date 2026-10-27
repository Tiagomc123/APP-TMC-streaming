import 'embedcine_provider.dart';
import 'pobreflix_provider.dart';
import 'pontofinal_provider.dart';
import 'stream_provider.dart';
import 'superflix_provider.dart';
import 'warezcdn_provider.dart';

class ProviderRegistry {
  ProviderRegistry._();

  /// Ordem base. O resolver reordena por saude em runtime.
  /// SuperFlix (API JSON) primeiro; PobreFlix em seguida; os scrapers de
  /// HTML ficam por ultimo por serem mais sensiveis a mudanca de layout.
  static List<StreamProvider> all() => <StreamProvider>[
        SuperFlixApiProvider(),
        PobreFlixProvider(),
        WarezCdnProvider(),
        EmbedCineProvider(),
        PontoFinalProvider(),
      ];
}