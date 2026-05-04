import java.util.Base64
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

var dartEnvironmentVariables = mutableMapOf("publish" to false)

if (project.hasProperty("dart-defines")) {
    dartEnvironmentVariables.putAll(
            (project.property("dart-defines") as String).split(',').associate { entry ->
                val pair = String(Base64.getDecoder().decode(entry)).split('=')
                pair.first() to (pair.last() == "true")
            }
    )
}

android {
    namespace = "com.nebula.clashmi"
    compileSdkVersion = "android-36"
    buildToolsVersion = "36.0.0"
    ndkVersion = "28.2.13676358" // flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions { jvmTarget = JavaVersion.VERSION_17.toString() }

    defaultConfig {
        applicationId = "com.nebula.clashmi"
        minSdk = 26
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        ndk {
            abiFilters.clear()
            abiFilters += listOf("arm64-v8a")
        }
    }

    buildTypes {
        val keystore = rootProject.file("./key.properties")
        val prop = Properties().apply { keystore.inputStream().use(this::load) }
        named("debug") {}
        named("profile") {
            signingConfig =
                    signingConfigs.create("profile") {
                        storeFile = rootProject.file(prop.getProperty("storeFile.release"))
                        storePassword = prop.getProperty("storePassword.release")
                        keyAlias = prop.getProperty("keyAlias.release")
                        keyPassword = prop.getProperty("keyPassword.release")
                    }
        }
        named("release") {
            signingConfig =
                    signingConfigs.create("release") {
                        storeFile = rootProject.file(prop.getProperty("storeFile.release"))
                        storePassword = prop.getProperty("storePassword.release")
                        keyAlias = prop.getProperty("keyAlias.release")
                        keyPassword = prop.getProperty("keyPassword.release")
                    }
        }
    }
    splits {
        abi {
            isEnable = false
            isUniversalApk = false
        }
    }
    packaging {
        jniLibs {
            excludes += setOf("lib/armeabi-v7a/**", "lib/x86/**", "lib/x86_64/**")
        }
    }
}

flutter { source = "../.." }

dependencies { coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.3") }
