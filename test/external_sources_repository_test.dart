import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mc/data/repositories/external_sources_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _PendingClient extends http.BaseClient {
  final Completer<http.StreamedResponse> response =
      Completer<http.StreamedResponse>();
  bool requested = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    requested = true;
    return response.future;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('returns cached sources without waiting for Supabase refresh', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final _PendingClient client = _PendingClient();
    final ExternalSourcesRepository repository = ExternalSourcesRepository(
      client: client,
    );

    final Map<String, List<String>> sources = await repository.load().timeout(
      const Duration(milliseconds: 300),
    );

    expect(sources, isEmpty);
    expect(client.requested, isTrue);

    client.response.complete(
      http.StreamedResponse(
        Stream<List<int>>.value(
          utf8.encode('{"domains":{"superflix_api":["https://example.com"]}}'),
        ),
        200,
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));
    client.close();
  });
}
