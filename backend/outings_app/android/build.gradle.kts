// backend/outings_app/android/build.gradle.kts

plugins {
    // Google Services (Firebase) — declared at root, applied in :app
    id("com.google.gms.google-services") version "4.4.2" apply false
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
