plugins {
    kotlin("multiplatform") version "2.3.0" apply false
    kotlin("android") version "2.3.0" apply false
    kotlin("plugin.compose") version "2.3.0" apply false
    id("com.android.application") version "8.2.2" apply false
    id("com.android.library") version "8.2.2" apply false
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}
