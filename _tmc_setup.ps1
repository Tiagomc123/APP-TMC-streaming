$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

Write-Host '  -> Gerando identidade visual (TMC)...'
New-Item -ItemType Directory -Force -Path 'assets\icon' | Out-Null
New-Item -ItemType Directory -Force -Path 'android\app\src\main\res\drawable' | Out-Null

function New-TmcImage {
    param(
        [string]$Path,
        [int]$W,
        [int]$H,
        [bool]$Transparent = $false,
        [string]$Label = 'TMC',
        [double]$Scale = 0.26,
        [bool]$Accent = $true
    )
    $bmp = [System.Drawing.Bitmap]::new($W, $H)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic

    if (-not $Transparent) {
        $rect = [System.Drawing.RectangleF]::new(0, 0, [float]$W, [float]$H)
        $c1 = [System.Drawing.Color]::FromArgb(255, 8, 12, 22)
        $c2 = [System.Drawing.Color]::FromArgb(255, 30, 74, 170)
        $brush = [System.Drawing.Drawing2D.LinearGradientBrush]::new($rect, $c1, $c2, 45.0)
        $g.FillRectangle($brush, $rect)
        $brush.Dispose()
        $glow = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(34, 245, 196, 81))
        $g.FillEllipse($glow, [float]($W * 0.58), [float](-$H * 0.18), [float]($W * 0.70), [float]($W * 0.70))
        $glow.Dispose()
        $glow2 = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(28, 61, 123, 255))
        $g.FillEllipse($glow2, [float](-$W * 0.20), [float]($H * 0.60), [float]($W * 0.70), [float]($W * 0.70))
        $glow2.Dispose()
    } else {
        $g.Clear([System.Drawing.Color]::Transparent)
    }

    $base = [Math]::Min($W, $H)
    $size = [float]($base * $Scale)
    $font = [System.Drawing.Font]::new('Arial', $size, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
    $fmt = [System.Drawing.StringFormat]::new()
    $fmt.Alignment = [System.Drawing.StringAlignment]::Center
    $fmt.LineAlignment = [System.Drawing.StringAlignment]::Center
    $fmt.FormatFlags = [System.Drawing.StringFormatFlags]::NoClip

    $full = [System.Drawing.RectangleF]::new(0, 0, [float]$W, [float]$H)
    $shRect = [System.Drawing.RectangleF]::new([float]($base * 0.010), [float]($base * 0.014), [float]$W, [float]$H)
    $shadow = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(135, 0, 0, 0))
    $white = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::White)
    $gold = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(255, 245, 196, 81))

    $g.DrawString($Label, $font, $shadow, $shRect, $fmt)
    $g.DrawString($Label, $font, $white, $full, $fmt)

    if ($Accent) {
        $pen = [System.Drawing.Pen]::new([System.Drawing.Color]::FromArgb(255, 245, 196, 81), [float]($base * 0.016))
        $pen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
        $pen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
        $y = [float]($H * 0.5 + $size * 0.60)
        $g.DrawLine($pen, [float]($W * 0.5 - $base * 0.15), $y, [float]($W * 0.5 + $base * 0.15), $y)
        $pen.Dispose()
    }

    $g.Dispose()
    $font.Dispose(); $fmt.Dispose(); $shadow.Dispose(); $white.Dispose(); $gold.Dispose()
    $bmp.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
}

New-TmcImage -Path 'assets\icon\icon.png' -W 1024 -H 1024 -Transparent $false -Label 'TMC' -Scale 0.26
New-TmcImage -Path 'assets\icon\icon_fg.png' -W 1024 -H 1024 -Transparent $true -Label 'TMC' -Scale 0.24
New-TmcImage -Path 'android\app\src\main\res\drawable\tv_banner.png' -W 320 -H 180 -Transparent $false -Label 'TMC' -Scale 0.30

# ---------------- pubspec: config do launcher icons ----------------
$pubPath = 'pubspec.yaml'
$pub = [System.IO.File]::ReadAllText($pubPath)
if ($pub -notmatch 'flutter_launcher_icons:') {
    $block = "`r`n" + @"
flutter_launcher_icons:
  android: "launcher_icon"
  ios: true
  image_path: "assets/icon/icon.png"
  min_sdk_android: 21
  remove_alpha_ios: true
  adaptive_icon_background: "#0A0E18"
  adaptive_icon_foreground: "assets/icon/icon_fg.png"
"@
    [System.IO.File]::WriteAllText($pubPath, $pub + $block)
}

# ---------------- AndroidManifest: nome, permissoes e Android TV ----------------
$manPath = 'android\app\src\main\AndroidManifest.xml'
$man = [System.IO.File]::ReadAllText($manPath)

if ($man -notmatch 'android.permission.INTERNET') {
    $perm = '<uses-permission android:name="android.permission.INTERNET" />'
    $man = [regex]::Replace($man, '(<manifest[^>]*>)', ('$1' + "`r`n    " + $perm), 1)
}

$man = [regex]::Replace($man, 'android:label="[^"]*"', 'android:label="TMC"', 1)

if ($man -notmatch 'leanback') {
    $man = [regex]::Replace($man, '<application', '<application android:banner="@drawable/tv_banner" android:usesCleartextTraffic="true"', 1)
    $feats = "`r`n    " + '<uses-feature android:name="android.software.leanback" android:required="false" />' + "`r`n    " + '<uses-feature android:name="android.hardware.touchscreen" android:required="false" />'
    $man = [regex]::Replace($man, '(<manifest[^>]*>)', ('$1' + $feats), 1)
    $man = [regex]::Replace($man, '(<category android:name="android.intent.category.LAUNCHER"\s*/>)', ('$1' + "`r`n            " + '<category android:name="android.intent.category.LEANBACK_LAUNCHER" />'), 1)
}

[System.IO.File]::WriteAllText($manPath, $man)

Write-Host '  -> Icone, nome "TMC", Internet e suporte Android TV configurados.'