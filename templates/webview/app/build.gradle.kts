plugins {
    id("com.android.application")
}

// Signing-Daten kommen als Gradle-Properties von build-apk.ps1 (-P...).
// Fehlen sie, wird nur unsigniert bzw. mit dem Debug-Key gebaut.
val releaseStoreFile: String? = providers.gradleProperty("RELEASE_STORE_FILE").orNull

android {
    namespace = "{{PACKAGE_ID}}"
    compileSdk = {{COMPILE_SDK}}

    defaultConfig {
        applicationId = "{{PACKAGE_ID}}"
        minSdk = {{MIN_SDK}}
        targetSdk = {{TARGET_SDK}}
        versionCode = {{VERSION_CODE}}
        versionName = "{{VERSION_NAME}}"
    }

    signingConfigs {
        create("release") {
            if (releaseStoreFile != null) {
                storeFile = file(releaseStoreFile)
                storePassword = providers.gradleProperty("RELEASE_STORE_PASSWORD").get()
                keyAlias = providers.gradleProperty("RELEASE_KEY_ALIAS").get()
                keyPassword = providers.gradleProperty("RELEASE_KEY_PASSWORD").get()
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            isShrinkResources = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
            if (releaseStoreFile != null) {
                signingConfig = signingConfigs.getByName("release")
            }
        }
        debug {
            applicationIdSuffix = ".debug"
            versionNameSuffix = "-debug"
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

// Bewusst ohne Abhaengigkeiten: der WebView-Wrapper braucht weder androidx
// noch Kotlin. Das haelt den Build schnell, die APK klein (< 100 KB Code)
// und vermeidet die komplette Versions-Kompatibilitaetsmatrix.
dependencies {
}
