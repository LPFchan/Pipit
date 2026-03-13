import org.jetbrains.kotlin.gradle.tasks.KotlinCompilationTask

plugins {
    kotlin("multiplatform") version "2.3.0"
    // Gradle's Kotlin/Multiplatform may expect publication support; add maven-publish
    // to ensure internal publication APIs are available when configuring targets.
    id("maven-publish")
}

kotlin {
    // Make the Android target optional so we can build iOS frameworks on machines
    // that don't have the Android Gradle plugin applied (CI / mac previews).
    val hasAndroidPlugin = project.plugins.findPlugin("com.android.library") != null || project.plugins.findPlugin("com.android.application") != null
    if (hasAndroidPlugin) {
        androidTarget()
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
        if (hasAndroidPlugin) {
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
