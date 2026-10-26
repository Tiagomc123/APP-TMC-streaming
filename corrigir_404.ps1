# =====================================================================
#  TMC  -  PATCH 404 / FONTES         (build 6.1)
#  Aplicar sobre o lib/ gerado pelo atualizar.ps1 (build 6.0)
#  Uso: powershell -ExecutionPolicy Bypass -File .\corrigir_404.ps1
# =====================================================================

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
if ([string]::IsNullOrEmpty($root)) { $root = (Get-Location).Path }
Set-Location -LiteralPath $root

$mainPath = Join-Path $root 'lib\main.dart'
if (-not (Test-Path -LiteralPath $mainPath)) {
    Write-Host '-> lib/main.dart nao encontrado.' -ForegroundColor Red
    exit 1
}
Copy-Item -LiteralPath $mainPath -Destination "$mainPath.bak61" -Force

$utf8 = New-Object System.Text.UTF8Encoding($false)
$t = [System.IO.File]::ReadAllText($mainPath)
$n = 0

# ---------------------------------------------------------------------
# 1) endpoints VidSrc + IMDb
# ---------------------------------------------------------------------
if ($t -notmatch 'vidsrcUrl') {
    $t = $t.Replace(
        "  static String canalParceiro(String id) => '`$parceiro/canal/`$id';",
        "  static String canalParceiro(String id) => '`$parceiro/canal/`$id';`r`n`r`n  /// VidSrc: catalogo completo, keyed por ID do TMDB.`r`n  /// E o plano B quando o titulo nao existe no SuperFlix (404).`r`n  static const String vs1 = 'https://vidsrc.to';`r`n  static const String vs2 = 'https://vidsrc.xyz';`r`n`r`n  static String vidsrcUrl(bool isTv, int id, int s, int e) => isTv`r`n      ? '`$vs1/embed/tv/`$id/`$s/`$e'`r`n      : '`$vs1/embed/movie/`$id';`r`n`r`n  static String vidsrcUrl2(bool isTv, int id, int s, int e) => isTv`r`n      ? '`$vs2/embed/tv/`$id/`$s/`$e'`r`n      : '`$vs2/embed/movie/`$id';")
    $n++
    Write-Host '-> SuperFlix: rotas VidSrc adicionadas.' -ForegroundColor Green
}

# ---------------------------------------------------------------------
# 2) TmdbService: buscar o ID do IMDb (fallback do 404 em filmes)
# ---------------------------------------------------------------------
if ($t -notmatch 'imdbDe') {
    $t = $t.Replace(
        "  static Future<List<MediaItem>> similar(int id, bool isTv, {int pages = 1}) =>`r`n      _pages(isTv ? '/tv/`$id/similar' : '/movie/`$id/similar', isTv,`r`n          pages: pages);",
        "  static Future<List<MediaItem>> similar(int id, bool isTv, {int pages = 1}) =>`r`n      _pages(isTv ? '/tv/`$id/similar' : '/movie/`$id/similar', isTv,`r`n          pages: pages);`r`n`r`n  /// ID do IMDb do filme (o SuperFlix keye filmes por tt...).`r`n  static Future<String> imdbDe(int id) async {`r`n    try {`r`n      final Map<String, dynamic> d = await _get('/movie/`$id/external_ids');`r`n      final String i = (d['imdb_id'] ?? '').toString();`r`n      return i.startsWith('tt') ? i : '';`r`n    } catch (_) {`r`n      return '';`r`n    }`r`n  }")
    $n++
    Write-Host '-> TmdbService.imdbDe() criado.' -ForegroundColor Green
}

# ---------------------------------------------------------------------
# 3) 404 deve ser tratado como "nao achou", nao como pagina valida
# ---------------------------------------------------------------------
$t = $t.Replace(
    "    final http.Response? res = await SuperFlix.get(rota, page);`r`n    if (res == null) return null;",
    "    final http.Response? res = await SuperFlix.get(rota, page);`r`n    if (res == null) return null;`r`n    if (res.statusCode == 404) return null;")
if ($t -notmatch 'statusCode == 404') {
    $t = $t.Replace(
        "    if (res == null) return null;`n    final String body = res.body;",
        "    if (res == null) return null;`n    if (res.statusCode == 404) return null;`n    final String body = res.body;")
}
if ($t -match 'statusCode == 404') {
    $n++
    Write-Host '-> Resolver: 404 tratado como vazio.' -ForegroundColor Green
} else {
    Write-Host '   (aviso: nao achei o ponto do 404)' -ForegroundColor Yellow
}

