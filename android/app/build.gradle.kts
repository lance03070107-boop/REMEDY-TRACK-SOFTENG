import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
    id("com.google.firebase.crashlytics")
}

val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.remedytrack.app"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.remedytrack.app"
        minSdk = 26
        targetSdk = 35
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.exists()) {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                val storePath = keystoreProperties.getProperty("storeFile")
                if (storePath != null) {
                    storeFile = file(storePath)
                }
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        debug {
            ndk {
                // Keep debug APK small by stripping heavy native symbol tables
                debugSymbolLevel = "NONE"
            }
        }
        release {
            val allowDebugReleaseSigning =
                project.findProperty("allowDebugReleaseSigning")?.toString()?.toBoolean() == true
            val isReleaseTask = gradle.startParameter.taskNames.any {
                it.contains("Release", ignoreCase = true)
            }
            if (isReleaseTask && !keystorePropertiesFile.exists() && !allowDebugReleaseSigning) {
                throw GradleException(
                    "Missing android/key.properties for Release APK/AAB signing. " +
                    "Play Store release builds must not fall back to the debug keystore " +
                    "(pass -PallowDebugReleaseSigning=true only for local throwaway checks)."
                )
            }
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            ndk {
                // Keep lightweight symbol tables in AAB BUNDLE-METADATA for Play Console
                // without leaving ~350MB+ of unstripped .so debug symbols in APKs.
                debugSymbolLevel = "SYMBOL_TABLE"
            }
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
