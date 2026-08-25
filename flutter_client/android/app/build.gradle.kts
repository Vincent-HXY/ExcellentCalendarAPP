plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val flutterTarget = providers.gradleProperty("target").orNull?.replace('\\', '/')
val buildsFlutterIntegrationTest = flutterTarget?.let { "/${it.trimStart('/')}".contains("/integration_test/") } == true
val requestedGradleTasks = gradle.startParameter.taskNames
val requestsDebugVariant = requestedGradleTasks.any { it.contains("Debug", ignoreCase = true) }
val requestsUnsafeOrImplicitVariant = requestedGradleTasks.any {
    it.contains("Release", ignoreCase = true) || it.contains("Profile", ignoreCase = true)
} || !requestsDebugVariant
if (buildsFlutterIntegrationTest && requestsUnsafeOrImplicitVariant) {
    throw GradleException(
        "Flutter integration tests are restricted to the isolated Debug application id; " +
            "release/profile/implicit variants are forbidden.",
    )
}

android {
    namespace = "com.excellentcalendar.excellent_calendar"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.excellentcalendar.excellent_calendar"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        buildConfigField("boolean", "CALENDAR_CORE_V2_ENABLED", "true")
        buildConfigField("boolean", "CALENDAR_CORE_DEVICE_TEST", "false")
    }

    buildFeatures {
        buildConfig = true
    }

    sourceSets {
        getByName("main").assets.srcDir("../../../cpp_core/third_party/tzdata")
    }

    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
        }
    }

    buildTypes {
        debug {
            // Flutter integration runners uninstall their target package during cleanup.
            // Keep every debug/device run outside the release application sandbox.
            applicationIdSuffix = ".device_test"
            buildConfigField("boolean", "CALENDAR_CORE_DEVICE_TEST", "true")
        }
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    testOptions {
        unitTests.isReturnDefaultValues = true
    }

    lint {
        // Flutter regenerates the ignored Windows local.properties file and
        // escapes backslashes but not the drive-letter colon.
        disable += "PropertyEscape"
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.3")
    implementation("androidx.work:work-runtime:2.11.2")
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.json:json:20240303")
    testImplementation("androidx.work:work-testing:2.11.2")
}
