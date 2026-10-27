// =====================================================================
//  TMC - REGISTRO DE DOMINIOS ANTI-QUEDA
//  ------------------------------------------------------------------
//  * Pools de espelhos por servico + sondagem paralela em runtime.
//  * Registro remoto (Supabase Edge Function "tmc-sources").
//  * Auto-cura: le o dominio que a propria API devolve.
//  * Cache local com precedencia: remoto > cache > lista embutida.
// =====================================================================

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

const String kUserAgent =
    'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36';

const String kSupabaseBase = 'https://xjqdiulxrprxegfrufyf.supabase.co';
const String kSupabaseKey = 'sb_publishable_XyCk8TPrdGOzUrrr-59PpQ__dBWOFb9';
const String kRegistryUrl = '$kSupabaseBase/functions/v1/tmc-sources';

const String kSondaApi = '/lista?category=canais&limit=1&format=json';

/// Um servico e um conjunto de espelhos. O app escolhe o que responde.
class Dominio {
  final String id;
  final String rotulo;
  final List<String> espelhos;
  final String sonda;

  const Dominio(this.id, this.rotulo, this.espelhos, {this.sonda = '/'});
}

const List<Dominio> kDominiosPadrao = <Dominio>[
  Dominio('superflix', 'SuperFlixAPI', <String>[
    'https://superflixapi.fun',
    'https://superflixapi.pro',
    'https://superflixapi.sbs',
    'https://superflixapi.top',
    'https://superflixapi.online',
    'https://superflixapi.site',
    'https://superflixapi.store',
    'https://superflixapi.xyz',
    'https://superflixapi.app',
    'https://superflixapi.net',
    'https://superflixapi.me',
    'https://superflixapi.live',
  ], sonda: kSondaApi),
  Dominio('pobreflix', 'PobreFlixHD', <String>[
    'https://pobreflixhd.sbs',
    'https://pobreflixhd.top',
    'https://pobreflixhd.tv',
    'https://pobreflixhd.online',
    'https://pobreflixhd.site',
    'https://pobreflixhd.xyz',
    'https://pobreflixhd.app',
    'https://pobreflixhd.net',
  ]),
  Dominio('embedcine', 'EmbedCine', <String>[
    'https://embedcine.com',
    'https://embedcine.top',
    'https://embedcine.xyz',
    'https://embedcine.net',
    'https://embedcine.tv',
  ]),
  Dominio('warezcdn', 'WarezCDN', <String>[
    'https://warezcdn.com',
    'https://warezcdn.net',
    'https://warezcdn.tv',
    'https://warezcdn.xyz',
    'https://warezcdn.top',
  ]),
  Dominio('vidsrcxyz', 'VidSrc XYZ', <String>[
    'https://vidsrc.xyz',
    'https://vidsrc.net',
    'https://vidsrc.vip',
    'https://vidsrc.icu',
    'https://vidsrc.pm',
  ]),
  Dominio('vidsrccc', 'VidSrc CC', <String>[
    'https://vidsrc.cc',
    'https://vidsrc.to',
    'https://vidsrc.me',
    'https://vidsrc.sh',
  ]),
  Dominio('vidsrcmov', 'VidSrc MOV', <String>[
    'https://vidsrc.mov',
    'https://vidsrc.buzz',
    'https://vidsrc.hair',
  ]),
  Dominio('vidlink', 'VidLink', <String>['https://vidlink.pro']),
  Dominio('embedsu', 'Embed.su', <String>['https://embed.su']),
  Dominio('moviesapi', 'MoviesAPI', <String>[
    'https://moviesapi.club',
    'https://moviesapi.to',
  ]),
  Dominio('twembed', '2Embed', <String>[
    'https://www.2embed.cc',
    'https://www.2embed.to',
    'https://www.2embed.skin',
    'https://2embed.stream',
  ]),
  Dominio('smashy', 'SmashyStream', <String>['https://player.smashy.stream']),
  Dominio('autoembed', 'AutoEmbed', <String>[
    'https://player.autoembed.cc',
    'https://autoembed.co',
    'https://autoembed.me',
    'https://autoembed.app',
  ]),
  Dominio('m111', '111Movies', <String>['https://111movies.com']),
  Dominio('vidbinge', 'VidBinge', <String>['https://vidbinge.dev']),
  Dominio('videasy', 'Videasy', <String>['https://player.videasy.net']),
  Dominio('multiembed', 'MultiEmbed', <String>['https://multiembed.mov']),
  Dominio('vidfast', 'VidFast', <String>['https://vidfast.pro']),
  Dominio('vidcore', 'VidCore', <String>['https://vidcore.org']),
  Dominio('embedwave', 'EmbedWave', <String>['https://embedwave.cc']),
  Dominio('vixsrc', 'VixSrc', <String>['https://vixsrc.to']),
  Dominio('nontongo', 'NontonGo', <String>['https://nontongo.win']),
];

