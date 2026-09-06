<#
.SYNOPSIS
    Erzeugt aus dem WebView-Template ein neues Android-Projekt unter .\apps.
.DESCRIPTION
    Der Inhalt von -WebRoot (HTML/CSS/JS) wird in die App eingebettet und
    laeuft danach offline aus der APK heraus.
.PARAMETER Name
    Projekt- und Anzeigename der App, z.B. "Notizen".
.PARAMETER PackageId
    Android Application ID, z.B. com.daniel.notizen. Kleinbuchstaben,
    mindestens zwei Segmente. Laesst sich spaeter nicht mehr aendern, ohne
    dass Android die App als andere App behandelt.
.PARAMETER WebRoot
    Ordner mit der Web-App (muss eine index.html enthalten). Ohne Angabe wird
    eine mitgelieferte Demo-Seite verwendet.
.PARAMETER Online
    Fuegt die INTERNET-Berechtigung hinzu. Ohne diesen Schalter ist die App
    vollstaendig offline (und braucht die Berechtigung nicht).
.PARAMETER Force
    Ueberschreibt ein bereits vorhandenes Projekt gleichen Namens.
.EXAMPLE
    .\new-app.ps1 -Name Notizen -PackageId com.daniel.notizen -WebRoot C:\web\notizen
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Name,
    [Parameter(Mandatory)][string]$PackageId,
    [string]$WebRoot,
    [string]$VersionName = '1.0',
    [int]$VersionCode = 1,
    [switch]$Online,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib\env.ps1')
$V = Get-ToolchainVersions

# ------------------------------------------------------------- Validierung --
if ($Name -notmatch '^[A-Za-z][A-Za-z0-9_-]*$') {
    throw "Ungueltiger Name '$Name'. Erlaubt: Buchstaben, Ziffern, - und _, beginnend mit einem Buchstaben."
}
if ($PackageId -notmatch '^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$') {
    throw "Ungueltige PackageId '$PackageId'. Erwartet z.B. com.daniel.meineapp (nur Kleinbuchstaben, mindestens zwei Segmente)."
}
$javaKeywords = @('abstract','assert','boolean','break','byte','case','catch','char','class','const',
                  'continue','default','do','double','else','enum','extends','final','finally','float',
                  'for','goto','if','implements','import','instanceof','int','interface','long','native',
                  'new','package','private','protected','public','return','short','static','strictfp',
                  'super','switch','synchronized','this','throw','throws','transient','try','void',
                  'volatile','while')
foreach ($seg in $PackageId.Split('.')) {
    if ($javaKeywords -contains $seg) {
        throw "PackageId enthaelt das reservierte Java-Schluesselwort '$seg'."
    }
}

$templateDir = Join-Path $Paths.Templates 'webview'
if (-not (Test-Path $templateDir)) { throw "Template nicht gefunden: $templateDir" }

$appDir = Join-Path $Paths.Apps $Name
if (Test-Path $appDir) {
    if (-not $Force) {
        throw "Projekt existiert bereits: $appDir  (mit -Force ueberschreiben)"
    }
    Write-Host "  Ueberschreibe vorhandenes Projekt..." -ForegroundColor Yellow
    Remove-Item $appDir -Recurse -Force
}

# --- Web-Inhalte bestimmen ---------------------------------------------------
if ($WebRoot) {
    if (-not (Test-Path $WebRoot)) { throw "WebRoot nicht gefunden: $WebRoot" }
    $WebRoot = (Resolve-Path $WebRoot).Path
    if (-not (Test-Path (Join-Path $WebRoot 'index.html'))) {
        throw "In '$WebRoot' liegt keine index.html - die braucht die App als Startseite."
    }
} else {
    $WebRoot = Join-Path $Paths.Templates 'sample-www'
    Write-Host '  Kein -WebRoot angegeben, verwende die Demo-Seite.' -ForegroundColor DarkGray
}

# --------------------------------------------------------------- Erzeugen ---
Write-Host ''
Write-Host "  Erzeuge $Name" -ForegroundColor White
Copy-Item $templateDir $appDir -Recurse

$internetPermission = ''
if ($Online) {
    $internetPermission = '<uses-permission android:name="android.permission.INTERNET" />'
}

$tokens = @{
    '{{APP_NAME}}'            = $Name
    '{{PACKAGE_ID}}'          = $PackageId
    '{{VERSION_NAME}}'        = $VersionName
    '{{VERSION_CODE}}'        = "$VersionCode"
    '{{AGP_VERSION}}'         = $V.AgpVersion
    '{{COMPILE_SDK}}'         = "$($V.CompileSdk)"
    '{{TARGET_SDK}}'          = "$($V.TargetSdk)"
    '{{MIN_SDK}}'             = "$($V.MinSdk)"
    '{{INTERNET_PERMISSION}}' = $internetPermission
}

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Expand-Tokens {
    param([string]$Path)
    $text = [System.IO.File]::ReadAllText($Path)
    foreach ($k in $tokens.Keys) { $text = $text.Replace($k, $tokens[$k]) }
    [System.IO.File]::WriteAllText($Path, $text, $utf8NoBom)
}

Get-ChildItem $appDir -Recurse -File -Include *.kts, *.xml, *.properties, *.pro |
    ForEach-Object { Expand-Tokens $_.FullName }

# --- MainActivity an die richtige Paketstelle legen --------------------------
$javaRoot = Join-Path $appDir 'app\src\main\java'
$tmpl     = Join-Path $javaRoot 'MainActivity.java.tmpl'
$pkgDir   = Join-Path $javaRoot ($PackageId.Replace('.', '\'))
New-Item -ItemType Directory -Path $pkgDir -Force | Out-Null
$activity = Join-Path $pkgDir 'MainActivity.java'
Move-Item $tmpl $activity -Force
Expand-Tokens $activity

# --- Web-Inhalte einbetten ---------------------------------------------------
$assetsWww = Join-Path $appDir 'app\src\main\assets\www'
if (Test-Path $assetsWww) { Remove-Item $assetsWww -Recurse -Force }
New-Item -ItemType Directory -Path $assetsWww -Force | Out-Null
Copy-Item (Join-Path $WebRoot '*') $assetsWww -Recurse -Force

$fileCount = @(Get-ChildItem $assetsWww -Recurse -File).Count
$sizeKb = [math]::Round((Get-ChildItem $assetsWww -Recurse -File | Measure-Object Length -Sum).Sum / 1KB, 1)

Write-Host "  [ok] Projekt      $appDir" -ForegroundColor Green
Write-Host "  [ok] Package      $PackageId" -ForegroundColor Green
Write-Host "  [ok] Web-Inhalte  $fileCount Datei(en), $sizeKb KB aus $WebRoot" -ForegroundColor Green
if ($Online) {
    Write-Host '  [ok] INTERNET-Berechtigung gesetzt' -ForegroundColor Green
} else {
    Write-Host '  [ok] Offline (keine INTERNET-Berechtigung)' -ForegroundColor Green
}
Write-Host ''
Write-Host '  Naechster Schritt:' -ForegroundColor White
Write-Host "    .\build-apk.ps1 -App $Name" -ForegroundColor White
Write-Host ''
