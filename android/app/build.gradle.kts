import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
    id("com.google.firebase.crashlytics")
}

android {
    namespace = "com.example.aurarun_app"
    compileSdk = 36
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.example.aurarun_app"
        minSdk = 26
        targetSdk = 35
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // Mapbox token from android/local.properties (not in git) or the MAPBOX_ACCESS_TOKEN env variable
        val localProps = Properties().apply {
            val f = rootProject.file("local.properties")
            if (f.exists()) f.inputStream().use { load(it) }
        }
        manifestPlaceholders["MAPBOX_ACCESS_TOKEN"] =
            localProps.getProperty("MAPBOX_ACCESS_TOKEN") ?: System.getenv("MAPBOX_ACCESS_TOKEN") ?: ""
    }

    packaging {
        resources {
            excludes += "META-INF/LICENSE*"
            excludes += "META-INF/NOTICE*"
            excludes += "META-INF/*.kotlin_module"
            excludes += "META-INF/versions/9/OSGI-INF/MANIFEST.MF"
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
            firebaseCrashlytics {
                mappingFileUploadEnabled = true
            }
        }
    }
}

flutter {
    source = "../.."
}