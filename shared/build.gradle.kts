import com.android.build.gradle.LibraryExtension
import org.gradle.api.JavaVersion
import org.jetbrains.kotlin.gradle.dsl.KotlinMultiplatformExtension
import org.jetbrains.kotlin.gradle.tasks.KotlinCompilationTask

plugins {
    kotlin("multiplatform") version "2.3.0"
    // Gradle's Kotlin/Multiplatform may expect publication support; add maven-publish
    // to ensure internal publication APIs are available when configuring targets.
    id("maven-publish")
}

val hasConfiguredAndroidSdk =
    rootProject.file("local.properties").isFile ||
        providers.environmentVariable("ANDROID_HOME").isPresent ||
        providers.environmentVariable("ANDROID_SDK_ROOT").isPresent

// Keep the legacy Android target behind an SDK-aware gate until the repo can
// move to the Android KMP library plugin, which requires a newer AGP baseline.
val enableLegacyAndroidTarget = hasConfiguredAndroidSdk

if (enableLegacyAndroidTarget) {
    apply(plugin = "com.android.library")

    extensions.configure<LibraryExtension> {
        namespace = "com.immogen.pipit.shared"
        compileSdk = 34

        defaultConfig {
            minSdk = 26
        }

        compileOptions {
            sourceCompatibility = JavaVersion.VERSION_17
            targetCompatibility = JavaVersion.VERSION_17
        }
    }
}

private fun KotlinMultiplatformExtension.configureLegacyAndroidTargetCompat() {
    val androidTargetMethod = javaClass.methods.firstOrNull {
        it.name == "androidTarget" && it.parameterCount == 0
    } ?: error(
        "Legacy androidTarget() support is unavailable. Continue with the Android KMP library plugin migration plan."
    )

    androidTargetMethod.invoke(this)
}

kotlin {
    if (enableLegacyAndroidTarget) {
        configureLegacyAndroidTargetCompat()
    }

    val iosX64Target = iosX64()
    val iosArm64Target = iosArm64()
    val iosSimulatorArm64Target = iosSimulatorArm64()

    listOf(iosX64Target, iosArm64Target, iosSimulatorArm64Target).forEach { target ->
        target.binaries.framework {
            baseName = "shared"
            isStatic = true
        }
    }

    sourceSets {
        val commonMain by getting {
            dependencies {
                // Add common dependencies here
                implementation("org.jetbrains.kotlinx:kotlinx-coroutines-core:1.7.3")
            }
        }
        val commonTest by getting {
            dependencies {
                implementation(kotlin("test"))
            }
        }
        if (enableLegacyAndroidTarget) {
            val androidMain by getting {
                dependencies {
                    implementation("androidx.security:security-crypto:1.1.0-alpha06")
                }
            }
        }
    }
}

tasks.withType<KotlinCompilationTask<*>>().configureEach {
    compilerOptions.freeCompilerArgs.add("-Xexpect-actual-classes")
}
