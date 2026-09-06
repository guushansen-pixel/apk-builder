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
}

function Get-ToolchainVersions {
    return $script:Versions
}
