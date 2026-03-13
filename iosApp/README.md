# Pipit iOS App

**UIKit** app (per PIPIT_MASTER_ARCHITECTURE). Placeholder 3D fob; RealityKit can replace `FobPlaceholderView` when the final asset is ready. Agent 6 delivers the app shell; Agents 7 and 8 fill Onboarding and Settings.

## Setup

- Open in Xcode as part of a Kotlin Multiplatform project that includes the `shared` framework, or create a new iOS App target and add the `shared` framework (from the KMP build).
- Add all files under `iosApp/` and `iosApp/UI/` to the target.
- App entry is **UIKit**: `@main` in `AppDelegate.swift`; no storyboard (window created in code).
- Link the KMP `shared` framework and **Combine** so `IosBleProximityService`, `ConnectionState`, and `RootViewController` observation work.

## 3D fob (RealityKit)

The home screen uses **FobRealityView**, which loads `uguisu_placeholder.usdz` from the app bundle when present (RealityKit), with tap/long-press and button-depression animation. If the USDZ is not in the bundle, it falls back to **FobPlaceholderView** (2D).

1. Convert `Pipit/assets/uguisu_placeholder.glb` to `.usdz` (Reality Converter or `xcrun usdzconvert`).
2. Add `uguisu_placeholder.usdz` to the iOS target’s **Copy Bundle Resources**.
3. The app will load it via `Entity.loadModel(contentsOf:)` and animate the `button` entity for depression.

## BLE

`IosBleProximityService` is the BLE layer. `sendUnlockCommand()` and `sendLockCommand()` are stubbed for manual fob actions; wire them to connect and send the 14-byte payload when the UI triggers tap/long-press.
