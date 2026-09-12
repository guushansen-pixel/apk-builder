<#
.SYNOPSIS
    Prueft die installierte Toolchain und gibt die gefundenen Versionen aus.
.DESCRIPTION
    Exitcode 0 wenn alles vorhanden ist, sonst 1. Nimmt keine Aenderungen vor.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot 'lib\env.ps1')
$V = Get-ToolchainVersions

$problems = @()

function Show-Check {
    param(
        [string]$Name,
        [bool]$Ok,
        [string]$Detail
    )
    if ($Ok) {
        Write-Host ('  [ok]   {0,-18} {1}' -f $Name, $Detail) -ForegroundColor Green
    } else {
        Write-Host ('  [FEHL] {0,-18} {1}' -f $Name, $Detail) -ForegroundColor Red
        $script:problems += $Name
    }
}

# Fuehrt ein Tool aus und gibt die erste passende Ausgabezeile zurueck.
# java und gradle schreiben ihre Version nach stderr - Get-NativeOutput faengt
# beide Stroeme ein, ohne dass PowerShell daraus einen Fehler macht.
function Get-VersionLine {
    param(
        [string]$Exe,
        [string[]]$Arguments,
        [string]$Match
    )
    try {
        $out = Get-NativeOutput -FilePath $Exe -Arguments $Arguments -AllowFailure
        $lines = @($out -split "`r?`n" | Where-Object { $_.Trim() -ne '' })
        if ($Match) {
            $hit = $lines | Where-Object { $_ -match $Match } | Select-Object -First 1
            if ($hit) { return $hit.Trim() }
        }
        if ($lines.Count -gt 0) { return $lines[0].Trim() }
        return ''
    } catch {
        return ''
    }
}

Write-Host ''
Write-Host '  Toolchain-Check' -ForegroundColor White
Write-Host "  Root: $($Paths.Root)" -ForegroundColor DarkGray
Write-Host ''

# --- JDK --------------------------------------------------------------------
$java = Get-ToolPath 'java'
if (Test-Path $java) {
    $ver = Get-VersionLine -Exe $java -Arguments @('-version') -Match 'version'
    Show-Check 'JDK' $true $ver
} else {
    Show-Check 'JDK' $false "nicht gefunden: $java"
}

$keytool = Get-ToolPath 'keytool'
Show-Check 'keytool' (Test-Path $keytool) $keytool

# --- Gradle -----------------------------------------------------------------
$gradle = Get-ToolPath 'gradle'
if (Test-Path $gradle) {
    $ver = Get-VersionLine -Exe $gradle -Arguments @('--version') -Match '^Gradle '
    if (-not $ver) { $ver = "erwartet $($V.GradleVersion)" }
    Show-Check 'Gradle' $true $ver
} else {
    Show-Check 'Gradle' $false "nicht gefunden: $gradle"
}

# --- Android SDK ------------------------------------------------------------
$sdkmanager = Get-ToolPath 'sdkmanager'
Show-Check 'sdkmanager' (Test-Path $sdkmanager) $sdkmanager

$platform = Join-Path $Paths.SdkHome "platforms\android-$($V.AndroidApiLevel)"
Show-Check "Platform $($V.AndroidApiLevel)" (Test-Path $platform) $platform

$bt = Get-BuildToolsDir
if ($bt) {
    Show-Check 'Build-Tools' $true (Split-Path -Leaf $bt)
} else {
    Show-Check 'Build-Tools' $false "erwartet $($V.BuildToolsVersion)"
}

foreach ($tool in @('aapt2', 'apksigner', 'zipalign', 'd8')) {
    $p = Get-ToolPath $tool
    $ok = $false
    if ($p) { $ok = Test-Path $p }
    Show-Check $tool $ok $p
}

$adb = Get-ToolPath 'adb'
Show-Check 'adb' (Test-Path $adb) $adb

