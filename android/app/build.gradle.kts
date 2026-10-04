plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

// Server address baked into the APK: ./gradlew assembleDebug -PserverUrl=https://your-server
// If empty, the app asks for it on first launch (and it can be changed later).
val serverUrl = (findProperty("serverUrl") as String?).orEmpty()

android {
    namespace = "com.promarket.app"
    compileSdk = 36
    defaultConfig {
        minSdk = 26
        targetSdk = 36 // Google Play: new apps and updates must target API 36 from 31 Aug 2026
        versionCode = 7
        versionName = "0.7.0"
        buildConfigField("String", "SERVER_URL", "\"$serverUrl\"")
    }
    // Two apps from one codebase: customers, and pros/agents/couriers.
    flavorDimensions += "app"
    productFlavors {
        create("client") {
            dimension = "app"
            applicationId = "com.promarket.client"
            resValue("string", "app_name", "זריז")
            buildConfigField("String", "START_PATH", "\"/\"")
        }
        create("pro") {
            dimension = "app"
            applicationId = "com.promarket.pro"
            resValue("string", "app_name", "זריז מקצוענים")
            buildConfigField("String", "START_PATH", "\"/pro\"")
        }
    }
    signingConfigs {
        // Shared debug key so new sideloaded builds install over old ones.
        getByName("debug") {
            storeFile = file("debug.keystore")
            storePassword = "android"
            keyAlias = "androiddebugkey"
            keyPassword = "android"
        }
        // Google Play upload key, passed by CI from repository secrets (never committed).
        create("upload") {
            (findProperty("uploadStoreFile") as String?)?.let {
                storeFile = file(it)
                storePassword = findProperty("uploadStorePassword") as String
                keyAlias = findProperty("uploadKeyAlias") as String
                keyPassword = findProperty("uploadKeyPassword") as String
            }
        }
    }
    buildTypes {
        // Debug = the APKs on GitHub: plain http on the home network allowed, may ask for the server
        // address, and offers a new APK when the native shell changes.
        getByName("debug") {
            buildConfigField("boolean", "SIDELOAD", "true")
            manifestPlaceholders["cleartext"] = "true"
        }
        // Release = Google Play: https only, fixed server, updates only through the store.
        getByName("release") {
            isMinifyEnabled = false
            signingConfig = signingConfigs.getByName(if (findProperty("uploadStoreFile") != null) "upload" else "debug")
            buildConfigField("boolean", "SIDELOAD", "false")
            manifestPlaceholders["cleartext"] = "false"
        }
    }
    buildFeatures { buildConfig = true }
    compileOptions { sourceCompatibility = JavaVersion.VERSION_17; targetCompatibility = JavaVersion.VERSION_17 }
    kotlinOptions { jvmTarget = "17" }
}

dependencies {
    implementation("androidx.core:core-ktx:1.13.1")
    implementation("androidx.appcompat:appcompat:1.7.0")
    implementation("androidx.activity:activity-ktx:1.9.1")
    implementation("androidx.swiperefreshlayout:swiperefreshlayout:1.1.0")
}
