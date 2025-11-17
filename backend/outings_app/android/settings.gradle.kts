// android/settings.gradle.kts  — no imports needed

pluginManagement {
    // Read flutter.sdk from local.properties without imports
    val props = java.util.Properties()
    val lp = file("local.properties")
    if (lp.exists()) {
        lp.inputStream().use { stream -> props.load(stream) }
    }
    val flutterSdkPath = props.getProperty("flutter.sdk")
        ?: throw GradleException("flutter.sdk not set in local.properties")

    // Let Flutter provide its Gradle integration
    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
        maven { url = uri("https://storage.googleapis.com/download.flutter.io") }
        // Mapbox artifacts
        maven {
            url = uri("https://api.mapbox.com/downloads/v2/releases/maven")
            authentication { create<org.gradle.authentication.http.BasicAuthentication>("basic") }
            credentials {
                username = "mapbox"
                password = providers.gradleProperty("MAPBOX_DOWNLOADS_TOKEN").orNull
                    ?: System.getenv("MAPBOX_DOWNLOADS_TOKEN") ?: ""
            }
        }
    }
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.PREFER_SETTINGS)
    repositories {
        google()
        mavenCentral()
        maven { url = uri("https://storage.googleapis.com/download.flutter.io") }
        // Mapbox
        maven {
            url = uri("https://api.mapbox.com/downloads/v2/releases/maven")
            authentication { create<org.gradle.authentication.http.BasicAuthentication>("basic") }
            credentials {
                username = "mapbox"
                password = providers.gradleProperty("MAPBOX_DOWNLOADS_TOKEN").orNull
                    ?: System.getenv("MAPBOX_DOWNLOADS_TOKEN") ?: ""
            }
        }
    }
}

// Core plugins (versions here, applied in modules)
plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "8.6.1" apply false
    id("com.android.library") version "8.6.1" apply false
    id("org.jetbrains.kotlin.android") version "2.0.21" apply false // safe with AGP 8.6.x
    id("com.google.gms.google-services") version "4.4.2" apply false
}

include(":app")
