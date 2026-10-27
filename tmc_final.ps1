# =====================================================================
#  TMC - FINAL FIX  (tmc_final.ps1)  -- versao corrigida (parser OK)
#  Uso:  powershell -ExecutionPolicy Bypass -File .\tmc_final.ps1
#  Roda a partir da raiz do repo: D:\PROJETOSDEAPPSTIAGOMC\TMC
# =====================================================================
$ErrorActionPreference = 'Continue'

if ($PSScriptRoot) { $root = $PSScriptRoot } else { $root = (Get-Location).Path }
Set-Location -LiteralPath $root

$legacyDir = Join-Path $root 'lib\legacy'
$excludeItems = @('lib/legacy/**', '.tmc_backup_*/**', '_tmc_backup_*/**', 'lib/tmc_frame_stub/**')

function Write-Ok    { param([string]$m) Write-Host "[ OK ] ${m}" -ForegroundColor Green }
function Write-Fix   { param([string]$m) Write-Host "[FIX ] ${m}" -ForegroundColor Yellow }
function Write-Warn2 { param([string]$m) Write-Host "[WARN] ${m}" -ForegroundColor DarkYellow }
function Write-Err2  { param([string]$m) Write-Host "[ERR ] ${m}" -ForegroundColor Red }

function Read-Text { param([string]$file) return [System.IO.File]::ReadAllText($file) }
function Save-Text {
  param([string]$file, [string]$text)
  $enc = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($file, $text, $enc)
}

function Get-RelPath {
  param([string]$fromDir, [string]$toFile)
  $from = ([System.IO.Path]::GetFullPath($fromDir)).TrimEnd('\')
  $to   = [System.IO.Path]::GetFullPath($toFile)
  $fp = $from -split '\\'
  $tp = $to   -split '\\'
  $i = 0
  while ($i -lt $fp.Count -and $i -lt $tp.Count -and $fp[$i] -eq $tp[$i]) { $i++ }
  $parts = @()
  for ($k = $i; $k -lt $fp.Count; $k++) { $parts += '..' }
  if ($i -lt $tp.Count) { $parts += $tp[$i..($tp.Count - 1)] }
  return ($parts -join '/')
}

function Add-Import {
  param([string]$file, [string]$importLine, [string]$needle)
  if (-not (Test-Path -LiteralPath $file)) { Write-Warn2 "arquivo nao encontrado: ${file}"; return }
  $t = Read-Text -file $file
  if ($t -match [regex]::Escape($needle)) { Write-Ok "ja contem ${needle}"; return }
  $lines = New-Object System.Collections.Generic.List[string]
  $lines.AddRange([string[]][System.IO.File]::ReadAllLines($file))
  $last = -1
  for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match '^\s*import\s') { $last = $i } }
  if ($last -ge 0) { $lines.Insert($last + 1, $importLine) } else { $lines.Insert(0, $importLine) }
  Save-Text -file $file -text ($lines -join "`r`n")
  Write-Fix "import adicionado em $([System.IO.Path]::GetFileName($file))"
}

Write-Host ""
Write-Host "===== TMC FINAL FIX =====" -ForegroundColor Cyan
Write-Host "Raiz: ${root}"
Write-Host ""

if (-not (Test-Path -LiteralPath (Join-Path $root 'pubspec.yaml'))) {
  Write-Err2 "pubspec.yaml nao encontrado em ${root}. Rode da raiz do projeto."
}

# ---------------------------------------------------------------------
# STEP 1 - renomeia _tmc_backup_* -> .tmc_backup_* (o analyzer ignora dot-folders)
# ---------------------------------------------------------------------
Write-Host "--- [1] backups ---" -ForegroundColor Cyan
$backups = @(Get-ChildItem -LiteralPath $root -Directory -Filter '_tmc_backup_*' -ErrorAction SilentlyContinue)
if ($backups.Count -gt 0) {
  foreach ($b in $backups) {
    $novo = '.tmc_backup_' + $b.Name.Substring('_tmc_backup_'.Length)
    $dest = Join-Path $root $novo
    if (Test-Path -LiteralPath $dest) { Remove-Item -LiteralPath $dest -Recurse -Force -ErrorAction SilentlyContinue }
    Rename-Item -LiteralPath $b.FullName -NewName $novo -ErrorAction SilentlyContinue
    Write-Fix "renomeado: $($b.Name)  ->  ${novo}"
  }
} else {
  Write-Warn2 "nenhum _tmc_backup_* encontrado (ja renomeado)"
}

