// android/app/build.gradle.kts

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("dev.flutter.flutter-gradle-plugin") // gives flutter {} and embedder
    id("com.google.gms.google-services")
}

import java.util.Properties
import java.io.FileInputStream

// --- Load keystore properties (for release signing) ---
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    FileInputStream(keystorePropertiesFile).use { stream ->
        keystoreProperties.load(stream)
    }
}

android {
    // ✅ New final app ID / namespace
    namespace = "com.outingswithfriends.app"
    compileSdk = 36

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = "17" }

    defaultConfig {
        // ✅ This is what Google Play checks
        applicationId = "com.outingswithfriends.app"
        minSdk = flutter.minSdkVersion
        targetSdk = 35

        // Provided by Flutter Gradle plugin
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        multiDexEnabled = true
    }

    // Optional (NDK warning you saw – safe to add, or leave out if you prefer)
    // ndkVersion = "27.0.12077973"

    // --- Signing configs ---
    signingConfigs {
        create("release") {
            if (keystoreProperties.isNotEmpty()) {
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
            }
        }
    }

    buildTypes {
        getByName("release") {
            // No shrinking for now (avoids the “Removing unused resources requires code shrinking” error)
            isMinifyEnabled = false
            isShrinkResources = false

            // Use release signing if we have a keystore, otherwise fall back to debug
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
        getByName("debug") {
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.2")
}
