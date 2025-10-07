// android/app/build.gradle.kts

import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.medirem" // keep yours
    compileSdk = 35

    // --- Load signing props (if key.properties exists) ---
    val keystoreProps = Properties()
    val keystorePropsFile = rootProject.file("key.properties")
    if (keystorePropsFile.exists()) {
        FileInputStream(keystorePropsFile).use { fis ->
            keystoreProps.load(fis)
        }
    }

    defaultConfig {
        applicationId = "com.example.medirem" // keep yours
        minSdk = 23
        targetSdk = 35
        versionCode = 1
        versionName = "1.0"
        multiDexEnabled = true // required because desugaring is enabled
    }

    signingConfigs {
        // Only configure if key.properties exists
        if (keystoreProps.isNotEmpty()) {
            create("release") {
                storeFile = file(keystoreProps.getProperty("storeFile"))
                storePassword = keystoreProps.getProperty("storePassword")
                keyAlias = keystoreProps.getProperty("keyAlias")
                keyPassword = keystoreProps.getProperty("keyPassword")
                enableV1Signing = true
                enableV2Signing = true
            }
        }
    }

    buildTypes {
        getByName("release") {
            isMinifyEnabled = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
            // Attach release signing config only if available
            if (signingConfigs.findByName("release") != null) {
                signingConfig = signingConfigs.getByName("release")
            }
        }
        getByName("debug") {
            // default debug config
        }
    }

    compileOptions {
        // Java 8 + core library desugaring
        sourceCompatibility = JavaVersion.VERSION_1_8
        targetCompatibility = JavaVersion.VERSION_1_8
        isCoreLibraryDesugaringEnabled = true
    }
    kotlinOptions {
        jvmTarget = "1.8"
    }

    packaging {
        resources {
            excludes += setOf("META-INF/AL2.0", "META-INF/LGPL2.1")
        }
    }
}

dependencies {
    implementation("org.jetbrains.kotlin:kotlin-stdlib")

    // Play Core to satisfy Flutter deferred components references (harmless if unused)
    implementation("com.google.android.play:core:1.10.3")

    // Desugaring + multidex
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")
    implementation("androidx.multidex:multidex:2.0.1")
}
// --- Auto-copy APKs after assembleRelease ---
val releaseApk = layout.buildDirectory.file("outputs/apk/release/app-release.apk")
val flutterOutDir = rootProject.layout.buildDirectory.dir("app/outputs/flutter-apk")
val distDir = rootProject.layout.projectDirectory.dir("dist")

// Copy to Flutter's expected folder (so Flutter tools see it)
tasks.register<Copy>("copyReleaseToFlutterOut") {
    from(releaseApk)
    into(flutterOutDir)
}

// Copy to /dist with a friendly name for sharing
tasks.register<Copy>("copyReleaseToDist") {
    from(releaseApk)
    into(distDir)
    rename { "medirem-v1.0-release.apk" }
}

// --- Put this near the bottom of android/app/build.gradle.kts ---

// Export APK after assembleRelease (if/when that task runs)
tasks.matching { it.name == "assembleRelease" }.configureEach {
    finalizedBy("exportReleaseApk")
}

// Export AAB after bundleRelease (if/when that task runs)
tasks.matching { it.name == "bundleRelease" }.configureEach {
    finalizedBy("exportReleaseBundle")
}

// Copies the built APK to /dist with a nice name (runs only if the file exists)
tasks.register<Copy>("exportReleaseApk") {
    val apkFile = layout.buildDirectory.file("outputs/flutter-apk/app-release.apk")
        .orElse(layout.buildDirectory.file("outputs/apk/release/app-release.apk")) // fallback
    from(apkFile)
    into(rootProject.layout.projectDirectory.dir("dist"))
    // If you don’t have versionName available here, you can hardcode or keep “medirem-v1.0”
    rename { "medirem-v1.0-release.apk" }
    onlyIf { apkFile.get().asFile.exists() }
}

// Copies the built AAB to /dist with a nice name (runs only if the file exists)
tasks.register<Copy>("exportReleaseBundle") {
    val aabFile = layout.buildDirectory.file("outputs/bundle/release/app-release.aab")
    from(aabFile)
    into(rootProject.layout.projectDirectory.dir("dist"))
    rename { "medirem-v1.0-release.aab" }
    onlyIf { aabFile.get().asFile.exists() }
}
