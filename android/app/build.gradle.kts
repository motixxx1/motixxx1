plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

// Server addresses baked into the APK, comma separated, tried in order (public, then LAN): ./gradlew assembleDebug -PserverUrl=http://public:3000,http://lan:3000
// If empty, the app asks for it on first launch (and it can be changed later).
val serverUrl = (findProperty("serverUrl") as String?).orEmpty()

android {
    namespace = "com.promarket.app"
    compileSdk = 34
    defaultConfig {
        minSdk = 26
        targetSdk = 34
        versionCode = 6
        versionName = "0.6.0"
        buildConfigField("String", "SERVER_URL", "\"$serverUrl\"")
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
