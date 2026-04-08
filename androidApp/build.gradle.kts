plugins {
    id("com.android.application")
    kotlin("android")
    kotlin("plugin.compose")
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

android {
    namespace = "com.immogen.pipit"
    compileSdk = 35
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    defaultConfig {
        applicationId = "com.immogen.pipit"
        minSdk = 26
        targetSdk = 34
        versionCode = 1
        versionName = "1.0"
    }
    buildFeatures {
        buildConfig = true
        compose = true
    }
    buildTypes {
        getByName("release") {
            isMinifyEnabled = false
        }
    }
    // Copy Three.js + addons from the iOS resource bundle at build time so
    // viewer.html can load them via the pipit-app-local scheme interceptor.
    // We isolate them in a generated dir to avoid duplicate-file conflicts
    // with the shared ../assets directory.
    val threeJsAssets = layout.buildDirectory.dir("three-js-assets")
    val copyThreeJs by tasks.registering(Copy::class) {
        from("../iosApp/iosApp/Resources") {
            include("three.module.js", "three.core.js", "three-addons/**")
        }
        into(threeJsAssets)
    }
    tasks.named("preBuild") { dependsOn(copyThreeJs) }

    sourceSets["main"].assets.srcDirs("src/main/assets", "../assets", threeJsAssets)
}

dependencies {
    implementation(project(":shared"))
    implementation("androidx.activity:activity-compose:1.8.2")
    implementation("androidx.camera:camera-camera2:1.3.4")
    implementation("androidx.camera:camera-core:1.3.4")
    implementation("androidx.camera:camera-lifecycle:1.3.4")
    implementation("androidx.camera:camera-view:1.3.4")
    implementation(platform("androidx.compose:compose-bom:2024.02.00"))
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.ui:ui-graphics")
    implementation("androidx.compose.ui:ui-tooling-preview")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.material:material-icons-extended")
    implementation("androidx.lifecycle:lifecycle-runtime-compose:2.7.0")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.7.0")
    implementation("com.google.mlkit:barcode-scanning:17.2.0")
    implementation("com.google.zxing:core:3.5.3")
    implementation("com.github.mik3y:usb-serial-for-android:3.9.0")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.7.3")
    implementation("io.github.sceneview:sceneview:2.3.3")
    implementation("me.jahnen.libaums:core:0.10.0")
}