# --- Umgebung ---------------------------------------------------------------
Write-Host ''
Write-Host '  Umgebung (nur diese Session)' -ForegroundColor White
Write-Host "    JAVA_HOME        = $env:JAVA_HOME" -ForegroundColor Gray
Write-Host "    ANDROID_HOME     = $env:ANDROID_HOME" -ForegroundColor Gray
Write-Host "    GRADLE_USER_HOME = $env:GRADLE_USER_HOME" -ForegroundColor Gray

if ($Paths.SdkHome -ne $Paths.AndroidSdk) {
    Write-Host "    (SDK ueber Junction: $($Paths.SdkHome))" -ForegroundColor DarkYellow
} elseif ($Paths.AndroidSdk -match ' ') {
    Write-Host '    (SDK-Pfad enthaelt Leerzeichen - von sdkmanager akzeptiert)' -ForegroundColor DarkGray
}

# --- Release-Keystore -------------------------------------------------------
$ks = Join-Path $Paths.Keys 'release.jks'
if (Test-Path $ks) {
    Write-Host "    Release-Keystore  = vorhanden" -ForegroundColor Gray
} else {
    Write-Host "    Release-Keystore  = noch keiner (wird beim ersten -Release Build erzeugt)" -ForegroundColor Gray
}

# --- Godot (zweite Build-Faehigkeit, optional) ------------------------------
Write-Host ''
Write-Host '  Godot' -ForegroundColor White
$godotProblems = @()
function Show-GodotCheck {
    param([string]$Name, [bool]$Ok, [string]$Detail)
    if ($Ok) {
        Write-Host ('  [ok]   {0,-18} {1}' -f $Name, $Detail) -ForegroundColor Green
    } else {
        Write-Host ('  [--]   {0,-18} {1}' -f $Name, $Detail) -ForegroundColor DarkYellow
        $script:godotProblems += $Name
    }
}
$godotExe = Get-ToolPath 'godot'
if (Test-Path $godotExe) {
    $ver = Get-VersionLine -Exe $godotExe -Arguments @('--version') -AllowFailure
    Show-GodotCheck 'Godot-Editor' $true $ver
} else {
    Show-GodotCheck 'Godot-Editor' $false 'nicht installiert - .\setup-godot.ps1 ausfuehren'
}
$templatesDir = Join-Path $Paths.GodotTemplatesDir $V.GodotTemplatesDirName
Show-GodotCheck 'Exportvorlagen' (Test-Path (Join-Path $templatesDir 'android_release.apk')) $templatesDir
Show-GodotCheck "Platform $($V.GodotAndroidApiLevel)" (Test-Path (Join-Path $Paths.SdkHome "platforms\android-$($V.GodotAndroidApiLevel)")) ''
Show-GodotCheck "Build-Tools $($V.GodotBuildToolsVersion)" (Test-Path (Join-Path $Paths.SdkHome "build-tools\$($V.GodotBuildToolsVersion)")) ''
$jdkChoiceFile = Join-Path $Paths.Godot 'jdk-choice.txt'
if (Test-Path $jdkChoiceFile) {
    Write-Host "    JDK fuer Godot-Export = $((Get-Content $jdkChoiceFile -Raw).Trim())" -ForegroundColor Gray
}
if ($godotProblems.Count -gt 0) {
    Write-Host "    (Godot ist optional - fehlt nur, wenn .\setup-godot.ps1 noch nicht lief)" -ForegroundColor DarkGray
}

Write-Host ''
if ($problems.Count -eq 0) {
    Write-Host '  Alles bereit. Naechster Schritt:' -ForegroundColor Green
    Write-Host '    .\new-app.ps1 -Name MeineApp -PackageId com.daniel.meineapp' -ForegroundColor White
    Write-Host ''
    exit 0
} else {
    Write-Host "  Fehlend: $($problems -join ', ')" -ForegroundColor Red
    Write-Host '  Bitte .\setup.ps1 ausfuehren.' -ForegroundColor Yellow
    Write-Host ''
    exit 1
}
