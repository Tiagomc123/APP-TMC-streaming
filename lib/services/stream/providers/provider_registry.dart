import '../json_api_provider.dart';
import '../json_api_spec.dart';
import 'stream_provider.dart';

/// Registro de fontes. Todas sao APIs JSON: nenhuma depende de pagina HTML
/// nem de WebView. A ordem base vem da prioridade do spec; o resolver
/// reordena por saude em runtime.
class ProviderRegistry {
  ProviderRegistry._();

  static List<StreamProvider> all() => jsonApiSpecs
      .map((JsonApiSpec spec) => JsonApiProvider(spec))
      .toList();
}