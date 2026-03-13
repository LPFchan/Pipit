# Pipit iOS App

**UIKit** app (per PIPIT_MASTER_ARCHITECTURE). Placeholder 3D fob; RealityKit can replace `FobPlaceholderView` when the final asset is ready. Agent 6 delivers the app shell; Agents 7 and 8 fill Onboarding and Settings.

## Setup

- Open in Xcode as part of a Kotlin Multiplatform project that includes the `shared` framework, or create a new iOS App target and add the `shared` framework (from the KMP build).
- Add all files under `iosApp/` and `iosApp/UI/` to the target.
- App entry is **UIKit**: `@main` in `AppDelegate.swift`; no storyboard (window created in code).
- Link the KMP `shared` framework and **Combine** so `IosBleProximityService`, `ConnectionState`, and `RootViewController` observation work.

## Placeholder 3D

The home screen uses a 2D placeholder (rounded rect) for the Uguisu fob. To use the real 3D asset:

1. Convert `Pipit/assets/uguisu_placeholder.glb` to `.usdz` (e.g. Reality Converter or `xcrun usdzconvert`).
2. Add the `.usdz` to the app bundle and load it in a `RealityKit` `Entity` or `ModelEntity` in place of `FobPlaceholderView`.

## BLE

`IosBleProximityService` is the BLE layer. `sendUnlockCommand()` and `sendLockCommand()` are stubbed for manual fob actions; wire them to connect and send the 14-byte payload when the UI triggers tap/long-press.