class Dominios {
  static SharedPreferences? _prefs;
  static final Map<String, String> _ativos = <String, String>{};
  static final Map<String, bool> _status = <String, bool>{};
  static final Map<String, int> _ms = <String, int>{};
  static final ValueNotifier<int> revisao = ValueNotifier<int>(0);
  static final List<Dominio> _lista = List<Dominio>.from(kDominiosPadrao);
  static String _registroInfo = 'lista interna';
  static DateTime? _ultimaSonda;
  static bool _sondando = false;

  static void anexar(SharedPreferences p) => _prefs = p;

  static List<Dominio> get lista => _lista;
  static String get infoRegistro => _registroInfo;
  static DateTime? get ultimaSonda => _ultimaSonda;
  static bool get sondando => _sondando;

  static String get(String id) {
    final String? a = _ativos[id];
    if (a != null && a.isNotEmpty) return a;
    for (final Dominio d in _lista) {
      if (d.id == id && d.espelhos.isNotEmpty) return d.espelhos.first;
    }
    return '';
  }

  static bool? vivo(String id) => _status[id];
  static int latencia(String id) => _ms[id] ?? -1;

  static Dominio? porId(String id) {
    for (final Dominio d in _lista) {
      if (d.id == id) return d;
    }
    return null;
  }

  // --------------------------- CACHE --------------------------------
  static Future<void> carregarCache() async {
    final SharedPreferences? p = _prefs;
    if (p == null) return;
    try {
      final String raw = p.getString('tmc_dom_remoto') ?? '';
      if (raw.isNotEmpty) _aplicarRemoto(jsonDecode(raw), 'cache remoto');
    } catch (_) {}
    try {
      final String raw = p.getString('tmc_dom_ativos') ?? '';
      if (raw.isNotEmpty) {
        final Map<String, dynamic> m = jsonDecode(raw) as Map<String, dynamic>;
        m.forEach((String k, dynamic v) {
          final String s = v.toString();
          if (s.startsWith('http')) _ativos[k] = s;
        });
      }
    } catch (_) {}
  }

  static Future<void> salvarCache() async {
    final SharedPreferences? p = _prefs;
    if (p == null) return;
    try {
      await p.setString('tmc_dom_ativos', jsonEncode(_ativos));
    } catch (_) {}
  }

  // -------------------------- REGISTRO ------------------------------
  static void _aplicarRemoto(dynamic j, String origem) {
    if (j is! Map) return;
    final dynamic d = j['domains'];
    if (d is! Map) return;
    int n = 0;
    for (final Dominio base in kDominiosPadrao) {
      final dynamic v = d[base.id];
      if (v is List && v.isNotEmpty) {
        final List<String> novos = v
            .map((dynamic e) => e.toString())
            .where((String s) => s.startsWith('http'))
            .toList();
        if (novos.isEmpty) continue;
        final int i = _lista.indexWhere((Dominio x) => x.id == base.id);
        if (i < 0) continue;
        _lista[i] = Dominio(base.id, base.rotulo, novos, sonda: base.sonda);
        n++;
      }
    }
    if (n > 0) {
      _registroInfo = 'remoto ($origem, $n servicos)';
      revisao.value++;
    }
  }

  static Future<bool> atualizarRemoto() async {
    try {
      final http.Response r = await http.get(
        Uri.parse(kRegistryUrl),
        headers: <String, String>{'apikey': kSupabaseKey},
      ).timeout(const Duration(seconds: 12));
      if (r.statusCode != 200) return false;
      final dynamic j = jsonDecode(utf8.decode(r.bodyBytes));
      _aplicarRemoto(j, 'supabase');
      try {
        await _prefs?.setString('tmc_dom_remoto', jsonEncode(j));
      } catch (_) {}
      return true;
    } catch (_) {
      return false;
    }
  }

  // --------------------------- SONDAGEM -----------------------------
  static Future<bool> _respira(String base, String sonda) async {
    final Stopwatch sw = Stopwatch()..start();
    try {
      final http.Response r = await http.get(
        Uri.parse('$base$sonda'),
        headers: <String, String>{'User-Agent': kUserAgent, 'Accept': '*/*'},
      ).timeout(const Duration(seconds: 6));
      _ms[base] = sw.elapsedMilliseconds;
      return r.statusCode > 0 && r.statusCode < 600;
    } catch (_) {
      _ms[base] = -1;
      return false;
    }
  }

