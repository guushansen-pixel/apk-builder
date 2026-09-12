<#
.SYNOPSIS
    Installiert Godot (Editor + Android-Exportvorlagen) als zweite
    Build-Faehigkeit neben der bestehenden WebView-Toolchain.
.DESCRIPTION
    Laedt den portablen Godot-Editor und die Android-Exportvorlagen, prueft
    beides per SHA-256, aktiviert Godots "self-contained mode" (Editor-Daten
    liegen dann unter toolchain\godot\editor_data statt in %APPDATA%), und
    erweitert den BESTEHENDEN Android-SDK-Root additiv um die von Godot
    benoetigten Pakete (platform 35 / build-tools 35.0.1) - nichts wird
    ersetzt, die WebView-Toolchain bleibt unveraendert nutzbar.

    Idempotent: bereits vorhandene Komponenten werden uebersprungen. Ein
    abgebrochener Lauf kann einfach wiederholt werden.
.PARAMETER Force
    Installiert auch bereits vorhandene Komponenten neu.
.PARAMETER UseJdk17
    Laedt zusaetzlich ein eigenes, portables JDK 17 fuer Godots
    Android-Export. Nur noetig, falls das gemeinsame JDK 21 (WebView-Pfad)
    beim Godot-Export tatsaechlich fehlschlaegt (siehe README/CLAUDE.md) -
    daher standardmaessig AUS, nicht vorsorglich installiert.
.PARAMETER WithNdk
    Laedt zusaetzlich das Android NDK. Laut Godot-Doku Teil des "normalen"
    Setups, aber unverifiziert, ob ein reiner GDScript-Export (kein Custom
    Build) es wirklich braucht - deshalb standardmaessig AUS. Nur setzen,
    falls ein Export ohne NDK tatsaechlich fehlschlaegt.
.EXAMPLE
    .\setup-godot.ps1
.EXAMPLE
    .\setup-godot.ps1 -UseJdk17
#>
[CmdletBinding()]
param(
    [switch]$Force,
    [switch]$UseJdk17,
    [switch]$WithNdk
)

$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

. (Join-Path $PSScriptRoot 'lib\env.ps1')
$V = Get-ToolchainVersions

function Write-Step { param([string]$m) Write-Host "`n==> $m" -ForegroundColor Cyan }
function Write-Ok   { param([string]$m) Write-Host "    OK  $m" -ForegroundColor Green }
function Write-Skip { param([string]$m) Write-Host "    --  $m (bereits vorhanden)" -ForegroundColor DarkGray }
function Write-Info { param([string]$m) Write-Host "    $m" -ForegroundColor Gray }

function Get-Sha256 {
    param([string]$Path)
    return (Get-FileHash -Path $Path -Algorithm SHA256).Hash.ToLower()
}

function Save-Download {
    param(
        [Parameter(Mandatory)][string]$Url,
        [Parameter(Mandatory)][string]$Destination,
        [string]$ExpectedSha256
    )
    if ((Test-Path $Destination) -and $ExpectedSha256) {
        if ((Get-Sha256 $Destination) -eq $ExpectedSha256.ToLower()) {
            Write-Skip (Split-Path -Leaf $Destination)
            return
        }
        Write-Info 'Vorhandener Download hat falsche Pruefsumme - wird neu geladen.'
        Remove-Item $Destination -Force
    }
    Write-Info "Lade $Url"
    $tmp = "$Destination.part"
    if (Test-Path $tmp) { Remove-Item $tmp -Force }
    $client = New-Object System.Net.WebClient
    try {
        $client.DownloadFile($Url, $tmp)
    } finally {
        $client.Dispose()
    }
    if ($ExpectedSha256) {
        $actual = Get-Sha256 $tmp
        if ($actual -ne $ExpectedSha256.ToLower()) {
            Remove-Item $tmp -Force
            throw "SHA-256 stimmt nicht fuer $Url (erwartet $($ExpectedSha256.ToLower()), erhalten $actual)"
        }
    }
    Move-Item $tmp $Destination -Force
    $mb = [math]::Round((Get-Item $Destination).Length / 1MB, 1)
    Write-Ok "$(Split-Path -Leaf $Destination) ($mb MB, Pruefsumme OK)"
}

function Expand-ZipTo {
    param(
        [Parameter(Mandatory)][string]$ZipPath,
        [Parameter(Mandatory)][string]$Destination,
        [switch]$Clean
    )
    if ($Clean -and (Test-Path $Destination)) { Remove-Item $Destination -Recurse -Force }
    if (-not (Test-Path $Destination)) { New-Item -ItemType Directory -Path $Destination -Force | Out-Null }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::ExtractToDirectory($ZipPath, $Destination)
}

