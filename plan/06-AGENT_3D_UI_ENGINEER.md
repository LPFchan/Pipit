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