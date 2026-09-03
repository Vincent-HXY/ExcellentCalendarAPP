import java.security.KeyStore
import java.security.MessageDigest
import java.security.cert.X509Certificate
import java.util.Properties
import java.util.jar.JarFile

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val releaseSigningPropertiesFile = rootProject.file("key.properties")
val releaseSigningProperties = Properties().apply {
    if (releaseSigningPropertiesFile.isFile) {
        releaseSigningPropertiesFile.inputStream().use(::load)
    }
}

fun releaseSigningValue(propertyName: String, environmentName: String): String? =
    providers.environmentVariable(environmentName).orNull
        ?.trim()
        ?.takeIf(String::isNotEmpty)
        ?: releaseSigningProperties.getProperty(propertyName)
            ?.trim()
            ?.takeIf(String::isNotEmpty)

val releaseStoreFilePath =
    releaseSigningValue("storeFile", "EXCELLENT_CALENDAR_RELEASE_STORE_FILE")
val releaseStorePassword =
    releaseSigningValue("storePassword", "EXCELLENT_CALENDAR_RELEASE_STORE_PASSWORD")
val releaseKeyAlias =
    releaseSigningValue("keyAlias", "EXCELLENT_CALENDAR_RELEASE_KEY_ALIAS")
val releaseKeyPassword =
    releaseSigningValue("keyPassword", "EXCELLENT_CALENDAR_RELEASE_KEY_PASSWORD")
val releaseCertificateSha256 =
    releaseSigningValue("certificateSha256", "EXCELLENT_CALENDAR_RELEASE_CERT_SHA256")

val releaseSigningInputs = linkedMapOf(
    "storeFile" to releaseStoreFilePath,
    "storePassword" to releaseStorePassword,
    "keyAlias" to releaseKeyAlias,
    "keyPassword" to releaseKeyPassword,
    "certificateSha256" to releaseCertificateSha256,
)
val suppliedReleaseSigningInputs = releaseSigningInputs.filterValues { it != null }
val missingReleaseSigningInputs = releaseSigningInputs.filterValues { it == null }.keys
val releaseSigningConfigured = missingReleaseSigningInputs.isEmpty()

if (suppliedReleaseSigningInputs.isNotEmpty() && !releaseSigningConfigured) {
    throw GradleException(
        "Release signing configuration is incomplete. Missing: " +
            missingReleaseSigningInputs.joinToString(", ") +
            ". Use ignored android/key.properties or EXCELLENT_CALENDAR_RELEASE_* environment variables.",
    )
}

fun normalizedCertificateSha256(value: String): String {
    val normalized = value.replace(":", "").uppercase()
    if (!normalized.matches(Regex("[0-9A-F]{64}"))) {
        throw GradleException("Release certificateSha256 must contain exactly 64 hexadecimal characters.")
    }
    return normalized
}

fun sha256(bytes: ByteArray): String =
    MessageDigest.getInstance("SHA-256")
        .digest(bytes)
        .joinToString("") { "%02X".format(it) }

fun loadReleaseCertificate(storeFile: File, storePassword: String, keyAlias: String): X509Certificate {
    if (!storeFile.isFile) {
        throw GradleException("Release keystore does not exist: ${storeFile.absolutePath}")
    }
    val candidateTypes = listOf(KeyStore.getDefaultType(), "PKCS12", "JKS").distinct()
    for (storeType in candidateTypes) {
        try {
            val keyStore = KeyStore.getInstance(storeType)
            storeFile.inputStream().use { keyStore.load(it, storePassword.toCharArray()) }
            val certificate = keyStore.getCertificate(keyAlias) as? X509Certificate
            if (certificate != null) return certificate
        } catch (_: Exception) {
            // Try the next supported keystore format. The final error is intentionally secret-free.
        }
    }
    throw GradleException(
        "Unable to load the configured release certificate. Check storeFile, storePassword, and keyAlias.",
    )
}

val expectedReleaseCertificateSha256 = releaseCertificateSha256?.let(::normalizedCertificateSha256)
fun validateConfiguredReleaseSigningIdentity() {
    if (!releaseSigningConfigured) {
        throw GradleException(
            "Release signing is not configured. Debug signing is forbidden for Release artifacts. " +
                "Copy android/key.properties.example to the ignored android/key.properties file " +
                "or inject all EXCELLENT_CALENDAR_RELEASE_* environment variables.",
        )
    }
    val certificate = loadReleaseCertificate(
        rootProject.file(releaseStoreFilePath!!),
        releaseStorePassword!!,
        releaseKeyAlias!!,
    )
    val subject = certificate.subjectX500Principal.name
    if (subject.contains("CN=Android Debug", ignoreCase = true)) {
        throw GradleException("Android Debug certificates are forbidden for Release artifacts.")
    }
    val actualDigest = sha256(certificate.encoded)
    if (actualDigest != expectedReleaseCertificateSha256) {
        throw GradleException(
            "Configured release certificate does not match certificateSha256. " +
                "Expected $expectedReleaseCertificateSha256 but found $actualDigest.",
        )
    }
}

