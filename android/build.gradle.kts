// Keep the project build file minimal. Do NOT declare AGP/Kotlin/Flutter plugins here.
// Flutter already provides them via its own tooling.

buildscript {
    repositories {
        google()
        mavenCentral()
    }
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// Optional convenience clean task (works in Kotlin DSL)
tasks.register<Delete>("clean") {
    delete(rootProject.buildDir)
}
