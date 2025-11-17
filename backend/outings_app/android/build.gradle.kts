// android/build.gradle.kts

plugins {
    id("com.google.gms.google-services") apply false
}

// Put all repositories in settings.gradle.kts (we already did)

val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubBuildDir: Directory = newBuildDir.dir(project.name)
    layout.buildDirectory.value(newSubBuildDir)
    evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
