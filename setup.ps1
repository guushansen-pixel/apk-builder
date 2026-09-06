<#
.SYNOPSIS
    Installiert die komplette Android-Build-Toolchain in .\toolchain.
.DESCRIPTION
    Laedt JDK 21 (Temurin), Gradle und die Android SDK command line tools,
    prueft jeden Download per SHA-256 und installiert die noetigen SDK-Pakete.

    Idempotent: bereits vorhandene Komponenten werden uebersprungen. Ein
    abgebrochener Lauf kann einfach wiederholt werden.

    Aendert nichts ausserhalb dieses Projektordners und braucht keine
    Administratorrechte. Zum Entfernen genuegt das Loeschen von .\toolchain.
.PARAMETER AcceptLicenses
    Akzeptiert die Android SDK Lizenzen ohne Rueckfrage.
.PARAMETER Force
    Installiert auch bereits vorhandene Komponenten neu.
.EXAMPLE
    .\setup.ps1
#>
[CmdletBinding()]
param(
    [switch]$AcceptLicenses,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'   # sonst ist der Download extrem langsam
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

. (Join-Path $PSScriptRoot 'lib\env.ps1')
$V = Get-ToolchainVersions

# ---------------------------------------------------------------- Ausgabe ---
function Write-Step { param([string]$m) Write-Host "`n==> $m" -ForegroundColor Cyan }
function Write-Ok   { param([string]$m) Write-Host "    OK  $m" -ForegroundColor Green }
function Write-Skip { param([string]$m) Write-Host "    --  $m (bereits vorhanden)" -ForegroundColor DarkGray }
function Write-Info { param([string]$m) Write-Host "    $m" -ForegroundColor Gray }

# ------------------------------------------------------------- Hilfsmittel --
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
        [Parameter(Mandatory)][string]$Destination
    )
    if (Test-Path $Destination) { Remove-Item $Destination -Recurse -Force }
    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::ExtractToDirectory($ZipPath, $Destination)
}

# Zip-Archive haben meist genau einen Wurzelordner (z.B. jdk-21.0.x).
# Dessen Inhalt wird eine Ebene nach oben gezogen, damit die Pfade stabil sind.
function Move-SingleRootUp {
    param([Parameter(Mandatory)][string]$Directory)
    $entries = @(Get-ChildItem $Directory -Force)
    if ($entries.Count -ne 1 -or -not $entries[0].PSIsContainer) { return }
    $inner = $entries[0].FullName
    Get-ChildItem $inner -Force | ForEach-Object {
        Move-Item $_.FullName (Join-Path $Directory $_.Name) -Force
    }
    Remove-Item $inner -Recurse -Force
}

# ============================================================== Ausfuehrung ==
Write-Host ''
Write-Host '  APK-Builder Setup' -ForegroundColor White
Write-Host "  Zielordner: $($Paths.Toolchain)" -ForegroundColor DarkGray

foreach ($d in @($Paths.Toolchain, $Paths.Downloads, $Paths.GradleHome, $Paths.Apps, $Paths.Keys, $Paths.Out)) {
    if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
}

$driveLetter = $Paths.Root.Substring(0, 1)
$freeGb = [math]::Round((Get-PSDrive -Name $driveLetter).Free / 1GB, 1)
Write-Info "Freier Speicher auf ${driveLetter}: $freeGb GB (benoetigt: ca. 4 GB)"
if ($freeGb -lt 4) { throw "Zu wenig freier Speicherplatz ($freeGb GB)." }

# ------------------------------------------------------------------- JDK ----
Write-Step "JDK $($V.JdkFeatureVersion) (Eclipse Temurin)"
$javaExe = Join-Path $Paths.Jdk 'bin\java.exe'
if ((Test-Path $javaExe) -and -not $Force) {
    Write-Skip 'JDK'
} else {
    Write-Info 'Frage Adoptium-API nach dem aktuellen Patchstand...'
    $asset = @(Invoke-RestMethod -Uri $V.JdkApiUrl -UseBasicParsing) | Select-Object -First 1
    if (-not $asset) { throw 'Adoptium-API lieferte kein passendes JDK-Paket.' }
    $pkg = $asset.binary.package
    Write-Info "Version $($asset.version.openjdk_version)"

    $zip = Join-Path $Paths.Downloads $pkg.name
    Save-Download -Url $pkg.link -Destination $zip -ExpectedSha256 $pkg.checksum
    Write-Info 'Entpacke JDK...'
    Expand-ZipTo -ZipPath $zip -Destination $Paths.Jdk
    Move-SingleRootUp -Directory $Paths.Jdk
    if (-not (Test-Path $javaExe)) { throw "java.exe nach dem Entpacken nicht gefunden unter $javaExe" }
    Write-Ok 'JDK installiert'
}

