# Setzt die Toolchain-Umgebung NUR fuer die aktuelle PowerShell-Session.
# Keine systemweiten Variablen, kein Admin noetig, keine Spuren ausserhalb
# des Projektordners. Wird von allen anderen Skripten dot-sourced.

Set-StrictMode -Version Latest

$script:LibDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $script:LibDir 'versions.ps1')

$Root      = Split-Path -Parent $script:LibDir
$Toolchain = Join-Path $Root 'toolchain'

$Paths = [ordered]@{
    Root          = $Root
    Toolchain     = $Toolchain
    Jdk           = Join-Path $Toolchain 'jdk'
    Gradle        = Join-Path $Toolchain 'gradle'
    GradleHome    = Join-Path $Toolchain 'gradle-home'
    AndroidSdk    = Join-Path $Toolchain 'android-sdk'
    Downloads     = Join-Path $Toolchain 'downloads'
    Apps          = Join-Path $Root 'apps'
    Templates     = Join-Path $Root 'templates'
    Keys          = Join-Path $Root 'keys'
    Out           = Join-Path $Root 'out'
    EnvJson       = Join-Path $Toolchain 'env.json'
    JunctionMarker= Join-Path $Toolchain 'sdk-path.txt'

    # --- Godot (siehe setup-godot.ps1) --------------------------------------
    Godot         = Join-Path $Toolchain 'godot'
    GodotExe      = Join-Path $Toolchain 'godot\godot.exe'
    GodotDataDir  = Join-Path $Toolchain 'godot\editor_data'       # self-contained mode (._sc_)
    # Godot erwartet Exportvorlagen unter "export_templates\<version>\", nicht
    # nur "templates\" (das legt Godot selbst separat/leer an) - per echtem
    # Exportversuch verifiziert, nicht geraten.
    GodotTemplatesDir = Join-Path $Toolchain 'godot\editor_data\export_templates'
    GodotJdk      = Join-Path $Toolchain 'jdk17'                  # nur angelegt, falls JDK 21 nicht funktioniert
}

# Der Projektpfad enthaelt Leerzeichen ("claude code projects"). Fuer Gradle/AGP
# unkritisch, aber falls setup.ps1 eine Junction auf einen kurzen, leerzeichen-
# freien Pfad angelegt hat, wird ANDROID_HOME auf diese gesetzt.
$SdkHome = $Paths.AndroidSdk
if (Test-Path $Paths.JunctionMarker) {
    $alt = (Get-Content $Paths.JunctionMarker -Raw).Trim()
    if ($alt -and (Test-Path $alt)) { $SdkHome = $alt }
}
$Paths.SdkHome = $SdkHome

# --- Umgebungsvariablen (nur diese Session) ---------------------------------
$env:JAVA_HOME        = $Paths.Jdk
$env:ANDROID_HOME     = $Paths.SdkHome
$env:ANDROID_SDK_ROOT = $Paths.SdkHome
$env:GRADLE_USER_HOME = $Paths.GradleHome   # nichts landet in C:\Users\...\.gradle

$binDirs = @(
    (Join-Path $Paths.Jdk 'bin'),
    (Join-Path $Paths.Gradle 'bin'),
    (Join-Path $Paths.SdkHome 'cmdline-tools\latest\bin'),
    (Join-Path $Paths.SdkHome 'platform-tools')
)
foreach ($d in $binDirs) {
    if ($env:PATH -notlike "*$d*") { $env:PATH = "$d;$env:PATH" }
}

# --- Hilfsfunktionen --------------------------------------------------------

function Get-BuildToolsDir {
    $v  = (Get-ToolchainVersions).BuildToolsVersion
    $bt = Join-Path $Paths.SdkHome "build-tools\$v"
    if (Test-Path $bt) { return $bt }
    # Fallback: hoechste installierte Build-Tools-Version
    $btRoot = Join-Path $Paths.SdkHome 'build-tools'
    if (Test-Path $btRoot) {
        $newest = Get-ChildItem $btRoot -Directory -ErrorAction SilentlyContinue |
                  Sort-Object Name -Descending | Select-Object -First 1
        if ($newest) { return $newest.FullName }
    }
    return $null
}

