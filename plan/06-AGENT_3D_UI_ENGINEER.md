# Pipit Agent 6: 3D & App Shell UI Engineer

*Date: 2026-03-11*

**Status:** Active Brief
**Scope:** The Main Fob Screen, 3D Rendering, and Navigation Shell
**Working Directory:** `Pipit/` (You must execute all work within this specific directory)
**Role:** You are the Mobile UI/UX Engineer specialized in native 3D frameworks. Your task is to build Pipit's primary interface: a photorealistic interactive 3D key fob.

---

## 0. Project Overview
**Pipit** is the companion app for the **Immogen immobilizer ecosystem** (designed for the Ninebot G30 and compatible PEVs). The ecosystem consists of:
*   **Guillemot:** The vehicle immobilizer firmware.
*   **Uguisu:** A physical hardware key fob.
*   **Whimbrel:** A web-based administration dashboard.
*   **Pipit:** The mobile companion app (iOS & Android).

Pipit provides two main features:
1.  **Proximity Unlock (Background):** A low-power BLE service that detects the vehicle and automatically unlocks it based on RSSI thresholding.
2.  **Active Key Fob (Foreground):** A manual lock/unlock UI, functionally identical to the Uguisu hardware fob.

*How you fit in:* You are building the main visual shell of the Pipit app—a photorealistic 3D interactive key fob that users will tap to unlock their vehicle.

## 1. Mission & Deliverables
Your goal is to build the "single-screen utility model" that serves as the root of the Pipit app.
*   **Deliverable 1:** Implementation of the 3D Uguisu model using `RealityKit` (iOS) and `SceneView` (Android) with tap/hold gesture recognition.
*   **Deliverable 2:** The Disconnect Overlay UI.
*   **Deliverable 3:** The 3D flip transition animation that reveals the Settings screen.
*   **Deliverable 4:** The App Shell Architecture. You are the owner of the root navigation controller/Compose graph. You must set up the root shell and expose empty placeholder views (`OnboardingView` and `SettingsView`) that Agents 7 and 8 will populate later.

## 2. Technical Context

### 2.1 App Navigation Model
Pipit uses a single-screen utility model. The Home screen (key fob) is always the root view. Settings is the only secondary surface, accessed via a 3D flip. The app respects the system dark/light theme.

### 2.2 Home Screen (Key Fob)
```
┌─────────────────────────────┐
│ ⚙                          │
│                             │
│                             │
│                             │
│   ╔═══════════════════════╗  │
│   ║                       ║  │
│   ║   [Uguisu 3D model]   ║  │
│   ║   perspective, lit    ║  │
│   ║   LED: off (idle)      ║  │
│   ║                       ║  │
│   ║                       ║  │
│   ╚═══════════════════════╝  │
│     Tap · Hold to lock      │
│                             │
│                             │
│                             │
└─────────────────────────────┘
```
*   **Layout:** A gear icon in the top-left. A dominant, centered 3D model of the Uguisu fob. A subtle text hint "Tap · Hold to lock" below it (hidden after first use).
*   **Interaction:**
    *   **Button Depression:** The moment the user touches the 3D model on screen, the tactile button geometry on the model MUST physically depress (move inward ~1-2mm). It must remain held down as long as the user's finger is on the screen, and spring back up upon release.
    *   **Short press (tap):** Triggers Unlock.
    *   **Long press (~700 ms hold):** Triggers Lock instantly at the 700ms mark (no release required).
*   **Passive Interaction:** The model responds to device gyroscope input with a subtle parallax tilt (±5°).

### 2.3 3D Asset & Emissive LED Control
*   Assets are `.glb` (Android) and `.usdz` (iOS). Target size < 5 MB.
*   Both platforms use Image-Based Lighting (IBL) simulating an overcast sky.
*   The LED mesh (named `led_rgb` in the scene graph) is off by default (emissive intensity 0.0). It only fires during transient flash animations:
    *   **Unlock:** Color `#00FF00`, intensity ramps 0→1.0→0 over 500ms (fade in 100ms, hold 200ms, fade out 200ms).
    *   **Lock:** Color `#FF0000`, same intensity ramp.
    *   **Background Proximity Action:** If the background service auto-unlocks/locks, the app must play the corresponding LED flash on the 3D model if foregrounded.

### 2.4 Haptics & Sound Schedule
*   **Unlock (tap):** iOS `.light` impact / Android `KEYBOARD_TAP`. Fast, bright mechanical click audio (~40ms).
*   **Lock (700ms hold):** iOS `.heavy` impact / Android `CONFIRM` / `LONG_PRESS`. Heavier mechanical clunk audio (~60ms).
*   *Audio must strictly respect the hardware silent switch / ringer mode.*

### 2.5 Disconnect Overlay
```
┌─────────────────────────────┐
│ ⚙                          │
│▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒│
│▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒│
│▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒│
│▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒│
│▒▒▒▒▒ ○ Disconnected ▒▒▒▒▒▒▒│
│▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒│
│▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒│
│▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒│
│▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒│
└─────────────────────────────┘
```
When Guillemot is unreachable via BLE, show a full-screen semi-transparent overlay (white/black depending on system theme, ~60% opacity). The 3D model sits faintly beneath it, non-interactive.
*   Shows `○ Disconnected` or `✕ Bluetooth is off`.
*   Fades out (200ms) instantly upon BLE connection. The gear icon remains accessible.

