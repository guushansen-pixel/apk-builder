<#
.SYNOPSIS
    Legt ein neues (oder ergaenzt ein bestehendes) Godot-Projekt fuer den
    Android-Export mit build-godot-apk.ps1 an.
.DESCRIPTION
    Anders als new-app.ps1 (WebView-Template) generiert dieses Skript KEIN
    Web-Content-Wrapping - das Godot-Projekt selbst (Szenen/Skripte) gehoert
    dem jeweiligen Spiele-Repo (z.B. hopper\godot\), apk-builder liefert nur
    Toolchain/Packaging. Ohne -WebRoot-Aequivalent: entweder ein bereits
    vorhandenes Godot-Projekt unter -ProjectRoot wiederverwenden (nur
    export_presets.cfg wird ergaenzt/aktualisiert), oder mit -Bootstrap ein
    minimales Ein-Szenen-Projekt fuer den Phase-0-Toolchain-Test erzeugen.
.PARAMETER Name
    Anzeigename der App.
.PARAMETER PackageId
    Android Application ID, z.B. com.daniel.hopper.godot.
.PARAMETER ProjectRoot
    Ordner mit dem Godot-Projekt (project.godot liegt dort). Wird bei
    -Bootstrap angelegt, sonst muss er bereits existieren.
.PARAMETER Bootstrap
    Erzeugt ein minimales Ein-Szenen-Testprojekt (Label + ColorRect) statt
    ein bestehendes Projekt vorauszusetzen - fuer den Phase-0-Toolchain-Test.
.PARAMETER VersionName
.PARAMETER VersionCode
.PARAMETER Force
    Ueberschreibt eine bereits vorhandene export_presets.cfg.
.EXAMPLE
    .\new-godot-app.ps1 -Name HopperBootstrap -PackageId com.daniel.hopper.godot.bootstrap -ProjectRoot "D:\claude code projects\hopper\godot" -Bootstrap
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Name,
    [Parameter(Mandatory)][string]$PackageId,
    [Parameter(Mandatory)][string]$ProjectRoot,
    [switch]$Bootstrap,
    [string]$VersionName = '0.1',
    [int]$VersionCode = 1,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib\env.ps1')
$V = Get-ToolchainVersions

function Write-Step { param([string]$m) Write-Host "`n==> $m" -ForegroundColor Cyan }
function Write-Ok   { param([string]$m) Write-Host "    OK  $m" -ForegroundColor Green }
function Write-Info { param([string]$m) Write-Host "    $m" -ForegroundColor Gray }

if ($PackageId -notmatch '^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$') {
    throw "PackageId '$PackageId' sieht nicht wie eine gueltige Android Application ID aus (z.B. com.daniel.hopper.godot)."
}

$projectFile = Join-Path $ProjectRoot 'project.godot'

if ($Bootstrap) {
    Write-Step "Bootstrap-Projekt anlegen: $ProjectRoot"
    if ((Test-Path $projectFile) -and -not $Force) {
        throw "$projectFile existiert bereits. -Force zum Ueberschreiben oder -Bootstrap weglassen, um es unveraendert zu lassen."
    }
    New-Item -ItemType Directory -Path $ProjectRoot -Force | Out-Null

    @'
; Engine configuration file.
; Von new-godot-app.ps1 -Bootstrap erzeugt (Phase-0-Toolchain-Test).

config_version=5

[application]

config/name="{0}"
run/main_scene="res://main.tscn"
config/features=PackedStringArray("4.7", "GDScript")

[rendering]

renderer/rendering_method="mobile"
textures/vram_compression/import_etc2_astc=true
'@ -f $Name | Set-Content -Path $projectFile -Encoding ascii   # kein BOM, siehe Kommentar bei export_presets.cfg

    @'
extends Node2D

func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.11, 0.12, 0.16)
	bg.size = get_viewport_rect().size
	bg.z_index = -10
	add_child(bg)

	var label := Label.new()
	label.text = "Hopper - Godot Bootstrap OK"
	label.position = Vector2(40, 80)
	label.add_theme_font_size_override("font_size", 32)
	add_child(label)
'@ | Set-Content -Path (Join-Path $ProjectRoot 'main.gd') -Encoding ascii

    @'
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://main.gd" id="1"]