function Get-ToolPath {
    param([Parameter(Mandatory)][string]$Name)
    switch ($Name) {
        'java'       { return (Join-Path $Paths.Jdk 'bin\java.exe') }
        'keytool'    { return (Join-Path $Paths.Jdk 'bin\keytool.exe') }
        'gradle'     { return (Join-Path $Paths.Gradle 'bin\gradle.bat') }
        'sdkmanager' { return (Join-Path $Paths.SdkHome 'cmdline-tools\latest\bin\sdkmanager.bat') }
        'adb'        { return (Join-Path $Paths.SdkHome 'platform-tools\adb.exe') }
        'godot'      { return $Paths.GodotExe }
        default {
            $bt = Get-BuildToolsDir
            if (-not $bt) { return $null }
            $exe = Join-Path $bt "$Name.exe"
            if (Test-Path $exe) { return $exe }
            $bat = Join-Path $bt "$Name.bat"
            if (Test-Path $bat) { return $bat }
            return $exe
        }
    }
}

function Test-ToolchainReady {
    $needed = @('java', 'gradle', 'sdkmanager')
    foreach ($n in $needed) {
        $p = Get-ToolPath $n
        if (-not $p -or -not (Test-Path $p)) { return $false }
    }
    if (-not (Get-BuildToolsDir)) { return $false }
    return $true
}

function Assert-ToolchainReady {
    if (-not (Test-ToolchainReady)) {
        throw "Toolchain ist nicht (vollstaendig) installiert. Bitte zuerst .\setup.ps1 ausfuehren."
    }
}

# Godots Android-Export braucht ein eigenes JAVA_HOME zur Exportzeit (per
# Umgebungsvariable, nicht ueber PATH) - siehe setup-godot.ps1: das schreibt
# nach dem ersten funktionierenden Testexport fest, ob das gemeinsame JDK 21
# reicht oder ein zweites, eigenes JDK 17 noetig war (godot-jdk-choice.txt).
function Get-GodotJavaHome {
    $marker = Join-Path $Paths.Godot 'jdk-choice.txt'
    if ((Test-Path $marker) -and ((Get-Content $marker -Raw).Trim() -eq '17')) {
        return $Paths.GodotJdk
    }
    return $Paths.Jdk
}

function Test-GodotReady {
    if (-not (Test-Path $Paths.GodotExe)) { return $false }
    if (-not (Test-Path (Join-Path $Paths.GodotTemplatesDir (Get-ToolchainVersions).GodotTemplatesDirName))) { return $false }
    return $true
}

function Assert-GodotReady {
    if (-not (Test-GodotReady)) {
        throw "Godot-Toolchain ist nicht (vollstaendig) installiert. Bitte zuerst .\setup-godot.ps1 ausfuehren."
    }
}

# --- Aufruf externer Programme ----------------------------------------------
#
# Windows PowerShell 5.1 verpackt jede stderr-Zeile eines nativen Programms in
# einen ErrorRecord. Bei $ErrorActionPreference = 'Stop' wird daraus ein
# terminierender Fehler - auch dann, wenn das Programm mit Exitcode 0 sauber
# durchgelaufen ist. Genau das passiert hier staendig: sdkmanager warnt vor
# seiner eigenen Deprecation, keytool, aapt2, adb und Gradle schreiben
# Fortschritt und Warnungen ebenfalls nach stderr.
#
# Deshalb laufen alle nativen Aufrufe ueber diese beiden Helfer. Sie schalten
# die Fehlerbehandlung waehrend des Aufrufs auf 'Continue' und bewerten
# ausschliesslich den Exitcode - das einzige verlaessliche Erfolgssignal.
# ($? ist hier ebenfalls unbrauchbar, es wird durch stderr-Ausgaben falsch.)

$script:LastNativeExitCode = 0

