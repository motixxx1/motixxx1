plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

// Server addresses baked into the APK, comma separated, tried in order (public, then LAN): ./gradlew assembleDebug -PserverUrl=http://public:3000,http://lan:3000
// If empty, the app asks for it on first launch (and it can be changed later).
val serverUrl = (findProperty("serverUrl") as String?).orEmpty()
// -Pstore=true: the Google Play build. No address box for end users, and plain http is blocked
// when every address is https.
val store = findProperty("store") == "true"
val httpsOnly = serverUrl.isNotBlank() && serverUrl.split(",").all { it.trim().startsWith("https://") }
// Release signing comes from the environment (CI secrets); see docs/PUBLISHING.md.
val releaseKeystore = System.getenv("KEYSTORE_FILE")?.takeIf { it.isNotBlank() }

android {
    namespace = "com.promarket.app"
    compileSdk = 36
    defaultConfig {
        minSdk = 26
        targetSdk = 36
        // CI passes a growing number so every upload to Play is newer than the last.
        versionCode = (findProperty("versionCode") as String?)?.toInt() ?: 7
        versionName = "0.7.0"
        buildConfigField("String", "SERVER_URL", "\"$serverUrl\"")
        buildConfigField("boolean", "STORE", store.toString())
        manifestPlaceholders["cleartext"] = (!httpsOnly).toString()
    }
    // Two apps from one codebase: customers, and pros/agents/couriers.
    flavorDimensions += "app"
    productFlavors {
        create("client") {
            dimension = "app"
            applicationId = "com.promarket.client"
            resValue("string", "app_name", "ProMarket")
            buildConfigField("String", "START_PATH", "\"/\"")
        }
        create("pro") {
            dimension = "app"
            applicationId = "com.promarket.pro"
            resValue("string", "app_name", "ProMarket למקצוענים")
            buildConfigField("String", "START_PATH", "\"/pro\"")
        }
    }
    signingConfigs {
        // Shared debug key so new builds install over old ones. Use a private key for the Play Store.
        getByName("debug") {
            storeFile = file("debug.keystore")
            storePassword = "android"
            keyAlias = "androiddebugkey"
            keyPassword = "android"
        }
    }
    if (releaseKeystore != null) {
        signingConfigs.create("release") {
            storeFile = file(releaseKeystore)
            storePassword = System.getenv("KEYSTORE_PASSWORD")
            keyAlias = System.getenv("KEY_ALIAS")
            keyPassword = System.getenv("KEY_PASSWORD")
        }
    }
    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
            // Without a private key the release is signed with the debug key: fine for testing, never for Play.
            signingConfig = signingConfigs.findByName("release") ?: signingConfigs.getByName("debug")
        }
    }
    lint { abortOnError = false }
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