val releaseArtifactTaskPaths = setOf(
    "${project.path}:assembleRelease",
    "${project.path}:bundleRelease",
)
gradle.taskGraph.whenReady {
    if (allTasks.any { it.path in releaseArtifactTaskPaths }) {
        validateConfiguredReleaseSigningIdentity()
    }
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

    signingConfigs {
        if (releaseSigningConfigured) {
            create("release") {
                storeFile = rootProject.file(releaseStoreFilePath!!)
                storePassword = releaseStorePassword
                keyAlias = releaseKeyAlias
                keyPassword = releaseKeyPassword
            }
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
            signingConfig = signingConfigs.findByName("release")
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

fun verifyReleaseApkCertificate(apk: File, expectedDigest: String) {
    if (!apk.isFile) throw GradleException("Release APK was not produced: ${apk.absolutePath}")
    val executableSuffix = if (System.getProperty("os.name").startsWith("Windows")) ".bat" else ""
    val apksigner = File(
        android.sdkDirectory,
        "build-tools/${android.buildToolsVersion}/apksigner$executableSuffix",
    )
    if (!apksigner.isFile) {
        throw GradleException("apksigner is unavailable at ${apksigner.absolutePath}")
    }
    val command = if (executableSuffix.isEmpty()) {
        listOf(apksigner.absolutePath, "verify", "--print-certs", apk.absolutePath)
    } else {
        listOf("cmd.exe", "/d", "/c", apksigner.absolutePath, "verify", "--print-certs", apk.absolutePath)
    }
    val process = ProcessBuilder(command).redirectErrorStream(true).start()
    val output = process.inputStream.bufferedReader().use { it.readText() }
    if (process.waitFor() != 0) {
        throw GradleException("Release APK signature verification failed: $output")
    }
    val signerDigests = Regex(
        "certificate SHA-256 digest:\\s*([0-9a-fA-F:]{64,95})",
        RegexOption.IGNORE_CASE,
    ).findAll(output).map { normalizedCertificateSha256(it.groupValues[1]) }.toSet()
    if (signerDigests != setOf(expectedDigest)) {
        throw GradleException(
            "Release APK signer identity mismatch. Expected $expectedDigest but found " +
                signerDigests.joinToString().ifEmpty { "no signer" } + ".",
        )
    }
    if (output.contains("CN=Android Debug", ignoreCase = true)) {
        throw GradleException("Release APK is signed with an Android Debug certificate.")
    }
}

fun verifyReleaseBundleCertificate(bundle: File, expectedDigest: String) {
    if (!bundle.isFile) throw GradleException("Release AAB was not produced: ${bundle.absolutePath}")
    val signerDigests = mutableSetOf<String>()
    JarFile(bundle, true).use { jar ->
        val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
        val entries = jar.entries()
        while (entries.hasMoreElements()) {
            val entry = entries.nextElement()
            if (entry.isDirectory || entry.name.startsWith("META-INF/", ignoreCase = true)) continue
            jar.getInputStream(entry).use { input ->
                while (input.read(buffer) != -1) {
                    // Reading the complete entry makes JarFile verify its signature.
                }
            }
            val signers = entry.codeSigners
                ?: throw GradleException("Release AAB contains an unsigned entry: ${entry.name}")
            signers.forEach { signer ->
                val certificate = signer.signerCertPath.certificates.firstOrNull() as? X509Certificate
                    ?: throw GradleException("Release AAB signer certificate is unavailable.")
                signerDigests += sha256(certificate.encoded)
                if (certificate.subjectX500Principal.name.contains("CN=Android Debug", ignoreCase = true)) {
                    throw GradleException("Release AAB is signed with an Android Debug certificate.")
                }
            }
        }
    }
    if (signerDigests != setOf(expectedDigest)) {
        throw GradleException(
            "Release AAB signer identity mismatch. Expected $expectedDigest but found " +
                signerDigests.joinToString().ifEmpty { "no signer" } + ".",
        )
    }
}

tasks.configureEach {
    when (name) {
        "assembleRelease" -> doLast {
            verifyReleaseApkCertificate(
                layout.buildDirectory.file("outputs/apk/release/app-release.apk").get().asFile,
                expectedReleaseCertificateSha256!!,
            )
        }
        "bundleRelease" -> doLast {
            verifyReleaseBundleCertificate(
                layout.buildDirectory.file("outputs/bundle/release/app-release.aab").get().asFile,
                expectedReleaseCertificateSha256!!,
            )
        }
    }
}

tasks.register("verifyReleaseApkSigning") {
    group = "verification"
    description = "Builds the Release APK and verifies its pinned signing certificate."
    dependsOn("assembleRelease")
}

tasks.register("verifyReleaseBundleSigning") {
    group = "verification"
    description = "Builds the Release AAB and verifies its pinned signing certificate."
    dependsOn("bundleRelease")
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
