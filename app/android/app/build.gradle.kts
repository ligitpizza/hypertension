plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "fyp.hypertension"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // Base ID; each flavor appends its suffix (D-23).
        applicationId = "fyp.hypertension"
        // NFR-6.1 / D-12: Android 7.0 (API 24), the minimum supported by Flutter 3.44.
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // D-14 / D-23: one codebase, two Android apps.
    flavorDimensions += "app"
    productFlavors {
        create("patient") {
            dimension = "app"
            applicationIdSuffix = ".patient"
            resValue("string", "app_name", "CareFlow")
        }
        create("family") {
            dimension = "app"
            applicationIdSuffix = ".family"
            resValue("string", "app_name", "CareFlow Family")
        }
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
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