# ---------------------------------------------------------------------
# 4) Resolver.best: tentar tambem o ID do IMDb
# ---------------------------------------------------------------------
$velhoBest = @'
    final List<Source> lista = forced >= 0 && forced < kSources.length
        ? <Source>[kSources[forced]]
        : kSources;
    PlayTarget? embed;
    for (final Source s in lista) {
      final String page = s.page(isTv, id, season, episode);
      for (final String rota in s.rotas(isTv, id, season, episode)) {
'@
$novoBest = @'
    final List<Source> lista = forced >= 0 && forced < kSources.length
        ? <Source>[kSources[forced]]
        : kSources;
    String imdb = '';
    if (!isTv) {
      try {
        imdb = await TmdbService.imdbDe(id);
      } catch (_) {
        imdb = '';
      }
    }
    PlayTarget? embed;
    for (final Source s in lista) {
      final String page = s.page(isTv, id, season, episode);
      final List<String> rotas = s.rotas(isTv, id, season, episode);
      if (imdb.isNotEmpty && s.name == 'SuperFlixAPI') {
        rotas.add('${SuperFlix.filme(imdb)}?format=json');
        rotas.add(SuperFlix.filme(imdb));
      }
      for (final String rota in rotas) {
'@
if ($t.Contains($velhoBest.Trim())) {
    $t = $t.Replace($velhoBest.Trim(), $novoBest.Trim())
    $n++
    Write-Host '-> Resolver.best: fallback por IMDb ativo.' -ForegroundColor Green
} else {
    Write-Host '   (aviso: bloco best nao bateu)' -ForegroundColor Yellow
}

# ---------------------------------------------------------------------
# 5) VidSrc como fonte extra (Android/TV)
# ---------------------------------------------------------------------
$velhoSrc = @'
    (bool isTv, int id, int s, int e) => isTv
        ? 'https://warezcdn.com/embed/serie.php?id=$id&season=$s&episode=$e'
        : 'https://warezcdn.com/embed/filme.php?id=$id',
  ),
];
'@
$novoSrc = @'
    (bool isTv, int id, int s, int e) => isTv
        ? 'https://warezcdn.com/embed/serie.php?id=$id&season=$s&episode=$e'
        : 'https://warezcdn.com/embed/filme.php?id=$id',
  ),
  Source(
    'VidSrc',
    (bool isTv, int id, int s, int e) =>
        <String>[SuperFlix.vidsrcUrl(isTv, id, s, e)],
    (bool isTv, int id, int s, int e) => SuperFlix.vidsrcUrl(isTv, id, s, e),
  ),
  Source(
    'VidSrc 2',
    (bool isTv, int id, int s, int e) =>
        <String>[SuperFlix.vidsrcUrl2(isTv, id, s, e)],
    (bool isTv, int id, int s, int e) => SuperFlix.vidsrcUrl2(isTv, id, s, e),
  ),
];
'@
if ($t.Contains($velhoSrc.Trim())) {
    $t = $t.Replace($velhoSrc.Trim(), $novoSrc.Trim())
    $n++
    Write-Host '-> kSources: VidSrc e VidSrc 2 adicionados.' -ForegroundColor Green
} else {
    Write-Host '   (aviso: fim de kSources nao bateu)' -ForegroundColor Yellow
}

# ---------------------------------------------------------------------
# 6) Web: SuperFlix principal, parceiro 2o, VidSrc 3o (ciclo de servidores)
# ---------------------------------------------------------------------
$velhoWeb = @'
  if (kIsWeb) {
    nav.push(MaterialPageRoute<void>(
      builder: (BuildContext _) => FrameScreen(
        url: paginaParceira,
        title: item.title,
        urlAlt: paginaOficial,
      ),
    ));
    return;
  }
'@
$novoWeb = @'
  if (kIsWeb) {
    nav.push(MaterialPageRoute<void>(
      builder: (BuildContext _) => FrameScreen(
        url: paginaOficial,
        title: item.title,
        urlAlt: paginaParceira,
        urlAlt2: SuperFlix.vidsrcUrl(item.isTv, item.id, season, episode),
      ),
    ));
    return;
  }
'@
if ($t.Contains($velhoWeb.Trim())) {
    $t = $t.Replace($velhoWeb.Trim(), $novoWeb.Trim())
    $n++
    Write-Host '-> openPlayer (Web): ordem de servidores corrigida.' -ForegroundColor Green
} else {
    Write-Host '   (aviso: branch kIsWeb do openPlayer nao bateu)' -ForegroundColor Yellow
}

