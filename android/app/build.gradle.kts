plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val yawmiSigningMode = providers.environmentVariable("YAWMI_SIGNING_MODE").orElse("testing").get()
val githubUpdates = providers.environmentVariable("YAWMI_GITHUB_UPDATES").orElse("false").get() == "true"
val pushProject = providers.environmentVariable("YAWMI_FCM_PROJECT_ID").orElse("").get()
val pushApp = providers.environmentVariable("YAWMI_FCM_APP_ID").orElse("").get()
val pushKey = providers.environmentVariable("YAWMI_FCM_API_KEY").orElse("").get()
val pushSettings = listOf(pushProject, pushApp, pushKey)
val releasePush = githubUpdates && pushSettings.all { it.isNotBlank() }
require(!githubUpdates || pushSettings.all { it.isBlank() } || releasePush) { "Incomplete Firebase update configuration." }
if (releasePush) {
    require(pushProject.matches(Regex("[a-z][a-z0-9-]{4,29}")) &&
        pushApp.matches(Regex("1:[0-9]+:android:[0-9a-f]+")) &&
        pushKey.matches(Regex("[A-Za-z0-9_-]{30,80}"))) { "Invalid Firebase client configuration." }
}
require(yawmiSigningMode in setOf("testing", "unsigned", "release")) { "Invalid YAWMI_SIGNING_MODE." }

android {
    namespace = "app.yawmi.journal"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion
    buildFeatures {
        buildConfig = true
        resValues = releasePush
    }
    if (githubUpdates) {
        sourceSets.getByName("release").manifest.srcFile("src/github/AndroidManifest.xml")
    }
    sourceSets.getByName("main").java.srcDir(if (releasePush) "src/push/kotlin" else "src/noPush/kotlin")

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "app.yawmi.journal"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        buildConfigField("boolean", "GITHUB_UPDATES", githubUpdates.toString())
        manifestPlaceholders["releasePush"] = releasePush.toString()
        if (releasePush) {
            resValue("string", "google_app_id", pushApp)
            resValue("string", "google_api_key", pushKey)
            resValue("string", "gcm_defaultSenderId", pushApp.split(':')[1])
            resValue("string", "project_id", pushProject)
        }
    }

    if (yawmiSigningMode == "release") {
        fun signingValue(name: String): String =
            providers.environmentVariable(name).orNull?.takeIf { it.isNotBlank() }
                ?: error("Missing production signing setting: $name")
        signingConfigs.create("production") {
            storeFile = file(signingValue("YAWMI_KEYSTORE_PATH")).also {
                require(it.isFile) { "Production keystore was not found." }
            }
            storePassword = signingValue("YAWMI_KEYSTORE_PASSWORD")
            keyAlias = signingValue("YAWMI_KEY_ALIAS")
            keyPassword = signingValue("YAWMI_KEY_PASSWORD")
        }
    }

    buildTypes {
        release {
            signingConfig = when (yawmiSigningMode) {
                "release" -> signingConfigs.getByName("production")
                "testing" -> signingConfigs.getByName("debug")
                else -> null
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    implementation("com.google.mlkit:text-recognition:16.0.1")
    if (releasePush) implementation("com.google.firebase:firebase-messaging:25.0.1")
}

flutter {
    source = "../.."
}