# ---------------------------------------------------------------- Gradle ----
Write-Step "Gradle $($V.GradleVersion)"
$gradleBat = Join-Path $Paths.Gradle 'bin\gradle.bat'
if ((Test-Path $gradleBat) -and -not $Force) {
    Write-Skip 'Gradle'
} else {
    $zip = Join-Path $Paths.Downloads "gradle-$($V.GradleVersion)-bin.zip"
    Save-Download -Url $V.GradleUrl -Destination $zip -ExpectedSha256 $V.GradleSha256
    Write-Info 'Entpacke Gradle...'
    Expand-ZipTo -ZipPath $zip -Destination $Paths.Gradle
    Move-SingleRootUp -Directory $Paths.Gradle
    if (-not (Test-Path $gradleBat)) { throw 'gradle.bat nach dem Entpacken nicht gefunden.' }
    Write-Ok 'Gradle installiert'
}

# ------------------------------------------------- Android cmdline-tools ----
Write-Step "Android command line tools ($($V.CmdlineToolsVersion))"
$sdkmanagerBat = Join-Path $Paths.AndroidSdk 'cmdline-tools\latest\bin\sdkmanager.bat'
if ((Test-Path $sdkmanagerBat) -and -not $Force) {
    Write-Skip 'cmdline-tools'
} else {
    $zip = Join-Path $Paths.Downloads "commandlinetools-win-$($V.CmdlineToolsVersion).zip"
    Save-Download -Url $V.CmdlineToolsUrl -Destination $zip -ExpectedSha256 $V.CmdlineToolsSha256

    Write-Info 'Entpacke command line tools...'
    $staging = Join-Path $Paths.Downloads 'cmdline-staging'
    Expand-ZipTo -ZipPath $zip -Destination $staging

    # Das Archiv enthaelt "cmdline-tools\...". sdkmanager verlangt zwingend die
    # Struktur <sdk>\cmdline-tools\latest\bin, sonst findet es sein SDK-Root nicht.
    $target = Join-Path $Paths.AndroidSdk 'cmdline-tools\latest'
    if (Test-Path $target) { Remove-Item $target -Recurse -Force }
    New-Item -ItemType Directory -Path $target -Force | Out-Null
    $src = Join-Path $staging 'cmdline-tools'
    if (-not (Test-Path $src)) { $src = $staging }
    Get-ChildItem $src -Force | ForEach-Object {
        Move-Item $_.FullName (Join-Path $target $_.Name) -Force
    }
    Remove-Item $staging -Recurse -Force
    if (-not (Test-Path $sdkmanagerBat)) { throw 'sdkmanager.bat nach dem Entpacken nicht gefunden.' }
    Write-Ok 'command line tools installiert'
}

# ---- Leerzeichen-im-Pfad-Test: notfalls Junction auf kurzen Pfad ------------
Write-Step 'Pruefe SDK-Pfad (Projektpfad enthaelt Leerzeichen)'
$env:ANDROID_HOME     = $Paths.AndroidSdk
$env:ANDROID_SDK_ROOT = $Paths.AndroidSdk
Get-NativeOutput -FilePath $sdkmanagerBat -Arguments @('--version') -AllowFailure | Out-Null
if ($LastNativeExitCode -ne 0) {
    Write-Info 'sdkmanager kommt mit dem Pfad nicht zurecht - lege Junction an.'
    $junction = Join-Path $env:LOCALAPPDATA 'apk-builder-sdk'
    if (Test-Path $junction) { Remove-Item $junction -Force -Recurse }
    New-Item -ItemType Junction -Path $junction -Target $Paths.AndroidSdk | Out-Null
    Set-Content -Path $Paths.JunctionMarker -Value $junction -Encoding utf8
    $Paths.SdkHome        = $junction
    $env:ANDROID_HOME     = $junction
    $env:ANDROID_SDK_ROOT = $junction
    $sdkmanagerBat        = Join-Path $junction 'cmdline-tools\latest\bin\sdkmanager.bat'
    Write-Ok "Junction angelegt: $junction"
} else {
    Write-Ok 'Pfad wird direkt unterstuetzt (keine Junction noetig)'
}

# --------------------------------------------------------------- Lizenzen ---
Write-Step 'Android SDK Lizenzen'
$licensesDir = Join-Path $Paths.SdkHome 'licenses'
$licenseFiles = @()
if (Test-Path $licensesDir) {
    $licenseFiles = @(Get-ChildItem $licensesDir -File -ErrorAction SilentlyContinue)
}