# ---------------------------------------------------------------------
# 7) FrameScreen com 3 servidores + aviso de 404
# ---------------------------------------------------------------------
$novoFrame = @'
// ============ TELA DE EMBUTIR (WEB - IFRAME + 3 SERVIDORES) ==========
class FrameScreen extends StatefulWidget {
  final String url;
  final String title;
  final String urlAlt;
  final String urlAlt2;

  const FrameScreen({
    super.key,
    required this.url,
    required this.title,
    this.urlAlt = '',
    this.urlAlt2 = '',
  });

  @override
  State<FrameScreen> createState() => _FrameScreenState();
}

class _FrameScreenState extends State<FrameScreen> {
  int _i = 0;
  int _v = 0;

  List<String> get _servidores => <String>[
        widget.url,
        widget.urlAlt,
        widget.urlAlt2,
      ].where((String u) => u.isNotEmpty).toList();

  String get _atual {
    final List<String> l = _servidores;
    if (l.isEmpty) return widget.url;
    if (_i >= l.length) return l.last;
    return l[_i];
  }

  @override
  void initState() {
    super.initState();
    try {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } catch (_) {}
  }

  @override
  void dispose() {
    CacheKeeper.wipe();
    try {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    } catch (_) {}
    super.dispose();
  }

  void _proximo() {
    final List<String> l = _servidores;
    if (l.length < 2) return;
    setState(() {
      _i = (_i + 1) % l.length;
      _v++;
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      duration: const Duration(seconds: 2),
      content: Text('Servidor ${_i + 1} de ${l.length}'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final List<String> l = _servidores;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: <Widget>[
          Positioned.fill(
            child: KeyedSubtree(
              key: ValueKey<int>(_v + _i * 1000),
              child: TmcFrame(url: _atual),
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Container(
                color: Colors.black.withValues(alpha: 0.62),
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  children: <Widget>[
                    IconButton(
                      icon: const Icon(Icons.arrow_back),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    Expanded(
                      child: Text(
                        widget.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    if (l.length > 1)
                      TextButton(
                        onPressed: _proximo,
                        child: Text(
                          'SERVIDOR ${_i + 1}/${l.length}',
                          style: const TextStyle(
                              color: kGold,
                              fontSize: 11,
                              fontWeight: FontWeight.w800),
                        ),
                      ),
                    IconButton(
                      tooltip: 'Recarregar',
                      icon: const Icon(Icons.refresh),
                      onPressed: () => setState(() => _v++),
                    ),
                    IconButton(
                      tooltip: 'Abrir em nova aba (sem iframe)',
                      icon: const Icon(Icons.open_in_new),
                      onPressed: () => abrirExterno(_atual),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 6,
            child: IgnorePointer(
              child: Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    '404 ou travou? Toque em SERVIDOR para trocar a fonte.',
                    style: TextStyle(fontSize: 10, color: Colors.white60),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

'@

$rxFrame = [regex]'(?s)// =+ TELA DE EMBUTIR.*?(?=// =+ PLAYER NATIVO)'
if ($rxFrame.IsMatch($t)) {
    $sb = { param($m) $novoFrame }
    $t = $rxFrame.Replace($t, $sb)
    $n++
    Write-Host '-> FrameScreen: ciclo de 3 servidores + aviso de 404.' -ForegroundColor Green
} else {
    Write-Host '   (aviso: FrameScreen nao localizado)' -ForegroundColor Yellow
}

# ---------------------------------------------------------------------
# 8) TV ONLINE na Web: mesma ordem
# ---------------------------------------------------------------------
$t = $t.Replace(
    "        builder: (_) => FrameScreen(`r`n          url: alt.isEmpty ? url : alt,`r`n          title: titulo,`r`n          urlAlt: alt.isEmpty ? '' : url,`r`n        ),",
    "        builder: (_) => FrameScreen(`r`n          url: alt.isEmpty ? url : alt,`r`n          title: titulo,`r`n          urlAlt: alt.isEmpty ? '' : url,`r`n        ),")

[System.IO.File]::WriteAllText($mainPath, $t, $utf8)
Write-Host ''
Write-Host ('-> ' + $n + ' de 7 ajustes aplicados.') -ForegroundColor Cyan

Write-Host '-> flutter pub get...' -ForegroundColor Yellow
& flutter pub get
Write-Host '-> flutter analyze...' -ForegroundColor Yellow
& flutter analyze --no-fatal-infos

Write-Host ''
Write-Host '========================================================' -ForegroundColor Cyan
Write-Host '   PRONTO. Backup: lib\main.dart.bak61' -ForegroundColor DarkGray
Write-Host '   Se um titulo der 404, toque em SERVIDOR 2/3 no player.' -ForegroundColor Cyan
Write-Host '========================================================' -ForegroundColor Cyan