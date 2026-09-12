<#
.SYNOPSIS
    Exportiert ein Godot-Projekt kopflos als Android-APK und legt sie in
    .\out ab - das Godot-Gegenstueck zu build-apk.ps1.
.DESCRIPTION
    Ruft `godot --headless --path <ProjectRoot> --export-(debug|release)
    "Android" <apk>` auf. Release-Builds nutzen denselben geteilten
    Toolchain-Keystore wie die WebView-Apps (keys\release.jks) - Zugangsdaten
    werden als GODOT_ANDROID_KEYSTORE_RELEASE_* Umgebungsvariablen durch-
    gereicht, nie in export_presets.cfg eingebettet.

    Nach dem Export dieselbe Verifikation wie build-apk.ps1: apksigner
    verify + aapt2 dump badging (Paket-ID/Version bestaetigt).
.PARAMETER ProjectRoot
    Ordner mit dem Godot-Projekt (enthaelt project.godot + export_presets.cfg).
.PARAMETER AppName
    Name fuer die Ausgabedatei unter .\out (z.B. "Hopper").
.PARAMETER Release
    Signierter Release-Export statt Debug.
.PARAMETER Install
    Installiert die fertige APK per adb auf einem angeschlossenen Geraet.
.PARAMETER KeystorePassword
    Passwort fuer einen neu anzulegenden Release-Keystore (nur falls
    keys\release.jks noch nicht existiert - normalerweise bereits vorhanden,
    siehe build-apk.ps1).
.EXAMPLE
    .\build-godot-apk.ps1 -ProjectRoot "D:\claude code projects\hopper\godot" -AppName Hopper
.EXAMPLE
    .\build-godot-apk.ps1 -ProjectRoot "D:\claude code projects\hopper\godot" -AppName Hopper -Release -Install
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ProjectRoot,
    [Parameter(Mandatory)][string]$AppName,
    [switch]$Release,
    [switch]$Install,
    [string]$KeystorePassword
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib\env.ps1')
$V = Get-ToolchainVersions

function Write-Step { param([string]$m) Write-Host "`n==> $m" -ForegroundColor Cyan }
function Write-Ok   { param([string]$m) Write-Host "    OK  $m" -ForegroundColor Green }
function Write-Info { param([string]$m) Write-Host "    $m" -ForegroundColor Gray }

Assert-ToolchainReady
Assert-GodotReady

if (-not (Test-Path (Join-Path $ProjectRoot 'project.godot'))) {
    throw "Kein Godot-Projekt gefunden unter $ProjectRoot (project.godot fehlt)."
}
if (-not (Test-Path (Join-Path $ProjectRoot 'export_presets.cfg'))) {
    throw "export_presets.cfg fehlt unter $ProjectRoot - zuerst .\new-godot-app.ps1 ausfuehren."
}

$variant = 'debug'
if ($Release) { $variant = 'release' }

# Godots Android-Export braucht ein eigenes JAVA_HOME zur Exportzeit - siehe
# setup-godot.ps1/Get-GodotJavaHome: entweder das gemeinsame JDK 21 oder,
# falls das nicht funktioniert, ein eigenes JDK 17.
$env:JAVA_HOME = Get-GodotJavaHome
Write-Info "JAVA_HOME (Godot-Export) = $env:JAVA_HOME"

