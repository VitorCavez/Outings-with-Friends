// android/app/build.gradle (Kotlin DSL)

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")

    // NEW: apply Google Services plugin in the app module
    id("com.google.gms.google-services")
}

android {
    namespace = "com.example.outings_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "27.0.12077973"

    ndkVersion "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "com.example.outings_app"
        // FCM requires minSdk 21+. Flutter’s default is usually fine, but if you hit errors set:
        // minSdk = 21
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
