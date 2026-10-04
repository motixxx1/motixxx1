plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Google Play build: pass the upload key (-PuploadStoreFile=... etc). Without it, the APK is signed
// with the shared key in this folder, the same key as the earlier apps, so it installs over them.
val store = findProperty("uploadStoreFile") != null

android {
    namespace = "com.promarket.app"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }
    kotlinOptions { jvmTarget = "17" }

    defaultConfig {
        minSdk = 26
        targetSdk = 36 // Google Play: new apps and updates must target API 36 from 31 Aug 2026
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        manifestPlaceholders["cleartext"] = if (store) "false" else "true"
    }

    // Two apps from one codebase, with the same ids as before (updates install over the old apps).
    flavorDimensions += "app"
    productFlavors {
        create("client") {
            dimension = "app"
            applicationId = "com.promarket.client"
            resValue("string", "app_name", "זריז")
        }
        create("pro") {
            dimension = "app"
            applicationId = "com.promarket.pro"
            resValue("string", "app_name", "זריז מקצוענים")
        }
    }

    signingConfigs {
        create("shared") {
            storeFile = file("debug.keystore")
            storePassword = "android"
            keyAlias = "androiddebugkey"
            keyPassword = "android"
        }
        if (store) create("upload") {
            storeFile = file(findProperty("uploadStoreFile") as String)
            storePassword = findProperty("uploadStorePassword") as String
            keyAlias = findProperty("uploadKeyAlias") as String
            keyPassword = findProperty("uploadKeyPassword") as String
        }
    }

    buildTypes {
        getByName("debug") { signingConfig = signingConfigs.getByName("shared") }
        getByName("release") {
            signingConfig = signingConfigs.getByName(if (store) "upload" else "shared")
            isMinifyEnabled = false
            isShrinkResources = false
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
