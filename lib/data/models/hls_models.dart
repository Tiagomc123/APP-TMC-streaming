class HlsVariant {
  const HlsVariant({required this.url, required this.bandwidth, required this.label});
  final String url;
  final int bandwidth;
  final String label;
}

class HlsAudioTrack {
  const HlsAudioTrack({required this.name, required this.lang, required this.url});
  final String name;
  final String lang;
  final String url;
}

class HlsSubtitleTrack {
  const HlsSubtitleTrack({required this.name, required this.lang, required this.url});
  final String name;
  final String lang;
  final String url;
}