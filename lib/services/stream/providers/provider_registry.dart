import '../json_api_provider.dart';
import '../json_api_spec.dart';
import 'pobreflix_provider.dart';
import 'stream_provider.dart';

/// =============================================================================
/// Fontes JSON declarativas e PobreFlix. A página de player só é aberta na
/// WebView quando a fonte não consegue fornecer um manifesto direto.
/// =============================================================================
class ProviderRegistry {
  ProviderRegistry._();

  static List<StreamProvider> all() => <StreamProvider>[
    for (final JsonApiSpec spec in jsonApiSpecs) JsonApiProvider(spec),
    PobreFlixProvider(),
  ];
}
