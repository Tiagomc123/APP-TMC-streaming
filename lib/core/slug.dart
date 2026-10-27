/// Utilitarios de texto para montar URLs amigaveis dos sites de origem.
class Slug {
  Slug._();

  static const Map<String, String> _map = <String, String>{
    'Ã¡': 'a', 'Ã ': 'a', 'Ã£': 'a', 'Ã¢': 'a', 'Ã¤': 'a', 'Ã¥': 'a',
    'Ã©': 'e', 'Ã¨': 'e', 'Ãª': 'e', 'Ã«': 'e',
    'Ã­': 'i', 'Ã¬': 'i', 'Ã®': 'i', 'Ã¯': 'i',
    'Ã³': 'o', 'Ã²': 'o', 'Ãµ': 'o', 'Ã´': 'o', 'Ã¶': 'o',
    'Ãº': 'u', 'Ã¹': 'u', 'Ã»': 'u', 'Ã¼': 'u',
    'Ã§': 'c', 'Ã±': 'n', 'Ã½': 'y', 'Ã¿': 'y',
  };

  static final RegExp _keep = RegExp('[a-z0-9]');
  static final RegExp _dashes = RegExp('-+');
  static final RegExp _edges = RegExp(r'^-+|-+$');

  /// "Homem-Aranha: Um Novo Dia" -> "homem-aranha-um-novo-dia"
  static String of(String input) {
    final String lower = input.toLowerCase().trim();
    final StringBuffer out = StringBuffer();
    for (final int rune in lower.runes) {
      final String ch = String.fromCharCode(rune);
      final String mapped = _map[ch] ?? ch;
      out.write(_keep.hasMatch(mapped) ? mapped : '-');
    }
    return out
        .toString()
        .replaceAll(_dashes, '-')
        .replaceAll(_edges, '');
  }
}