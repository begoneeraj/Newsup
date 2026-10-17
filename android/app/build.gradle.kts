import java.util.Properties

plugins {
    id("com.android.application")
    id("com.google.gms.google-services")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing comes from android/key.properties locally (gitignored) or
// from RELEASE_* env vars in CI (see .github/workflows/release-apk.yml) — the
// keystore itself is never committed. Falls back to null so `flutter build`
// for debug/profile still works without either being present.
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(keystorePropertiesFile.inputStream())
}
fun signingProp(propKey: String, envKey: String): String? =
    keystoreProperties.getProperty(propKey) ?: System.getenv(envKey)

if (gradle.startParameter.taskNames.any { it.contains("release", ignoreCase = true) }) {
    for ((property, environment) in listOf(
        "storeFile" to "RELEASE_STORE_FILE", "storePassword" to "RELEASE_STORE_PASSWORD",
        "keyAlias" to "RELEASE_KEY_ALIAS", "keyPassword" to "RELEASE_KEY_PASSWORD"
    )) {
        require(!signingProp(property, environment).isNullOrBlank()) {
            "Release signing is required: configure $property in key.properties or $environment."
        }
    }
}

android {
    namespace = "com.begoneeraj.newsup"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.begoneeraj.newsup"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            val storeFilePath = signingProp("storeFile", "RELEASE_STORE_FILE")
            if (storeFilePath != null) {
                storeFile = file(storeFilePath)
                storePassword = signingProp("storePassword", "RELEASE_STORE_PASSWORD")
                keyAlias = signingProp("keyAlias", "RELEASE_KEY_ALIAS")
                keyPassword = signingProp("keyPassword", "RELEASE_KEY_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            // Never silently produce a debug-signed store submission.
            signingConfig = signingConfigs.getByName("release")
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