[node name="Main" type="Node2D"]
script = ExtResource("1")
'@ | Set-Content -Path (Join-Path $ProjectRoot 'main.tscn') -Encoding ascii

    Write-Ok "Bootstrap-Projekt erzeugt (project.godot, main.gd, main.tscn)"
} else {
    if (-not (Test-Path $projectFile)) {
        throw "$projectFile nicht gefunden. Entweder -Bootstrap fuer ein neues Testprojekt, oder ProjectRoot auf ein bestehendes Godot-Projekt zeigen lassen."
    }
    Write-Info "Bestehendes Projekt wird verwendet: $ProjectRoot"
}

# ---------------------------------------------------- export_presets.cfg ----
# Von Hand nachgebaut (kein GUI-Zugriff moeglich - siehe CLAUDE.md/README fuer
# die Begruendung), Feldstruktur anhand einer bekannten Godot-4-CI-Vorlage
# (abarichello/godot-ci test-project) verifiziert. use_gradle_build=false
# nutzt Godots vorgefertigtes Android-Exportbinary statt eines vollen
# Gradle-Unterprojekts - der einfachste Pfad fuer den ersten Toolchain-Test.
# Nur die arm64-v8a-Architektur (moderne Geraete) fuer kleinere/simplere
# Test-Builds; weitere Architekturen bei Bedarf spaeter ergaenzen.
Write-Step 'export_presets.cfg schreiben'
$presetsFile = Join-Path $ProjectRoot 'export_presets.cfg'
if ((Test-Path $presetsFile) -and -not $Force) {
    Write-Info "$presetsFile existiert bereits - unveraendert gelassen (-Force zum Ueberschreiben)."
} else {
    @'
[preset.0]

name="Android"
platform="Android"
runnable=true
advanced_options=false
dedicated_server=false
custom_features=""
export_filter="all_resources"
include_filter=""
exclude_filter=""
export_path=""
encryption_include_filters=""
encryption_exclude_filters=""
encrypt_pck=false
encrypt_directory=false
script_export_mode=2

[preset.0.options]

custom_template/debug=""
custom_template/release=""
gradle_build/use_gradle_build=false
gradle_build/gradle_build_directory=""
gradle_build/android_source_template=""
gradle_build/compress_native_libraries=false
gradle_build/export_format=0
gradle_build/min_sdk=""
gradle_build/target_sdk=""
architectures/armeabi-v7a=false
architectures/arm64-v8a=true
architectures/x86=false
architectures/x86_64=false
version/code={0}
version/name="{1}"
package/unique_name="{2}"
package/name="{3}"
package/signed=true
package/app_category=2
package/retain_data_on_uninstall=false
package/exclude_from_recents=false
package/show_in_android_tv=false
package/show_in_app_library=true
package/show_as_launcher_app=false
launcher_icons/main_192x192=""
launcher_icons/adaptive_foreground_432x432=""
launcher_icons/adaptive_background_432x432=""
graphics/opengl_debug=false
xr_features/xr_mode=0
screen/immersive_mode=true
screen/support_small=true
screen/support_normal=true
screen/support_large=true
screen/support_xlarge=true
user_data_backup/allow=false
command_line/extra_args=""
apk_expansion/enable=false
apk_expansion/SALT=""
apk_expansion/public_key=""
permissions/custom_permissions=PackedStringArray()
keystore/debug=""
keystore/debug_user=""
keystore/debug_password=""
keystore/release=""
keystore/release_user=""
keystore/release_password=""
'@ -f $VersionCode, $VersionName, $PackageId, $Name |
        # WICHTIG: -Encoding utf8 schreibt in Windows PowerShell 5.1 IMMER ein
        # BOM voraus - Godots ConfigFile-Parser ueberliest das nicht und
        # erkennt dann in der ganzen Datei keinen einzigen Preset (leise,
        # kein Fehler beim Schreiben, nur "Invalid export preset name" beim
        # Export). ascii ist hier sicher, da der Inhalt rein ASCII ist.
        Set-Content -Path $presetsFile -Encoding ascii

    Write-Ok "export_presets.cfg geschrieben (Paket-ID: $PackageId, Version: $VersionName/$VersionCode)"
    Write-Info 'Keystore-Zeilen bleiben leer - build-godot-apk.ps1 reicht sie zur Exportzeit als GODOT_ANDROID_KEYSTORE_RELEASE_* Umgebungsvariablen durch, damit hier keine Passwoerter im Repo landen.'
}

Write-Host ''
Write-Host '  Fertig.' -ForegroundColor Green
Write-Host "    Naechster Schritt: .\build-godot-apk.ps1 -ProjectRoot ""$ProjectRoot"" -AppName $Name -Release" -ForegroundColor White
Write-Host ''
