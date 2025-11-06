// backend/outings_app/android/build.gradle.kts

// Keep the root build file minimal and declarative.
// Versions should align with your Flutter/AGP toolchain.
plugins {
    id("com.android.application") version "8.5.2" apply false
    id("com.android.library") version "8.5.2" apply false
    id("org.jetbrains.kotlin.android") version "1.9.24" apply false

    // Flutter’s Gradle integration loader (present in recent Flutter templates)
    id("dev.flutter.flutter-plugin-loader") version "1.0.0" apply false

    // Google Services (Firebase) — declared here, applied in :app
    id("com.google.gms.google-services") version "4.4.2" apply false
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// A simple clean task is enough.
tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
