<#
.SYNOPSIS
    Baut aus einem Projekt unter .\apps eine APK und legt sie in .\out ab.
.DESCRIPTION
    Debug-Builds sind sofort sideload-bar und dienen zum Testen.
    Release-Builds werden mit einem projekteigenen Keystore signiert, der beim
    ersten Release-Build automatisch unter .\keys erzeugt wird.

    Nach dem Build wird die APK mit apksigner verifiziert und mit aapt2
    ausgelesen, damit Package-ID und Versionen bestaetigt sind.
.PARAMETER App
    Name des Projekts unter .\apps.
.PARAMETER Release
    Baut die signierte Release-Variante statt Debug.
.PARAMETER Clean
    Loescht vorher die Build-Zwischenstaende des Projekts.
.PARAMETER Install
    Installiert die fertige APK per adb auf einem angeschlossenen Geraet.
.PARAMETER KeystorePassword
    Passwort fuer einen neu anzulegenden Release-Keystore. Ohne Angabe wird
    ein zufaelliges erzeugt und in keys\signing.properties hinterlegt.
.EXAMPLE
    .\build-apk.ps1 -App Notizen
.EXAMPLE
    .\build-apk.ps1 -App Notizen -Release -Install
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$App,
    [switch]$Release,
    [switch]$Clean,
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

$appDir = Join-Path $Paths.Apps $App
if (-not (Test-Path $appDir)) {
    $available = @(Get-ChildItem $Paths.Apps -Directory -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name)
    $hint = 'keine'
    if ($available.Count -gt 0) { $hint = $available -join ', ' }
    throw "Projekt '$App' nicht gefunden unter $($Paths.Apps). Vorhanden: $hint"
}

$variant = 'debug'
if ($Release) { $variant = 'release' }

# ------------------------------------------------- Release-Keystore ---------
$gradleExtraArgs = @()
if ($Release) {
    Write-Step 'Release-Signierung'
    $keystore   = Join-Path $Paths.Keys 'release.jks'
    $propsFile  = Join-Path $Paths.Keys 'signing.properties'
    $alias      = 'release'

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
            '-dname', "CN=$App, OU=apk-builder, O=$App, C=DE"
        ) | Out-Null

        @(
            '# Von build-apk.ps1 erzeugt. NICHT ins Git-Repo aufnehmen.',
            "storeFile=$keystore",
            "storePassword=$KeystorePassword",
            "keyAlias=$alias",
            "keyPassword=$KeystorePassword"
        ) | Set-Content -Path $propsFile -Encoding utf8

        Write-Ok "Keystore erzeugt: $keystore"
        Write-Host ''
        Write-Host '    WICHTIG: Sichere den Ordner .\keys an einem sicheren Ort.' -ForegroundColor Yellow
        Write-Host '    Geht der Keystore verloren, lassen sich bereits installierte' -ForegroundColor Yellow
        Write-Host '    Apps nicht mehr per Update ersetzen - nur noch neu installieren.' -ForegroundColor Yellow
        Write-Host ''
    } else {
        Write-Info "Verwende vorhandenen Keystore: $keystore"
    }

    if (-not (Test-Path $propsFile)) {
        throw "Keystore vorhanden, aber $propsFile fehlt. Passwort ist damit unbekannt - Datei wiederherstellen oder keys\release.jks loeschen und neu erzeugen lassen."
    }

    $props = @{}
    foreach ($line in (Get-Content $propsFile)) {
        if ($line -match '^\s*([^#=]+?)\s*=\s*(.*)$') { $props[$Matches[1]] = $Matches[2] }
    }
    $gradleExtraArgs = @(
        "-PRELEASE_STORE_FILE=$($props['storeFile'])",
        "-PRELEASE_STORE_PASSWORD=$($props['storePassword'])",
        "-PRELEASE_KEY_ALIAS=$($props['keyAlias'])",
        "-PRELEASE_KEY_PASSWORD=$($props['keyPassword'])"
    )
}

