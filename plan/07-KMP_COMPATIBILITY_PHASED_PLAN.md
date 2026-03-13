# Pipit KMP Compatibility Upgrade Status

## Completed on 2026-03-13

- Upgraded the Gradle wrapper to `8.13`.
- Upgraded Android Gradle Plugin usage to `8.13.2`.
- Migrated `androidApp` to the Kotlin 2.x Compose compiler plugin path.
- Replaced the shared module legacy `com.android.library` + `androidTarget()` bridge with `com.android.kotlin.multiplatform.library`.
- Preserved iOS framework generation for `iosX64`, `iosArm64`, and `iosSimulatorArm64`.
- Restored successful validation for both `:shared:assemble` and `:androidApp:assembleDebug`.

## Final validation state

- `:shared:compileIosMainKotlinMetadata` passes with Java 17.
- `:shared:assemble` succeeds and still emits `shared.framework` outputs for all current iOS targets.
- `:androidApp:assembleDebug` succeeds on a machine with Android SDK platform 35 available.
- The previous Compose compiler plugin warning is resolved.
- The previous shared `androidTarget()` compatibility warning is resolved.

## Resulting build baseline

- Java runtime for Gradle: `17`
- Gradle wrapper: `8.13`
- AGP: `8.13.2`
- Shared Android plugin: `com.android.kotlin.multiplatform.library`
- Android compileSdk: `35`
- Android targetSdk: `34`

## Remaining non-blocking warnings

- Android source code still has a small set of platform API deprecation warnings in BLE, theme, and USB code.
- Native libraries from SceneView / Filament are packaged without symbol stripping during debug builds.

## Notes

- The temporary SDK-gated legacy Android target bridge has been removed from `shared/build.gradle.kts`.
- README build requirements were updated to match the new post-migration toolchain.