# ------------------------------------------------- Release-Keystore ---------
if ($Release) {
    Write-Step 'Release-Signierung (geteilter Toolchain-Keystore)'
    $keystore  = Join-Path $Paths.Keys 'release.jks'
    $propsFile = Join-Path $Paths.Keys 'signing.properties'
    $alias     = 'release'

    if (-not (Test-Path $keystore)) {
        Write-Info 'Noch kein Release-Keystore vorhanden - lege einen an.'
        if (-not $KeystorePassword) {
            $bytes = New-Object byte[] 24
            [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
            $KeystorePassword = [Convert]::ToBase64String($bytes).Replace('/', '_').Replace('+', '-')
            Write-Info 'Zufaelliges Passwort erzeugt.'
        }
        $keytool = Get-ToolPath 'keytool'
        Get-NativeOutput -FilePath $keytool -What 'keytool' -Arguments @(
            '-genkeypair', '-v',
            '-keystore', $keystore,
            '-alias', $alias,
            '-keyalg', 'RSA', '-keysize', '4096', '-validity', '10950',
            '-storepass', $KeystorePassword, '-keypass', $KeystorePassword,
            '-dname', "CN=$AppName, OU=apk-builder, O=$AppName, C=DE"
        ) | Out-Null
        @(
            '# Von build-apk.ps1/build-godot-apk.ps1 erzeugt. NICHT ins Git-Repo aufnehmen.',
            "storeFile=$keystore",
            "storePassword=$KeystorePassword",
            "keyAlias=$alias",
            "keyPassword=$KeystorePassword"
        ) | Set-Content -Path $propsFile -Encoding utf8
        Write-Ok "Keystore erzeugt: $keystore"
    } else {
        Write-Info "Verwende vorhandenen Keystore: $keystore"
    }

    $props = @{}
    foreach ($line in (Get-Content $propsFile)) {
        if ($line -match '^\s*([^#=]+?)\s*=\s*(.*)$') { $props[$Matches[1]] = $Matches[2] }
    }
    $env:GODOT_ANDROID_KEYSTORE_RELEASE_PATH     = $props['storeFile']
    $env:GODOT_ANDROID_KEYSTORE_RELEASE_USER     = $props['keyAlias']
    $env:GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD = $props['storePassword']
    Write-Ok 'Keystore-Zugangsdaten als Umgebungsvariablen gesetzt (nicht in export_presets.cfg)'
}

# ------------------------------------------------------------- Export -------
Write-Step "Export ($variant)"
$stamp    = Get-Date -Format 'yyyyMMdd-HHmm'
$finalApk = Join-Path $Paths.Out "$AppName-godot-$variant-$stamp.apk"
$godot    = Get-ToolPath 'godot'
$exportFlag = if ($Release) { '--export-release' } else { '--export-debug' }

# WICHTIG: Invoke-Native (bare "& $FilePath @Arguments", keine Umleitung)
# liefert bei godot.exe kein $LASTEXITCODE - godot.exe scheint (trotz
# --headless) subsystemseitig wie eine GUI-Anwendung behandelt zu werden,
# PowerShell wartet dann ohne Ausgabeumleitung nicht zuverlaessig synchron
# darauf. Get-NativeOutput leitet stdout/stderr um (wie beim manuellen Test
# mit "2>&1 | Out-String" verifiziert) und wartet dadurch korrekt.
$exportLog = Get-NativeOutput -FilePath $godot -What 'Godot-Export' -Arguments @(
    '--headless',
    '--path', $ProjectRoot,
    $exportFlag, 'Android', $finalApk
)
Write-Info ($exportLog -split "`r?`n" | Select-Object -Last 15 | Out-String)

if (-not (Test-Path $finalApk)) { throw "Godot meldete Erfolg, aber keine APK unter $finalApk gefunden." }

# ------------------------------------------------------- Verifizieren -------
Write-Step 'Verifizieren'
$apksigner = Get-ToolPath 'apksigner'
Get-NativeOutput -FilePath $apksigner -What 'apksigner verify' `
    -Arguments @('verify', '--print-certs', $finalApk) | Out-Null
Write-Ok 'Signatur gueltig'

$aapt2 = Get-ToolPath 'aapt2'
$badging = Get-NativeOutput -FilePath $aapt2 -What 'aapt2 dump badging' -Arguments @('dump', 'badging', $finalApk)

$pkgLine = ($badging -split "`r?`n" | Where-Object { $_ -like 'package:*' } | Select-Object -First 1)
if ($pkgLine -match "name='([^']+)'")        { $pkgName = $Matches[1] } else { $pkgName = '?' }
if ($pkgLine -match "versionCode='([^']+)'") { $verCode = $Matches[1] } else { $verCode = '?' }
if ($pkgLine -match "versionName='([^']+)'") { $verName = $Matches[1] } else { $verName = '?' }
if ($badging -match "sdkVersion:'([^']+)'")        { $minSdk = $Matches[1] } else { $minSdk = '?' }
if ($badging -match "targetSdkVersion:'([^']+)'")  { $tgtSdk = $Matches[1] } else { $tgtSdk = '?' }

Write-Ok "Package     $pkgName"
Write-Ok "Version     $verName (code $verCode)"
Write-Ok "SDK         min $minSdk / target $tgtSdk"

$sizeKb = [math]::Round((Get-Item $finalApk).Length / 1KB, 1)
Write-Host ''
Write-Host '  Fertig.' -ForegroundColor Green
Write-Host "    $finalApk" -ForegroundColor White
Write-Host "    $sizeKb KB" -ForegroundColor Gray
Write-Host ''

if ($Install) {
    Write-Step 'Installieren'
    $adb = Get-ToolPath 'adb'
    $deviceList = Get-NativeOutput -FilePath $adb -Arguments @('devices') -What 'adb devices'
    $devices = @($deviceList -split "`r?`n" | Where-Object { $_ -match '\sdevice$' })
    if ($devices.Count -eq 0) {
        Write-Host '    Kein Geraet gefunden. USB-Debugging aktivieren und Geraet verbinden.' -ForegroundColor Yellow
    } else {
        Invoke-Native -FilePath $adb -Arguments @('install', '-r', $finalApk) -What 'adb install'
        Write-Ok 'Installiert'
    }
}
