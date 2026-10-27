import 'hls_models.dart';

enum StreamKind { hls, mp4, embed }

class ResolvedStream {
  const ResolvedStream({
    required this.url,
    required this.kind,
    required this.providerId,
    required this.providerLabel,
    required this.headers,
    this.embedPage,
    this.variants = const <HlsVariant>[],
    this.audioTracks = const <HlsAudioTrack>[],
    this.subtitleTracks = const <HlsSubtitleTrack>[],
    this.qualityLabel = '',
  });

  final Uri url;
  final StreamKind kind;
  final String providerId;
  final String providerLabel;
  final Map<String, String> headers;
  final Uri? embedPage;
  final List<HlsVariant> variants;
  final List<HlsAudioTrack> audioTracks;
  final List<HlsSubtitleTrack> subtitleTracks;
  final String qualityLabel;

  bool get playable => kind != StreamKind.embed;
  bool get hasQualityOptions => variants.length > 1;
  bool get hasAudioOptions => audioTracks.length > 1;

  ResolvedStream copyWith({
    Uri? url,
    String? qualityLabel,
    Map<String, String>? headers,
  }) =>
      ResolvedStream(
        url: url ?? this.url,
        kind: kind,
        providerId: providerId,
        providerLabel: providerLabel,
        headers: headers ?? this.headers,
        embedPage: embedPage,
        variants: variants,
        audioTracks: audioTracks,
        subtitleTracks: subtitleTracks,
        qualityLabel: qualityLabel ?? this.qualityLabel,
      );

  /// Devolve uma copia com a ordem das faixas de audio trocada
  /// (usado para colocar o PT-BR na frente sem mutar listas const).
  ResolvedStream reorderAudio(List<HlsAudioTrack> ordered) => ResolvedStream(
        url: url,
        kind: kind,
        providerId: providerId,
        providerLabel: providerLabel,
        headers: headers,
        embedPage: embedPage,
        variants: variants,
        audioTracks: ordered,
        subtitleTracks: subtitleTracks,
        qualityLabel: qualityLabel,
      );
}