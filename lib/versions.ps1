# Zentral gepinnte Versionen der Toolchain.
# Einziger Ort, an dem Versionen angehoben werden.
#
# Kompatibilitaetsmatrix (Stand 2026-09, recherchiert):
#   AGP 9.4.0  ->  Gradle >= 9.6.0, JDK >= 17, Build-Tools 36.0.0, max compileSdk 37
#   Quelle: https://developer.android.com/build/releases/agp-9-4-0-release-notes

$script:Versions = @{

    # --- Java ---------------------------------------------------------------
    # JDK 21 LTS: ueber dem AGP-Minimum (17), unter dem neuesten LTS (25),
    # damit sicher innerhalb der von Gradle 9.7 unterstuetzten Range.
    # Link + SHA-256 werden zur Laufzeit von der Adoptium-API geholt, damit
    # immer der aktuelle Patchstand mit passendem Checksum verwendet wird.
    JdkFeatureVersion = '21'
    JdkApiUrl         = 'https://api.adoptium.net/v3/assets/latest/21/hotspot?os=windows&architecture=x64&image_type=jdk&vendor=eclipse'

    # --- Gradle -------------------------------------------------------------
    GradleVersion  = '9.7.1'
    GradleUrl      = 'https://services.gradle.org/distributions/gradle-9.7.1-bin.zip'
    GradleSha256   = 'acd53f1edaf02f1a8ff99879f8a34b302661a057d9b063ae9e35b552f804d20a'

    # --- Android SDK command line tools -------------------------------------
    # Quelle: https://developer.android.com/studio ("Command line tools only")
    CmdlineToolsVersion = '15859902'
    CmdlineToolsUrl     = 'https://dl.google.com/android/repository/commandlinetools-win-15859902_latest.zip'
    CmdlineToolsSha256  = '90ae805d20434428bffcb699c290860f19bb5f66a67e6b330067e3de801fb04a'

    # --- Android SDK Pakete (sdkmanager-IDs) --------------------------------
    AndroidApiLevel   = 36
    BuildToolsVersion = '36.0.0'
    SdkPackages       = @(
        'platform-tools',
        'platforms;android-36',
        'build-tools;36.0.0'
    )

    # --- App-Template Defaults ----------------------------------------------
    AgpVersion   = '9.4.0'
    MinSdk       = 24
    CompileSdk   = 36
    TargetSdk    = 36

    # --- Godot (zweite Build-Faehigkeit, siehe setup-godot.ps1) --------------
    # Quelle: https://github.com/godotengine/godot-builds/releases/tag/4.7.2-stable
    # Nicht-Mono-Build (reines GDScript, kein Mono/.NET-Runtime im Export) -
    # bewusste Wahl, siehe CLAUDE.md.
    GodotVersion          = '4.7.2'
    GodotEditorUrl        = 'https://github.com/godotengine/godot-builds/releases/download/4.7.2-stable/Godot_v4.7.2-stable_win64.exe.zip'
    GodotEditorSha256     = '731980f9608d61333e5baf54a2ef17210acc7a538446c0cb9969f002aca1e953'
    GodotTemplatesUrl     = 'https://github.com/godotengine/godot-builds/releases/download/4.7.2-stable/Godot_v4.7.2-stable_export_templates.tpz'
    GodotTemplatesSha256  = 'f298490b8d44d934be425a5a65a51bf15f422428b229a06a6e11d9ffea248011'
    # Godots eigener interner Versionsstring, unter dem es Exportvorlagen
    # erwartet (Ordnername unter editor_data\templates\) - fuer einen
    # Nicht-Mono-Release-Build ist das "<version>.stable".
    GodotTemplatesDirName = '4.7.2.stable'

    # Android-SDK-Pakete, die Godot zusaetzlich zu den obigen (36/36.0.0)
    # braucht - koexistieren additiv im selben SDK-Root, nichts wird ersetzt.
    # Quelle: https://docs.godotengine.org/en/4.7/tutorials/export/exporting_for_android.html
    GodotAndroidApiLevel   = 35
    GodotBuildToolsVersion = '35.0.1'
    GodotSdkPackages       = @(
        'platforms;android-35',
        'build-tools;35.0.1'
    )
    # NDK: laut Godot-Doku Teil des "normalen" Android-Setups, aber
    # UNVERIFIZIERT, ob ein reiner GDScript-Export (kein Custom Build/
    # GDExtension) es wirklich braucht - siehe setup-godot.ps1 (erst ohne
    # versuchen, nur bei Bedarf nachinstallieren). Version/URL/Hash hier nur
    # als Platzhalter fuer den Bedarfsfall vermerkt (r28b, ~750MB):
    # https://developer.android.com/ndk/downloads
    GodotNdkVersion = '28.1.13356709'

    # JDK fuer Godots Android-Export: Godot-Doku nennt 17 als empfohlen,
    # "hoehere Versionen auch unterstuetzt" - aber mehrere 2026-Forenberichte
    # beschreiben Fehlschlaege mit JDK 21 je nach mitgeliefertem
    # Gradle-Template. UNVERIFIZIERT, ob das oben gepinnte JDK 21 fuer den
    # WebView-Pfad hier wiederverwendbar ist - setup-godot.ps1 testet das
    # zuerst, bevor ein zweites, eigenes JDK 17 heruntergeladen wird.
    GodotJdkFeatureVersion = '17'
    GodotJdkApiUrl         = 'https://api.adoptium.net/v3/assets/latest/17/hotspot?os=windows&architecture=x64&image_type=jdk&vendor=eclipse'
}

function Get-ToolchainVersions {
    return $script:Versions
}