# ---------------------------------------------------------------------
# STEP 2 - analysis_options.yaml : garante bloco analyzer/exclude
# ---------------------------------------------------------------------
Write-Host "--- [2] analysis_options.yaml ---" -ForegroundColor Cyan
$aoPath = Join-Path $root 'analysis_options.yaml'
if (-not (Test-Path -LiteralPath $aoPath)) {
  $novo = @'
include: package:flutter_lints/flutter.yaml

analyzer:
  exclude:
    - lib/legacy/**
    - .tmc_backup_*/**
    - _tmc_backup_*/**
    - lib/tmc_frame_stub/**
'@
  Save-Text -file $aoPath -text $novo
  Write-Fix "analysis_options.yaml criado"
} else {
  $lines = [System.IO.File]::ReadAllLines($aoPath)
  $out = New-Object System.Collections.Generic.List[string]
  $i = 0
  $done = $false
  while ($i -lt $lines.Count) {
    $ln = $lines[$i]
    if (-not $done -and $ln -match '^analyzer:') {
      $out.Add($ln)
      # procura 'exclude:' dentro do bloco analyzer
      $j = $i + 1
      $excIdx = -1
      while ($j -lt $lines.Count -and ($lines[$j] -match '^\s' -or $lines[$j].Trim() -eq '')) {
        if ($lines[$j] -match '^\s*exclude:') { $excIdx = $j; break }
        $j++
      }
      if ($excIdx -ge 0) {
        $k = $i + 1
        while ($k -le $excIdx) { $out.Add($lines[$k]); $k++ }
        foreach ($p in $excludeItems) { $out.Add("    - $p") }
        $k = $excIdx + 1
        while ($k -lt $lines.Count -and $lines[$k] -match '^\s*-\s') { $k++ }
        $i = $k
      } else {
        $out.Add('  exclude:')
        foreach ($p in $excludeItems) { $out.Add("    - $p") }
        $i = $i + 1
      }
      $done = $true
      continue
    }
    $out.Add($ln)
    $i++
  }
  if (-not $done) {
    $out.Add('')
    $out.Add('analyzer:')
    $out.Add('  exclude:')
    foreach ($p in $excludeItems) { $out.Add("    - $p") }
  }
  Save-Text -file $aoPath -text ($out -join "`r`n")
  Write-Fix "exclude do analyzer garantido (lib/legacy, backups, tmc_frame_stub)"
}

# ---------------------------------------------------------------------
# STEP 3 - move lib/domains.dart + deps relativas para lib/legacy
# ---------------------------------------------------------------------
Write-Host "--- [3] dependencias legadas ---" -ForegroundColor Cyan
New-Item -ItemType Directory -Force -Path $legacyDir | Out-Null

function Find-Candidate {
  param([string]$importPath)
  $fname = Split-Path $importPath -Leaf
  $all = @(Get-ChildItem -LiteralPath $root -Recurse -File -Filter $fname -ErrorAction SilentlyContinue |
    Where-Object {
      $fp = $_.FullName
      ($fp -notlike "*\.dart_tool\*") -and ($fp -notlike "*\build\*") -and
      ($fp -notlike "*\android\*") -and ($fp -notlike "*\ios\*") -and
      ($fp -notlike "*\.tmc_backup_*") -and ($fp -notlike "*\_tmc_backup_*") -and
      ($fp -notlike "${legacyDir}\*")
    })
  if ($all.Count -eq 0) { return $null }
  $tail = ($importPath -replace '\\', '/')
  $tail = $tail -replace '^\./', ''
  $best = $null
  foreach ($c in $all) {
    $f = ($c.FullName -replace '\\', '/')
    if ($f.EndsWith('/' + $tail)) { if (-not $best -or $c.FullName.Length -lt $best.FullName.Length) { $best = $c } }
  }
  if (-not $best) {
    $libOnes = @($all | Where-Object { $_.FullName -like "*\lib\*" })
    if ($libOnes.Count -gt 0) { $best = $libOnes | Sort-Object { $_.FullName.Length } | Select-Object -First 1 }
    else { $best = $all | Sort-Object { $_.FullName.Length } | Select-Object -First 1 }
  }
  return $best
}

$totalMoved = 0
for ($pass = 1; $pass -le 8; $pass++) {
  $movedThis = 0
  $legacyFiles = @(Get-ChildItem -LiteralPath $legacyDir -Recurse -File -Filter '*.dart' -ErrorAction SilentlyContinue)
  foreach ($lf in $legacyFiles) {
    $text = Read-Text -file $lf.FullName
    foreach ($mm in [regex]::Matches($text, "import\s+'([^']+)'")) {
      $imp = $mm.Groups[1].Value
      if ($imp -match '^package:') { continue }
      if ($imp -match '^dart:') { continue }
      $target = [System.IO.Path]::GetFullPath((Join-Path $lf.DirectoryName $imp))
      if (Test-Path -LiteralPath $target) { continue }
      $cand = Find-Candidate -importPath $imp
      if (-not $cand) { Write-Warn2 "dep nao encontrada para '${imp}' (usado por $($lf.Name))"; continue }
      $destDir = Split-Path $target -Parent
      New-Item -ItemType Directory -Force -Path $destDir | Out-Null
      Move-Item -LiteralPath $cand.FullName -Destination $target -Force
      Write-Fix "movido: $($cand.FullName.Substring($root.Length + 1))  ->  $($target.Substring($root.Length + 1))"
      $movedThis++
    }
  }
  $totalMoved += $movedThis
  if ($movedThis -eq 0) { break }
}
if ($totalMoved -eq 0) { Write-Ok "nenhuma dependencia legada pendente" } else { Write-Ok "deps movidas: ${totalMoved}" }

# corrige imports relativos que quebraram por causa dos movimentos
$libDir = Join-Path $root 'lib'
$rep = 0
foreach ($f in @(Get-ChildItem -LiteralPath $libDir -Recurse -File -Filter '*.dart' -ErrorAction SilentlyContinue)) {
  $text = Read-Text -file $f.FullName
  $orig = $text
  foreach ($mm in [regex]::Matches($text, "import\s+'([^']+)'")) {
    $imp = $mm.Groups[1].Value
    if ($imp -match '^package:') { continue }
    if ($imp -match '^dart:') { continue }
    $target = [System.IO.Path]::GetFullPath((Join-Path $f.DirectoryName $imp))
    if (Test-Path -LiteralPath $target) { continue }
    $fname = Split-Path $imp -Leaf
    $cand = @(Get-ChildItem -LiteralPath $libDir -Recurse -File -Filter $fname -ErrorAction SilentlyContinue |
      Where-Object { $_.FullName -notlike "${legacyDir}\*" } | Select-Object -First 1)
    if ($cand.Count -eq 0) { continue }
    $rel = Get-RelPath -fromDir $f.DirectoryName -toFile $cand[0].FullName
    if ($rel -notmatch '^\.') { $rel = './' + $rel }
    $text = $text.Replace("import '$imp'", "import '$rel'")
    $rep++
  }
  if ($text -ne $orig) { Save-Text -file $f.FullName -text $text }
}
Write-Ok "imports relativos reparados: ${rep}"

# ---------------------------------------------------------------------
# STEP 4 - details_screen.dart : import ResolvedStream
# ---------------------------------------------------------------------
Write-Host "--- [4] details_screen.dart ---" -ForegroundColor Cyan
$ds = Join-Path $root 'lib\ui\screens\details_screen.dart'
Add-Import -file $ds -importLine "import '../../data/models/resolved_stream.dart';" -needle "resolved_stream.dart"

# ---------------------------------------------------------------------
# STEP 5 - stream_provider.dart : prefer_initializing_formals
# ---------------------------------------------------------------------
Write-Host "--- [5] stream_provider.dart ---" -ForegroundColor Cyan
$sp = Join-Path $root 'lib\services\stream\providers\stream_provider.dart'
if (Test-Path -LiteralPath $sp) {
  $t = Read-Text -file $sp
  if ($t -match 'this\._emit') {
    Write-Ok "stream_provider.dart ja usa this._emit"
  } else {
    $t2 = $t -replace '(?m)^(\s*)required\s+void\s+Function.*\bemit\s*,', '${1}required this._emit,'
    $t2 = $t2 -replace '\}\s*\)\s*:\s*_emit\s*=\s*emit\s*;', '});'
    if ($t2 -ne $t) { Save-Text -file $sp -text $t2; Write-Fix "constructor -> required this._emit" }
    else { Write-Warn2 "padrao do constructor nao casou em stream_provider.dart" }
  }
} else { Write-Warn2 "stream_provider.dart nao encontrado" }

$vrs = Join-Path $root 'lib\services\stream\video_resolver_service.dart'
if (Test-Path -LiteralPath $vrs) {
  $t = Read-Text -file $vrs
  if ($t -match '\b_emit\s*:\s*_emit\b') {
    $t = $t -replace '\b_emit\s*:\s*_emit\b', 'emit: _emit'
    Save-Text -file $vrs -text $t
    Write-Fix "video_resolver_service.dart: _emit: _emit -> emit: _emit"
  } else { Write-Ok "video_resolver_service.dart ja ok" }
}

# ---------------------------------------------------------------------
# STEP 6 - embedded_trailer.dart : preservar controller e usar startSeconds
# ---------------------------------------------------------------------
Write-Host "--- [6] embedded_trailer.dart ---" -ForegroundColor Cyan
$et = Join-Path $root 'lib\ui\widgets\embedded_trailer.dart'
if (-not (Test-Path -LiteralPath $et)) {
  Write-Warn2 "embedded_trailer.dart nao encontrado"
} else {
  $t = Read-Text -file $et
  $orig = $t
  $createPattern = '(?s)  void _create\(\)\s*\{.*?(?=  /// Le o estado do player)'
  $createBody = @'
  void _create() {
    _ctl = YoutubePlayerController.fromVideoId(
      videoId: widget.videoKey,
      autoPlay: widget.autoPlay,
      params: const YoutubePlayerParams(
        showControls: true,
        strictRelatedVideos: true,
        origin: 'https://www.youtube.com',
      ),
    );
    _ctl!.stream.listen(_onValue);
  }

'@
  $t = [regex]::Replace($t, $createPattern, $createBody, 1)
  $t = [regex]::Replace(
    $t,
    'startAt\s*:\s*widget\.startAt\s*,',
    'startSeconds: widget.startAt.inSeconds.toDouble(),'
  )
  if ($t -ne $orig) {
    Save-Text -file $et -text $t
    Write-Fix "controller restaurado; retomada convertida para startSeconds"
  } else {
    Write-Ok "embedded_trailer.dart ja compativel com youtube_player_iframe 5.2.2"
  }
}

# ---------------------------------------------------------------------
# STEP 7 - PUB GET / TEST / ANALYZE + veredito
# ---------------------------------------------------------------------
Write-Host ""
Write-Host "--- [7] verificacao ---" -ForegroundColor Cyan

Write-Host "> flutter pub get"
& flutter pub get
if ($LASTEXITCODE -ne 0) { Write-Err2 "flutter pub get falhou" } else { Write-Ok "pub get ok" }

Write-Host "> flutter test"
$testList = New-Object System.Collections.Generic.List[string]
& flutter test 2>&1 | ForEach-Object { Write-Host $_; $testList.Add([string]$_) }
$testCode = $LASTEXITCODE

Write-Host "> flutter analyze"
$anList = New-Object System.Collections.Generic.List[string]
& flutter analyze 2>&1 | ForEach-Object { Write-Host $_; $anList.Add([string]$_) }

$errs = New-Object System.Collections.Generic.List[string]
$warns = New-Object System.Collections.Generic.List[string]
$infos = New-Object System.Collections.Generic.List[string]
foreach ($ln in $anList) {
  if ($ln -notmatch '\.dart:\d+:\d+') { continue }
  if ($ln -match 'legacy') { continue }
  if ($ln -match 'tmc_backup') { continue }
  if ($ln -match '^\s*error')   { $errs.Add($ln) }
  elseif ($ln -match '^\s*warning') { $warns.Add($ln) }
  else { $infos.Add($ln) }
}

Write-Host ""
Write-Host "=================== VEREDITO ===================" -ForegroundColor Cyan
if ($testCode -eq 0) { Write-Host "testes: PASSARAM" -ForegroundColor Green }
else { Write-Host "testes: FALHARAM (codigo $($testCode))" -ForegroundColor Red }

Write-Host "codigo NOVO -> erros: $($errs.Count) | warnings: $($warns.Count) | lints: $($infos.Count)"
foreach ($e in $errs)  { Write-Host "  E $($e)" -ForegroundColor Red }
foreach ($w in $warns) { Write-Host "  W $($w)" -ForegroundColor Yellow }
foreach ($n in $infos) { Write-Host "  i $($n)" -ForegroundColor DarkGray }

Write-Host ""
if ($errs.Count -eq 0 -and $warns.Count -eq 0 -and $testCode -eq 0) {
  Write-Host ">>> TUDO PRONTO: codigo novo limpo, testes ok." -ForegroundColor Green
  Write-Host ">>> Agora no VS Code: Ctrl+Shift+P -> 'Developer: Reload Window'." -ForegroundColor Green
  Write-Host ">>> Depois: teste o app na TV Box usando so o controle (D-Pad)." -ForegroundColor Green
  Write-Host ">>> Validado? git commit  e depois apague lib\legacy e .tmc_backup_*." -ForegroundColor Green
} else {
  Write-Host ">>> Ainda ha pendencias. Copie o log acima e me mande." -ForegroundColor Yellow
}
Write-Host "================================================" -ForegroundColor Cyan
