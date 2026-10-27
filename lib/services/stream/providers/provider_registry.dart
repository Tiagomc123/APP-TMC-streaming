import 'embedcine_provider.dart';
import 'pontofinal_provider.dart';
import 'stream_provider.dart';
import 'superflix_provider.dart';
import 'warezcdn_provider.dart';

class ProviderRegistry {
  ProviderRegistry._();

  /// Ordem base. O resolver reordena por saude em runtime.
  static List<StreamProvider> all() => <StreamProvider>[
        SuperFlixApiProvider(),
        WarezCdnProvider(),
        EmbedCineProvider(),
        PontoFinalProvider(),
      ];
}