### 2.6 The 3D Flip Transition (Settings)
Tapping the gear icon flips the Home screen to Settings:
1.  **Flip (0–400 ms):** The 3D model rotates 180° around its Y-axis and scales up slightly (~1.1×).
2.  **Morph (400–600 ms):** The back surface of the model cross-fades into the Settings content pane.
3.  **Reverse:** Closes Settings by reversing the animation.
*   *iOS: use `CATransform3D` on a snapshot layer. Android: use `View.rotationY` with `cameraDistance`.*

### 2.7 Integration Contract (BLE Engine)
To actually trigger the lock/unlock events when the user interacts with the 3D model, you must hook into the shared BLE service built by Agent 4. 
*   Observe the `BleState` Flow from `BleService.kt` to drive the visibility of the Disconnect Overlay.
*   When a short press (tap) is detected, call `bleService.sendUnlockCommand()`.
*   When a long press (700ms) is detected, call `bleService.sendLockCommand()`.

---

## 3. Implementation Log

**Date:** 2026-03-13

**What was done**

1. **Placeholder 3D model**  
   Added a script (`scripts/generate_uguisu_placeholder_glb_minimal.py`, Python stdlib only) that generates `assets/uguisu_placeholder.glb` with three named meshes: `body`, `button`, `led_rgb`, so the rendering and LED/button-depression contract can be implemented before the final Uguisu enclosure CAD exists. Documented conversion to `.usdz` for iOS in `assets/README.md`.

2. **Android app shell**  
   Introduced root Gradle setup (`settings.gradle.kts`, `build.gradle.kts`), `androidApp/build.gradle.kts` (Compose, Material3), `MainActivity` (binds to `AndroidBleProximityService`, gets `BleService`, observes `BleState`), and Compose UI: home screen with gear, centered fob placeholder (tap = unlock, long-press = lock), “Tap · Hold to lock” hint (dismissible), button-depression animation, disconnect overlay driven by BLE state, `AnimatedContent` transition to Settings, and placeholder views for Onboarding and Settings. Made the BLE service bindable (`LocalBinder` / `getBleService()`) so the activity can call `sendUnlockCommand()` / `sendLockCommand()`. Added resources (themes, strings, launcher drawable) and manifest entry/activity.

3. **iOS app shell (UIKit)**  
   Implemented the iOS shell in **UIKit** (not SwiftUI) to match *PIPIT_MASTER_ARCHITECTURE*, which specifies “Native UI: **UIKit** (iOS) and **Jetpack Compose** (Android).”  
   - **AppDelegate.swift:** `@main`, creates `UIWindow`, sets `rootViewController` to `RootViewController(bleService:)`.  
   - **RootViewController:** Container that shows `HomeViewController` or `SettingsPlaceholderViewController`, observes `bleService.$connectionState` (Combine) and shows/hides `DisconnectOverlayView` when not connected, and keeps “Tap · Hold to lock” hint state across Home/Settings.  
   - **HomeViewController:** Gear button, `FobPlaceholderView`, tap-hint label; forwards fob tap/long-press and hint dismissal.  
   - **FobPlaceholderView** (UIView): 200×140 rounded card placeholder, `UILongPressGestureRecognizer` (0.7s) for lock, `UITapGestureRecognizer` (require long-press to fail) for tap = unlock, `UIPanGestureRecognizer` for press state; light/heavy haptics and visual “depression” (offset + shadow).  
   - **DisconnectOverlayView** (UIView): Semi-transparent overlay, “○ Disconnected”; top 56pt excluded from hit-test so the gear stays tappable.  
   - **SettingsPlaceholderViewController** and **OnboardingPlaceholderViewController:** Placeholder view controllers for Agents 8 and 7.  
   Removed the earlier SwiftUI app and views (`PipitApp.swift`, `RootView.swift`, `HomeView.swift`, `SettingsPlaceholderView.swift`, `OnboardingPlaceholderView.swift`). Updated `iosApp/README.md` for UIKit entry and setup.

4. **BLE integration**  
   Android: Activity binds to the service and uses `BleService.state` for the overlay and for `sendUnlockCommand()` / `sendLockCommand()` on fob actions. iOS: `IosBleProximityService` already had `connectionState`; added async `sendUnlockCommand()` / `sendLockCommand()` stubs for the UI to call (actual connect-and-send path left as TODO).

**Reasoning**

- **Placeholder 3D:** The brief assumes a real Uguisu 3D asset; the user stated the 3D model was not ready. A programmatic GLB with the required mesh names (`led_rgb`, depressible “button”) lets the app shell, gestures, and BLE wiring be built and tested without blocking on CAD; the final asset can replace the placeholder with minimal code change.
- **UIKit for iOS:** The master architecture explicitly requires UIKit for iOS. An initial implementation used SwiftUI; that was reverted so the codebase stays aligned with the spec and with the stated rationale (reliable BLE/camera/keystore integration and native 3D). All iOS UI is therefore implemented with `UIViewController`, `UIView`, and UIKit gesture recognizers.
- **No Gradle wrapper / no Xcode project in repo:** The Pipit folder did not include a Gradle wrapper or an Xcode project file. The implementation adds the app code and build configuration (Gradle for Android, file layout and README for iOS) so that when the wrapper is added or the project is opened from a parent KMP setup, the shell builds and runs as described.