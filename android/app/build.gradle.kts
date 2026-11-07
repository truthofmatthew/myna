import java.util.Properties

plugins {
    id("com.android.application")
}

android {
    namespace = "com.truthofmatthew.myna"
    compileSdk = 37

    defaultConfig {
        applicationId = "com.truthofmatthew.myna"
        minSdk = 31
        targetSdk = 37
        versionCode = 1
        versionName = "0.1.0"
    }

    // Release signing: local.properties (not in git) holds releaseKeystoreProperties=<path to keystore.properties>.
    // Without it, release builds come out unsigned.
    val local = Properties().apply { rootProject.file("local.properties").takeIf { it.exists() }?.inputStream()?.use { load(it) } }
    val keystore = local.getProperty("releaseKeystoreProperties")?.let { path -> Properties().apply { file(path).inputStream().use { load(it) } } }
    if (keystore != null) {
        signingConfigs.create("release") {
            storeFile = file(keystore.getProperty("storeFile"))
            storePassword = keystore.getProperty("storePassword")
            keyAlias = keystore.getProperty("keyAlias")
            keyPassword = keystore.getProperty("keyPassword")
        }
        buildTypes.getByName("release").signingConfig = signingConfigs.getByName("release")
    }
}