# ------------------------------------------------------------- Build --------
$gradle = Get-ToolPath 'gradle'
$tasks = @()
if ($Clean) { $tasks += 'clean' }
if ($Release) { $tasks += 'assembleRelease' } else { $tasks += 'assembleDebug' }

Write-Step "Build ($variant)"
Write-Info "Projekt: $appDir"
Write-Info "Aufgaben: $($tasks -join ', ')"
Write-Info 'Der erste Build laedt das Android Gradle Plugin herunter und dauert einige Minuten.'

$gradleArgs = @('--project-dir', $appDir, '--console=plain') + $tasks + $gradleExtraArgs
Invoke-Native -FilePath $gradle -Arguments $gradleArgs -What 'Gradle-Build'

# --------------------------------------------------------- APK finden -------
$outputsDir = Join-Path $appDir "app\build\outputs\apk\$variant"
$apk = Get-ChildItem $outputsDir -Filter '*.apk' -File -ErrorAction SilentlyContinue |
       Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not $apk) { throw "Keine APK gefunden unter $outputsDir" }

# ------------------------------------------------------- Verifizieren -------
Write-Step 'Verifizieren'

$apksigner = Get-ToolPath 'apksigner'
Get-NativeOutput -FilePath $apksigner -What 'apksigner verify' `
    -Arguments @('verify', '--print-certs', $apk.FullName) | Out-Null
Write-Ok 'Signatur gueltig'

$aapt2 = Get-ToolPath 'aapt2'
$badging = Get-NativeOutput -FilePath $aapt2 -What 'aapt2 dump badging' `
    -Arguments @('dump', 'badging', $apk.FullName)

$pkgLine = ($badging -split "`r?`n" | Where-Object { $_ -like 'package:*' } | Select-Object -First 1)
if ($pkgLine -match "name='([^']+)'")          { $pkgName = $Matches[1] }     else { $pkgName = '?' }
if ($pkgLine -match "versionCode='([^']+)'")   { $verCode = $Matches[1] }     else { $verCode = '?' }
if ($pkgLine -match "versionName='([^']+)'")   { $verName = $Matches[1] }     else { $verName = '?' }
if ($badging -match "application-label:'([^']+)'") { $label = $Matches[1] }   else { $label = '?' }
if ($badging -match "sdkVersion:'([^']+)'")    { $minSdk = $Matches[1] }      else { $minSdk = '?' }
if ($badging -match "targetSdkVersion:'([^']+)'") { $tgtSdk = $Matches[1] }   else { $tgtSdk = '?' }

Write-Ok "Package     $pkgName"
Write-Ok "Label       $label"
Write-Ok "Version     $verName (code $verCode)"
Write-Ok "SDK         min $minSdk / target $tgtSdk"

# ------------------------------------------------------------ Ablegen -------
$stamp    = Get-Date -Format 'yyyyMMdd-HHmm'
$finalApk = Join-Path $Paths.Out "$App-$variant-$stamp.apk"
Copy-Item $apk.FullName $finalApk -Force
$sizeKb = [math]::Round((Get-Item $finalApk).Length / 1KB, 1)

Write-Host ''
Write-Host '  Fertig.' -ForegroundColor Green
Write-Host "    $finalApk" -ForegroundColor White
Write-Host "    $sizeKb KB" -ForegroundColor Gray
Write-Host ''

# ---------------------------------------------------------- Installieren ----
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
} else {
    Write-Host '  Aufs Geraet bringen:' -ForegroundColor White
    Write-Host '    - per USB:  .\build-apk.ps1 -App ' -NoNewline -ForegroundColor Gray
    Write-Host "$App $(if ($Release) { '-Release ' })-Install" -ForegroundColor Gray
    Write-Host '    - oder die Datei aufs Handy kopieren und dort antippen' -ForegroundColor Gray
    Write-Host '      (Installation aus unbekannten Quellen muss erlaubt sein)' -ForegroundColor DarkGray
    Write-Host ''
}