  static Future<String?> _melhor(Dominio d) async {
    final List<String> c = d.espelhos.take(5).toList();
    if (c.isEmpty) return null;
    final List<Future<String?>> fs = c
        .map((String e) async => (await _respira(e, d.sonda)) ? e : null)
        .toList();
    final List<String?> r = await Future.wait(fs);
    for (int i = 0; i < r.length; i++) {
      _status['${d.id}#${c[i]}'] = r[i] != null;
      if (r[i] != null) return r[i];
    }
    return null;
  }

  static Future<void> sondarTodos() async {
    if (_sondando) return;
    _sondando = true;
    revisao.value++;
    final List<Dominio> copia = List<Dominio>.from(_lista);
    await Future.wait(copia.map((Dominio d) async {
      final String? ok = await _melhor(d);
      if (ok != null) {
        _ativos[d.id] = ok;
        _status[d.id] = true;
      } else {
        _status[d.id] = false;
        if ((_ativos[d.id] ?? '').isEmpty && d.espelhos.isNotEmpty) {
          _ativos[d.id] = d.espelhos.first;
        }
      }
    }));
    _ultimaSonda = DateTime.now();
    await salvarCache();
    await _autocorrigir();
    _sondando = false;
    revisao.value++;
  }

  static Future<void> sondar(String id) async {
    final Dominio? d = porId(id);
    if (d == null) return;
    final String? ok = await _melhor(d);
    _status[id] = ok != null;
    if (ok != null) {
      _ativos[id] = ok;
      await salvarCache();
    }
    revisao.value++;
  }

  /// A propria API devolve links apontando para o dominio dela.
  /// Se o host mudou, o app se corrige sozinho.
  static Future<void> _autocorrigir() async {
    final String base = _ativos['superflix'] ?? '';
    if (base.isEmpty) return;
    try {
      final http.Response r = await http.get(
        Uri.parse('$base/lista?category=canais&limit=5&format=json'),
        headers: <String, String>{'User-Agent': kUserAgent},
      ).timeout(const Duration(seconds: 10));
      if (r.statusCode != 200) return;
      final RegExp re = RegExp(
          r'https?://[a-z0-9.-]*(?:superflix|superflixapi)[a-z0-9.-]*',
          caseSensitive: false);
      final Match? m = re.firstMatch(r.body);
      if (m == null) return;
      final String novo = m.group(0)!.replaceAll(RegExp(r'[/"]+$'), '');
      if (novo.isEmpty || novo == base) return;
      final int i = _lista.indexWhere((Dominio d) => d.id == 'superflix');
      if (i < 0) return;
      final List<String> espelhos = <String>[
        novo,
        ..._lista[i].espelhos.where((String e) => e != novo),
      ];
      _lista[i] = Dominio('superflix', 'SuperFlixAPI', espelhos, sonda: kSondaApi);
      _ativos['superflix'] = novo;
      await salvarCache();
      revisao.value++;
    } catch (_) {}
  }

  // --------------------------- INICIO -------------------------------
  static void iniciar() {
    Future<void>.microtask(() async {
      await atualizarRemoto();
      await sondarTodos();
    });
  }
}

// ================== DESCOBERTA DE API NA PAGINA ======================
class Descoberta {
  static final RegExp _hostApi =
      RegExp(r'''https?://(?:api|player|embed|cdn|server|go)[a-z0-9.-]*\.[a-z]{2,}[^"'\s\\<>)]*''',
          caseSensitive: false);
  static final RegExp _media =
      RegExp(r'''https?://[^"'\s\\<>)]+\.(?:m3u8|mp4)[^"'\s\\<>)]*''',
          caseSensitive: false);

  /// Baixa a pagina e extrai endpoints de API e midia citados nela.
  static Future<List<String>> apis(String url) async {
    final Set<String> out = <String>{};
    try {
      final http.Response r = await http.get(
        Uri.parse(url),
        headers: <String, String>{'User-Agent': kUserAgent},
      ).timeout(const Duration(seconds: 12));
      if (r.statusCode != 200) return <String>[];
      final String body = r.body;

      for (final RegExpMatch m in _media.allMatches(body)) {
        out.add(m.group(0)!);
        if (out.length > 20) break;
      }
      for (final RegExpMatch m in _hostApi.allMatches(body)) {
        out.add(m.group(0)!);
        if (out.length > 40) break;
      }
      final RegExp rel = RegExp(
          r'''["'](/(?:api|embed|player|e|v)/[^"'\s\\<>]{2,120})["']''',
          caseSensitive: false);
      for (final RegExpMatch m in rel.allMatches(body)) {
        try {
          out.add(Uri.parse(url).resolve(m.group(1)!).toString());
        } catch (_) {}
        if (out.length > 60) break;
      }
    } catch (_) {}
    return out.toList();
  }

  static Future<List<String>> streams(String url) => apis(url);
}
