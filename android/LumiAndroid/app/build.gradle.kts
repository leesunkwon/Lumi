import java.util.Properties

plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.ksp)
}

val localProperties = Properties().apply {
    val localPropertiesFile = rootProject.file("local.properties")
    if (localPropertiesFile.exists()) {
        localPropertiesFile.inputStream().use(::load)
    }
}

fun localValue(name: String): String = localProperties.getProperty(name).orEmpty()
fun escapedBuildConfigValue(name: String): String = "\"${localValue(name).replace("\\", "\\\\").replace("\"", "\\\"")}\""

android {
    namespace = "com.kotlinsun.lumiandroid"
    compileSdk {
        version = release(36) {
            minorApiLevel = 1
        }
    }

    defaultConfig {
        applicationId = "com.kotlinsun.lumiandroid"
        minSdk = 29
        targetSdk = 36
        versionCode = 1
        versionName = "1.0"

        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        manifestPlaceholders["mwdat_application_id"] = localValue("MWDAT_APPLICATION_ID").ifBlank { "0" }
        manifestPlaceholders["mwdat_client_token"] = localValue("MWDAT_CLIENT_TOKEN").ifBlank { "0" }
    }

    buildTypes {
        debug {
            buildConfigField("String", "GEMINI_API_KEY", escapedBuildConfigValue("GEMINI_API_KEY"))
            buildConfigField("String", "KMA_WEATHER_API_KEY", escapedBuildConfigValue("KMA_WEATHER_API_KEY"))
        }
        release {
            optimization {
                enable = false
            }
            buildConfigField("String", "GEMINI_API_KEY", "\"\"")
            buildConfigField("String", "KMA_WEATHER_API_KEY", "\"\"")
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }
    buildFeatures {
        buildConfig = true
        viewBinding = true
    }
}

dependencies {
    implementation(libs.androidx.activity.ktx)
    implementation(libs.androidx.appcompat)
    implementation(libs.androidx.constraintlayout)
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.datastore.preferences)
    implementation(libs.androidx.fragment.ktx)
    implementation(libs.androidx.lifecycle.livedata.ktx)
    implementation(libs.androidx.lifecycle.runtime.ktx)
    implementation(libs.androidx.lifecycle.viewmodel.ktx)
    implementation(libs.androidx.recyclerview)
    implementation(libs.androidx.room.ktx)
    implementation(libs.androidx.room.runtime)
    implementation(libs.kotlinx.coroutines.android)
    implementation(libs.material)
    implementation(libs.mwdat.camera)
    implementation(libs.mwdat.core)
    implementation(libs.mwdat.mockdevice)
    ksp(libs.androidx.room.compiler)
    testImplementation(libs.junit)
    androidTestImplementation(libs.androidx.espresso.core)
    androidTestImplementation(libs.androidx.junit)
}