# Fuehrt ein Programm aus und speist stdin aus einer Datei.
#
# Die Pipeline ("'y' | & tool.bat") ist dafuer unbrauchbar: PS 5.1 reicht stdin
# nicht zuverlaessig durch einen Batch-Wrapper an den dahinterliegenden
# Java-Prozess weiter - sdkmanager sieht dann sofort EOF und lehnt still ab.
# Start-Process haengt dagegen ein echtes Datei-Handle an stdin.
function Invoke-NativeWithStdinFile {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [string[]]$Arguments = @(),
        [Parameter(Mandatory)][string]$InputFile,
        [string]$What,
        [switch]$AllowFailure
    )
    if (-not $What) { $What = (Split-Path -Leaf $FilePath) }

    # Start-Process fuegt die ArgumentList in PS 5.1 ungequotet zusammen. Ein
    # Argument wie --sdk_root=D:\claude code projects\... zerfaellt dadurch am
    # Leerzeichen und das Zielprogramm sieht Muell. Also selbst quoten -
    # inklusive Verdoppeln abschliessender Backslashes, die sonst das
    # schliessende Anfuehrungszeichen escapen wuerden.
    $quoted = @($Arguments | ForEach-Object {
        $a = "$_"
        if ($a -match '\s' -and $a -notmatch '"') {
            $trailing = ''
            if ($a -match '(\\+)$') { $trailing = $Matches[1] }
            '"' + $a + $trailing + '"'
        } else {
            $a
        }
    })

    $stdout = [System.IO.Path]::GetTempFileName()
    $stderr = [System.IO.Path]::GetTempFileName()
    try {
        $proc = Start-Process -FilePath $FilePath -ArgumentList $quoted `
            -RedirectStandardInput $InputFile `
            -RedirectStandardOutput $stdout `
            -RedirectStandardError $stderr `
            -NoNewWindow -PassThru -Wait
        $script:LastNativeExitCode = $proc.ExitCode
        $text = (Get-Content $stdout -Raw -ErrorAction SilentlyContinue)
        if (-not $text) { $text = '' }
        # Nur fuer die Fehlermeldung - sonst waere im Fehlerfall nicht zu sehen,
        # woran es lag.
        $errTail = @(Get-Content $stderr -Tail 15 -ErrorAction SilentlyContinue) -join "`r`n"
    } finally {
        Remove-Item $stdout, $stderr -Force -ErrorAction SilentlyContinue
    }

    if (-not $AllowFailure -and $script:LastNativeExitCode -ne 0) {
        throw "$What ist mit Exitcode $($script:LastNativeExitCode) fehlgeschlagen.`r`n$errTail"
    }
    return $text
}

# Fuehrt ein Programm aus und laesst dessen Ausgabe direkt durchlaufen.
function Invoke-Native {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [string[]]$Arguments = @(),
        [string]$StdIn,
        [string]$What,
        [switch]$AllowFailure
    )
    if (-not $What) { $What = (Split-Path -Leaf $FilePath) }
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        if ($StdIn) {
            $StdIn | & $FilePath @Arguments
        } else {
            & $FilePath @Arguments
        }
    } finally {
        $ErrorActionPreference = $previous
    }
    $script:LastNativeExitCode = $LASTEXITCODE
    if (-not $AllowFailure -and $script:LastNativeExitCode -ne 0) {
        throw "$What ist mit Exitcode $($script:LastNativeExitCode) fehlgeschlagen."
    }
}

# Fuehrt ein Programm aus und gibt dessen Ausgabe (inkl. stderr) als Text zurueck.
function Get-NativeOutput {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [string[]]$Arguments = @(),
        [string]$StdIn,
        [string]$What,
        [switch]$AllowFailure
    )
    if (-not $What) { $What = (Split-Path -Leaf $FilePath) }
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $text = ''
    try {
        if ($StdIn) {
            $lines = $StdIn | & $FilePath @Arguments 2>&1 | ForEach-Object { "$_" }
        } else {
            $lines = & $FilePath @Arguments 2>&1 | ForEach-Object { "$_" }
        }
        $text = ($lines -join "`r`n")
    } finally {
        $ErrorActionPreference = $previous
    }
    $script:LastNativeExitCode = $LASTEXITCODE
    if (-not $AllowFailure -and $script:LastNativeExitCode -ne 0) {
        throw "$What ist mit Exitcode $($script:LastNativeExitCode) fehlgeschlagen.`r`n$text"
    }
    return $text
}
