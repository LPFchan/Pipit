# Pipit KMP Compatibility Phased Plan

## Current status

- `androidApp` now uses the Kotlin Compose plugin path required by Kotlin 2.x.
- `shared` keeps iOS framework generation available without requiring an Android SDK.
- The legacy shared Android target remains gated behind SDK detection because the repo is still on AGP `8.2.2`.

## Why the full shared migration is deferred

- The supported Android KMP library plugin (`com.android.kotlin.multiplatform.library`) requires AGP `8.10.0+`.
- This repo currently uses AGP `8.2.2` and Gradle `8.6`, so switching the shared module in this pass would force a larger toolchain upgrade.
- `androidApp` consumes classes from `shared/src/androidMain`, so removing the legacy Android target before the replacement plugin is in place would break Android compilation.
- Preserving current Xcode linkage depends on leaving the existing iOS `binaries.framework` setup unchanged during the migration.

## Phase 1: Safe compatibility step

- Keep the Kotlin 2.x Compose compiler on the plugin path in `androidApp`.
- Make the shared legacy Android target explicit and SDK-aware so iOS-only validation still works on machines without Android SDK configuration.
- Acceptance criteria:
  - `:shared:compileIosMainKotlinMetadata` succeeds with Java 17.
  - `:shared:assemble` still produces the iOS framework artifacts.
  - The Compose compiler plugin warning no longer appears during Gradle configuration.

## Phase 2: Toolchain uplift

- Upgrade AGP to at least `8.10.0`.
- Upgrade the Gradle wrapper to the version required by that AGP release.
- Re-run `:shared:assemble` and `:androidApp:assembleDebug` on a machine with a configured Android SDK.
- Acceptance criteria:
  - Both shared and Android app builds pass on the upgraded toolchain.
  - No new Kotlin, AGP, or Compose plugin compatibility warnings are introduced.

## Phase 3: Shared Android plugin migration

- Replace the shared module legacy `com.android.library` + `androidTarget()` path with `com.android.kotlin.multiplatform.library`.
- Configure the Android target inside the Kotlin DSL using the Android KMP plugin block supported by the selected AGP version.
- Keep Android-specific dependencies scoped under `androidMain`.
- Preserve the existing iOS target list: `iosX64`, `iosArm64`, `iosSimulatorArm64`.
- Acceptance criteria:
  - Shared Android compilation works without `androidTarget()`.
  - iOS framework link tasks still succeed for all current Apple targets.
  - Xcode continues to resolve and link the generated `shared.framework` outputs.

## Phase 4: Cleanup

- Remove the legacy shared Android gate and any compatibility comments that only exist for the interim path.
- Document the final Android SDK and Java requirements in the project README if they changed during the toolchain uplift.
- Acceptance criteria:
  - No deprecated Android target configuration remains in `shared/build.gradle.kts`.
  - The repository build instructions match the final Gradle configuration.