Write-Host ''
Write-Host '  Godot-Toolchain Setup' -ForegroundColor White
Write-Host "  Zielordner: $($Paths.Godot)" -ForegroundColor DarkGray

Assert-ToolchainReady   # Godot braucht die bestehende WebView-Toolchain (JDK/SDK) als Basis
foreach ($d in @($Paths.Godot, $Paths.GodotDataDir, $Paths.GodotTemplatesDir, $Paths.Downloads)) {
    if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
}

# ------------------------------------------------------------ Godot-Editor --
Write-Step "Godot-Editor $($V.GodotVersion) (portabel, win64, non-Mono)"
if ((Test-Path $Paths.GodotExe) -and -not $Force) {
    Write-Skip 'Godot-Editor'
} else {
    $zip = Join-Path $Paths.Downloads "Godot_v$($V.GodotVersion)-stable_win64.exe.zip"
    Save-Download -Url $V.GodotEditorUrl -Destination $zip -ExpectedSha256 $V.GodotEditorSha256
    Write-Info 'Entpacke Godot-Editor...'
    $staging = Join-Path $Paths.Downloads 'godot-editor-staging'
    Expand-ZipTo -ZipPath $zip -Destination $staging -Clean
    $exe = Get-ChildItem $staging -Filter '*.exe' -File -Recurse | Select-Object -First 1
    if (-not $exe) { throw 'Keine .exe im Godot-Editor-Archiv gefunden.' }
    if (-not (Test-Path $Paths.Godot)) { New-Item -ItemType Directory -Path $Paths.Godot -Force | Out-Null }
    Copy-Item $exe.FullName $Paths.GodotExe -Force
    Remove-Item $staging -Recurse -Force
    if (-not (Test-Path $Paths.GodotExe)) { throw "godot.exe nach dem Kopieren nicht gefunden unter $($Paths.GodotExe)" }
    Write-Ok "Godot-Editor installiert: $($Paths.GodotExe)"
}

# --------------------------------------------- Self-contained mode (._sc_) --
Write-Step 'Self-contained mode (Editor-Daten im Projektordner statt %APPDATA%)'
$scMarker = Join-Path $Paths.Godot '._sc_'
if (-not (Test-Path $scMarker)) {
    New-Item -ItemType File -Path $scMarker -Force | Out-Null
    Write-Ok "._sc_ angelegt: $scMarker"
} else {
    Write-Skip '._sc_'
}

# --------------------------------------------------- Android-Exportvorlagen -
Write-Step "Android-Exportvorlagen $($V.GodotVersion)"
$templatesTarget = Join-Path $Paths.GodotTemplatesDir $V.GodotTemplatesDirName
$androidTemplateMarker = Join-Path $templatesTarget 'android_release.apk'
if ((Test-Path $androidTemplateMarker) -and -not $Force) {
    Write-Skip 'Exportvorlagen'
} else {
    $tpz = Join-Path $Paths.Downloads "Godot_v$($V.GodotVersion)-stable_export_templates.tpz"
    Save-Download -Url $V.GodotTemplatesUrl -Destination $tpz -ExpectedSha256 $V.GodotTemplatesSha256
    Write-Info 'Entpacke Exportvorlagen (das ist ein grosses Archiv, dauert etwas)...'
    $staging = Join-Path $Paths.Downloads 'godot-templates-staging'
    Expand-ZipTo -ZipPath $tpz -Destination $staging -Clean
    # .tpz enthaelt einen "templates\" Wurzelordner - dessen INHALT muss nach
    # editor_data\export_templates\<version>\ (Godots erwarteter Ablageort -
    # nicht "templates\", das legt Godot selbst separat/leer an).
    $inner = Join-Path $staging 'templates'
    if (-not (Test-Path $inner)) { $inner = $staging }
    if (Test-Path $templatesTarget) { Remove-Item $templatesTarget -Recurse -Force }
    New-Item -ItemType Directory -Path $templatesTarget -Force | Out-Null
    Get-ChildItem $inner -Force | ForEach-Object {
        Move-Item $_.FullName (Join-Path $templatesTarget $_.Name) -Force
    }
    Remove-Item $staging -Recurse -Force
    if (-not (Test-Path $androidTemplateMarker)) {
        throw "android_release.apk nach dem Entpacken nicht gefunden unter $templatesTarget - Godot-Vorlagenordner falsch?"
    }
    Write-Ok "Exportvorlagen installiert: $templatesTarget"
}

# ------------------------------------------------- Zusaetzliche SDK-Pakete --
Write-Step 'Android-SDK um Godot-Pakete erweitern (additiv, gleicher SDK-Root)'
$sdkmanagerBat = Get-ToolPath 'sdkmanager'
foreach ($p in $V.GodotSdkPackages) { Write-Info $p }
Invoke-Native -FilePath $sdkmanagerBat `
    -Arguments (@("--sdk_root=$($Paths.SdkHome)") + $V.GodotSdkPackages) `
    -What 'sdkmanager (Godot-Pakete)'

