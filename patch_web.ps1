# =====================================================================
#  TMC - PATCH WEB  (rota garantida no navegador + flag do player nativo)
#  Uso: powershell -ExecutionPolicy Bypass -File .\patch_web.ps1
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

Copy-Item -LiteralPath $mainPath -Destination "$mainPath.bak2" -Force
$t = [System.IO.File]::ReadAllText($mainPath)

# 1) flag de configuracao
if ($t -notmatch 'kPlayerNativoNaWeb') {
    $t = $t.Replace(
        'late SharedPreferences prefs;',
        "late SharedPreferences prefs;`r`n`r`n// Web: true = tenta o player nativo (HLS via hls.js) antes do iframe.`r`nconst bool kPlayerNativoNaWeb = false;")
    Write-Host '-> flag kPlayerNativoNaWeb criada (false = iframe, que e o que roda no Chrome).' -ForegroundColor Green
}

# 2) respeitar a flag na escolha da rota
$antes = $t
$t = $t.Replace(
    'final bool usarNativo = t.direct && !kIsWeb;',
    'final bool usarNativo = t.direct && (!kIsWeb || kPlayerNativoNaWeb);')
if ($t -ne $antes) { Write-Host '-> rota do player agora respeita a flag.' -ForegroundColor Green }

# 3) FALLBACK OBRIGATORIO NA WEB (nao depende de fetch/CORS)
if ($t -notmatch 'Fallback Web') {
    $novo = @'
    if (embed != null) return embed;
    // Fallback Web: sem fetch/CORS, abre direto a pagina oficial no iframe.
    if (kIsWeb) {
      final Source s = kSources.first;
      final String pg = s.page(isTv, id, season, episode);
      return PlayTarget(provider: s.name, url: pg, direct: false, page: pg);
    }
    return null;
  }
}
'@
    $t = [regex]::Replace($t, '    return embed;\s*\}\s*\}', $novo, 1)
    Write-Host '-> fallback garantido da Web injetado no Resolver.' -ForegroundColor Green
}

$utf8 = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($mainPath, $t, $utf8)

Write-Host '-> Rodando flutter pub get...' -ForegroundColor Yellow
& flutter pub get
Write-Host '-> Validando...' -ForegroundColor Yellow
& flutter analyze --no-fatal-infos
Write-Host ''
Write-Host 'PRONTO. Web:  flutter run -d chrome' -ForegroundColor Cyan
Write-Host 'Backup: lib/main.dart.bak2' -ForegroundColor DarkGray