// android/app/build.gradle.kts (Kotlin DSL)

plugins {
    id("com.android.application")
    // ✅ Kotlin plugin ID for Kotlin DSL:
    id("org.jetbrains.kotlin.android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin plugins.
    id("dev.flutter.flutter-gradle-plugin")
    // Firebase / Google services
    id("com.google.gms.google-services")
}

android {
    namespace = "com.example.outings_app"

    // Values provided by Flutter's Gradle plugin
    compileSdk = flutter.compileSdkVersion

    // ✅ Kotlin DSL format; keep only one ndkVersion line:
    ndkVersion = "27.0.12077973"

    // AGP 8.7.x requires Java 17
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions {
        jvmTarget = "17"
    }

    defaultConfig {
        applicationId = "com.example.outings_app"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // Signing with debug keys so `flutter run --release` works during dev.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}
