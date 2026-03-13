import org.jetbrains.kotlin.gradle.dsl.JvmTarget
import org.jetbrains.kotlin.gradle.tasks.KotlinCompilationTask

plugins {
    kotlin("multiplatform") version "2.3.0"
    id("com.android.kotlin.multiplatform.library")
    // Gradle's Kotlin/Multiplatform may expect publication support; add maven-publish
    // to ensure internal publication APIs are available when configuring targets.
    id("maven-publish")
}

kotlin {
    android {
        namespace = "com.immogen.pipit.shared"
        compileSdk = 35
        minSdk = 26
        withJava()

        compilerOptions {
            jvmTarget.set(JvmTarget.JVM_17)
        }
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
        val androidMain by getting {
            dependencies {
                implementation("androidx.security:security-crypto:1.1.0-alpha06")
            }
        }
    }
}

tasks.withType<KotlinCompilationTask<*>>().configureEach {
    compilerOptions.freeCompilerArgs.add("-Xexpect-actual-classes")
}