$expected = [ordered]@{
    "Platform $($V.GodotAndroidApiLevel)"      = Join-Path $Paths.SdkHome "platforms\android-$($V.GodotAndroidApiLevel)"
    "Build-Tools $($V.GodotBuildToolsVersion)" = Join-Path $Paths.SdkHome "build-tools\$($V.GodotBuildToolsVersion)"
}
$missing = @()
foreach ($name in $expected.Keys) {
    if (-not (Test-Path $expected[$name])) { $missing += $name }
}
if ($missing.Count -gt 0) {
    throw "sdkmanager meldete Erfolg, aber diese Godot-Pakete fehlen: $($missing -join ', ')"
}
Write-Ok 'Godot-SDK-Pakete installiert und vorhanden (bestehende 36/36.0.0 unangetastet)'

# ------------------------------------------------------------------- NDK ----
if ($WithNdk) {
    Write-Step "Android NDK $($V.GodotNdkVersion) (nur mit -WithNdk angefordert)"
    $ndkPkg = "ndk;$($V.GodotNdkVersion)"
    Invoke-Native -FilePath $sdkmanagerBat `
        -Arguments @("--sdk_root=$($Paths.SdkHome)", $ndkPkg) -What 'sdkmanager (NDK)'
    $ndkDir = Join-Path $Paths.SdkHome "ndk\$($V.GodotNdkVersion)"
    if (-not (Test-Path $ndkDir)) { throw "NDK nach der Installation nicht gefunden unter $ndkDir" }
    Write-Ok "NDK installiert: $ndkDir"
} else {
    Write-Step 'Android NDK'
    Write-Info 'Uebersprungen (nicht angefordert) - siehe .\setup-godot.ps1 -WithNdk, falls ein Export ohne NDK fehlschlaegt.'
}

# ------------------------------------------------------------ JDK 17 (opt.) -
if ($UseJdk17) {
    Write-Step "JDK $($V.GodotJdkFeatureVersion) fuer Godot (eigenes, da JDK 21 laut Test nicht funktioniert)"
    $javaExe = Join-Path $Paths.GodotJdk 'bin\java.exe'
    if ((Test-Path $javaExe) -and -not $Force) {
        Write-Skip 'JDK 17'
    } else {
        Write-Info 'Frage Adoptium-API nach dem aktuellen Patchstand...'
        $asset = @(Invoke-RestMethod -Uri $V.GodotJdkApiUrl -UseBasicParsing) | Select-Object -First 1
        if (-not $asset) { throw 'Adoptium-API lieferte kein passendes JDK-17-Paket.' }
        $pkg = $asset.binary.package
        $zip = Join-Path $Paths.Downloads $pkg.name
        Save-Download -Url $pkg.link -Destination $zip -ExpectedSha256 $pkg.checksum
        Write-Info 'Entpacke JDK 17...'
        Expand-ZipTo -ZipPath $zip -Destination $Paths.GodotJdk -Clean
        $inner = @(Get-ChildItem $Paths.GodotJdk -Force)
        if ($inner.Count -eq 1 -and $inner[0].PSIsContainer) {
            Get-ChildItem $inner[0].FullName -Force | ForEach-Object {
                Move-Item $_.FullName (Join-Path $Paths.GodotJdk $_.Name) -Force
            }
            Remove-Item $inner[0].FullName -Recurse -Force
        }
        if (-not (Test-Path $javaExe)) { throw "java.exe (JDK 17) nach dem Entpacken nicht gefunden unter $javaExe" }
        Write-Ok 'JDK 17 installiert'
    }
    Set-Content -Path (Join-Path $Paths.Godot 'jdk-choice.txt') -Value '17' -Encoding ascii
    Write-Ok 'Godot verwendet ab jetzt JDK 17 (build-godot-apk.ps1 liest das automatisch)'
} else {
    $marker = Join-Path $Paths.Godot 'jdk-choice.txt'
    if (-not (Test-Path $marker)) {
        Set-Content -Path $marker -Value '21' -Encoding ascii
    }
}

Write-Host ''
Write-Host '  Godot-Setup abgeschlossen.' -ForegroundColor Green
Write-Host "    Naechster Schritt: .\new-godot-app.ps1 -Name Hopper -PackageId com.daniel.hopper.godot -ProjectRoot ""D:\claude code projects\hopper\godot""" -ForegroundColor White
Write-Host ''

& (Join-Path $PSScriptRoot 'doctor.ps1')
exit $LASTEXITCODE