if ($licenseFiles.Count -gt 0 -and -not $Force) {
    Write-Skip 'Lizenzen'
} else {
    if (-not $AcceptLicenses) {
        Write-Host ''
        Write-Host '    Zur Installation der SDK-Pakete musst du die Android SDK Lizenzen' -ForegroundColor Yellow
        Write-Host '    akzeptieren. Volltext: https://developer.android.com/studio/terms' -ForegroundColor Yellow
        Write-Host ''
        $answer = Read-Host '    Lizenzen akzeptieren? [j/N]'
        if ($answer -notmatch '^(j|ja|y|yes)$') {
            throw 'Setup abgebrochen: Lizenzen nicht akzeptiert.'
        }
    }
    Write-Info 'Akzeptiere Lizenzen...'
    $yesFile = Join-Path $Paths.Downloads 'accept-licenses.txt'
    Set-Content -Path $yesFile -Value (1..60 | ForEach-Object { 'y' }) -Encoding ascii

    Invoke-NativeWithStdinFile -FilePath $sdkmanagerBat `
        -Arguments @('--licenses', "--sdk_root=$($Paths.SdkHome)") `
        -InputFile $yesFile -What 'sdkmanager --licenses' | Out-Null
    Remove-Item $yesFile -Force -ErrorAction SilentlyContinue

    # sdkmanager beendet sich auch dann mit 0, wenn es nichts akzeptiert hat.
    # Verlaesslich ist nur, ob die Lizenzdateien tatsaechlich angelegt wurden.
    $written = @()
    if (Test-Path $licensesDir) {
        $written = @(Get-ChildItem $licensesDir -File -ErrorAction SilentlyContinue)
    }
    if ($written.Count -eq 0) {
        throw 'Die Lizenzen konnten nicht akzeptiert werden - es wurde keine Lizenzdatei geschrieben.'
    }
    Write-Ok "Lizenzen akzeptiert ($($written.Count) Stueck)"
}

# ------------------------------------------------------------ SDK-Pakete ----
Write-Step 'SDK-Pakete installieren'
foreach ($p in $V.SdkPackages) { Write-Info $p }
Invoke-Native -FilePath $sdkmanagerBat `
    -Arguments (@("--sdk_root=$($Paths.SdkHome)") + $V.SdkPackages) `
    -What 'sdkmanager'

# sdkmanager meldet auch dann Erfolg, wenn es Pakete stillschweigend
# uebersprungen hat (z.B. bei nicht akzeptierten Lizenzen). Deshalb wird das
# Ergebnis auf der Platte geprueft, nicht der Exitcode.
$expected = [ordered]@{
    "Platform $($V.AndroidApiLevel)"      = Join-Path $Paths.SdkHome "platforms\android-$($V.AndroidApiLevel)"
    "Build-Tools $($V.BuildToolsVersion)" = Join-Path $Paths.SdkHome "build-tools\$($V.BuildToolsVersion)"
    'platform-tools (adb)'                = Join-Path $Paths.SdkHome 'platform-tools\adb.exe'
}
$missing = @()
foreach ($name in $expected.Keys) {
    if (-not (Test-Path $expected[$name])) { $missing += $name }
}
if ($missing.Count -gt 0) {
    throw "sdkmanager meldete Erfolg, aber diese Pakete fehlen: $($missing -join ', ')"
}
Write-Ok 'SDK-Pakete installiert und vorhanden'

# -------------------------------------------------------------- env.json ----
$envInfo = [ordered]@{
    generatedAt       = (Get-Date).ToString('s')
    javaHome          = $Paths.Jdk
    androidHome       = $Paths.SdkHome
    gradleHome        = $Paths.Gradle
    gradleUserHome    = $Paths.GradleHome
    buildToolsVersion = $V.BuildToolsVersion
    androidApiLevel   = $V.AndroidApiLevel
    gradleVersion     = $V.GradleVersion
}
$envInfo | ConvertTo-Json | Set-Content -Path $Paths.EnvJson -Encoding utf8

Write-Host ''
Write-Host '  Setup abgeschlossen.' -ForegroundColor Green
Write-Host ''

# Exitcode von doctor.ps1 durchreichen: ein Setup, nach dem der Check
# fehlschlaegt, darf sich nicht als erfolgreich melden.
& (Join-Path $PSScriptRoot 'doctor.ps1')
exit $LASTEXITCODE
