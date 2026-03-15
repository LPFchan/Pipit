# Pipit Agent 7: Onboarding & QR UI Engineer

*Date: 2026-03-11*

*Sequencing Updated: 2026-03-16*

**Status:** Active Brief
**Scope:** Camera Viewfinder, QR Parsing, and Key Setup Flow
**Working Directory:** `Pipit/` (You must execute all work within this specific directory)
**Role:** You are the Mobile UI/UX Engineer. Your task is to build the initial onboarding experience for new users.

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

*How you fit in:* You are building the critical "first launch" camera experience where the user scans a QR code to securely provision their Pipit app.

## 1. Mission & Deliverables
Your goal is to build the immediate "Camera-First" onboarding flow triggered when no AES key exists in the platform's secure keystore.
*   **Deliverable 1:** Full-screen camera viewfinder UI with dark overlay.
*   **Deliverable 2:** QR Payload parser (`immogen://prov?...`) that routes to encrypted or plaintext flows.
*   **Deliverable 3:** The PIN Entry UI and the visual "QR Decryption Particle Animation."
*   **Integration Contract:** 
    *   **App Shell:** You now own replacing the existing onboarding placeholders and wiring real onboarding presentation into the app shell. On Android this means the onboarding route in `androidApp/src/main/java/com/immogen/pipit/ui/PipitApp.kt`. On iOS this means replacing `iosApp/iosApp/UI/OnboardingPlaceholderViewController.swift` and wiring it through `iosApp/iosApp/UI/RootViewController.swift`.
    *   **Crypto:** Do not implement Argon2id yourself. Call the KMP wrapper provided by Agent 2 (e.g., `ImmoCrypto.deriveKey(pin, salt)`).
    *   **Crypto Initialization:** The shared Argon2id implementation is libsodium-backed. Ensure `ImmoCrypto.initialize()` has completed before the first `deriveKey(...)` call. Treat this as a required startup/onboarding precondition, not as optional defensive code.
    *   **BLE Scanning:** For the "Recover Key" flow, do not write raw BLE scanning logic. Subscribe to the foreground scanning hook/Flow provided by Agent 4.
    *   **BLE Management:** Agent 4 has now delivered the low-level BLE management transport. Use that transport for `SLOTS?`, recovery-mode connection, and later `RECOVER`. Do not create a second management transport layer inside onboarding UI code.

### 1.1 Required Work Before Feature Deliverables
Before implementing the camera, QR parsing, or animation deliverables, Agent 7 should complete the following platform integration work in this order:

1.  **Replace the onboarding placeholders with real onboarding containers.**
    *   Android: take ownership of `OnboardingPlaceholderView` routing in `androidApp/src/main/java/com/immogen/pipit/ui/PipitApp.kt`.
    *   iOS: replace `iosApp/iosApp/UI/OnboardingPlaceholderViewController.swift` and wire presentation from `iosApp/iosApp/UI/RootViewController.swift`.
2.  **Add a real startup onboarding gate based on secure key presence.**
    *   Use `KeyStoreManager` to decide whether Pipit should launch into onboarding or the normal shell.
    *   The rule is: if no local slot key exists, show onboarding immediately; otherwise, skip onboarding.
3.  **Implement the smallest recovery milestone before the full QR flow.**
    *   The first working recovery slice is not full `RECOVER` yet.
    *   It is: tap "recover key from lost phone >" -> start Window Open scan -> detect Window Open -> connect with Agent 4's recovery-mode transport -> send `SLOTS?` -> render a slot picker.
    *   Do not block on owner-PIN proof or final key replacement before this read-only recovery path is working.
4.  **Only after the above, build the camera-first QR flow and PIN/decryption UI.**

### 1.2 Recommended Delivery Order
Implement the work in this sequence:

1.  App-shell onboarding routing and placeholder replacement.
2.  Key-presence gate using `KeyStoreManager`.
3.  Recovery read path: Window Open detection plus `SLOTS?` slot picker.
4.  Camera viewfinder UI and QR parsing.
5.  Owner PIN entry and shared-crypto decryption.
6.  QR success animation and completion screens.
7.  Final lost-phone recovery write path using `RECOVER`.

## 2. Technical Context

### 2.1 Step 1: Camera-First QR Scan
```
┌─────────────────────────────┐
│                             │
│  ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓  │
│  ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓  │
│  ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓  │
│  ▓▓▓▓▓┌───────────┐▓▓▓▓▓▓  │
│  ▓▓▓▓▓│           │▓▓▓▓▓▓  │
│  ▓▓▓▓▓│  [camera] │▓▓▓▓▓▓  │
│  ▓▓▓▓▓│           │▓▓▓▓▓▓  │
│  ▓▓▓▓▓└───────────┘▓▓▓▓▓▓  │
│  ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓  │
│  ▓  Scan from Whimbrel    ▓  │
│  ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓  │
│  ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓  │
│                             │
│   recover key from lost phone >│
│                             │
└─────────────────────────────┘
```
*   The app launches directly into the camera only after the startup onboarding gate determines that no local key is present. No welcome screens.
*   **UI:** Darkened overlay (~70% black) with a transparent rounded-rectangle viewfinder in the center. Text: "Scan from Whimbrel" below it. A subtle link "recover key from lost phone >" at the bottom.
*   **Parsing:** Scan for QR codes starting with `immogen://prov?`. Silently ignore non-matching codes.
*   **Routing:**
    *   If QR has `salt` and `ekey` parameters (Owner/Migration): Proceed to Step 2 (PIN Entry).
    *   If QR has a `key` parameter (Guest Plaintext): Skip Step 2. Save the key to the keystore and jump directly to Step 3 (Animation).

### 2.2 Step 2: PIN Entry (Owner Only)
```
┌─────────────────────────────┐
│                             │
│   Enter your 6-digit PIN    │
│                             │
│   This is the PIN you set   │
│   during Guillemot setup.   │
│                             │
│     ┌─┐┌─┐┌─┐┌─┐┌─┐┌─┐    │
│     │ ││ ││ ││ ││ ││ │    │
│     └─┘└─┘└─┘└─┘└─┘└─┘    │
│                             │
│        [ Confirm ]          │
│                             │
└─────────────────────────────┘
```
*   **UI:** "Enter your 6-digit PIN. This is the PIN you set during Guillemot setup." with a 6-box input field.
*   **Logic:** Use the shared KMP API from Agent 2 to derive the AES-128 key and decrypt the `ekey`. For owner/migration QR payloads, call `ImmoCrypto.initialize()` first if startup has not already done so, then call `ImmoCrypto.decryptProvisionedKey(pin, salt, ekey)` or the equivalent shared flow rather than re-implementing AES-CCM or Argon2id in UI code. The UI must handle `InvalidProvisioningPinException` with an inline incorrect-PIN message.
*   **QR crypto contract:** Owner/migration payloads use Whimbrel-compatible values: 16-byte salt, 16-byte encrypted slot key plus 8-byte MIC, and a 13-byte AES-CCM nonce derived from the first 13 bytes of the salt. Parse `salt` and `ekey` as hex before handing them to the shared crypto layer.

### 2.3 Step 3: QR Decryption Animation
On successful PIN entry (or immediately for Guest scans), play a ~1 second animation:
1.  **Dissolve (0–400 ms):** The QR code image breaks apart into a particle field of small squares (matching the QR grid) scattering outward with random velocities.
2.  **Convergence (400–800 ms):** Particles re-converge toward the center, shifting from black/white to the app's accent color.
3.  **Resolve (800–1000 ms):** Particles snap into a key icon with a brief glow/pulse. Fire a `.medium` haptic impact.
*(If the Argon2id KDF runs slow on older hardware, pause the animation at the convergence phase until decryption finishes).*

### 2.4 Step 4 & 5: Completion
**Step 4 (iOS Only):** Location Permission
```
┌─────────────────────────────┐
│                             │
│   Enable proximity unlock?  │
│                             │
│   Pipit can automatically   │
│   unlock your vehicle when  │
│   you walk up to it.        │
│                             │
│   This requires "Always     │
│   Allow" location access    │
│   so the app can detect     │
│   your vehicle in the       │
│   background.               │
│                             │
│   Your location is never    │
│   stored or transmitted.    │
│                             │
│   [ Enable Proximity ]      │
│   [ Skip for Now ]          │
│                             │
└─────────────────────────────┘
```
*   Prompt for "Always Allow" location permission with clear text explaining Proximity Unlock. Offer "Enable Proximity" or "Skip for Now".

**Step 5:** Slot Overview
```
┌─────────────────────────────┐
│                             │
│            ✓                │
│                             │
│   You're all set.           │
│                             │
│   Slot 0   Uguisu       🔑 │
│   Slot 1   Jamie's iPhone ● │
│            OWNER            │
│   Slot 2   — empty —       │
│            GUEST            │
│   Slot 3   — empty —       │
│            GUEST            │
│                             │
│        [ Done ]             │
│                             │
└─────────────────────────────┘
```
*   Show a success screen listing all 4 slots (0–3) with tier labels (`OWNER` / `GUEST`). Highlight the user's slot. "Done" button dismisses onboarding.

### 2.5 "Recover Key from Lost Phone" Link
*   The "recover key from lost phone >" link at the bottom of the camera screen launches a separate, reactive UI flow.
*   **UI Prompt:** Instructs the user to "Press the button three times on your Uguisu fob." and displays a "Scanning..." state. No manual "Connect" button.
*   **Logic:** Pipit's BLE scanner actively listens for the Guillemot peripheral to change its Service UUID to the "Window Open" state.
*   **First implementation milestone:** When detected, Pipit vibrates, automatically initiates a recovery-mode GATT connection through Agent 4's management transport, fetches the `SLOTS?` list, and prompts the user to select their lost slot.
*   **Follow-up implementation:** After the slot-picker flow is working, add owner proof and the final `RECOVER` mutation. If the Owner slot is selected, prompt for the 6-digit PIN or other approved ownership proof, then generate a new key, send the `RECOVER` command, and jump to Step 5 (Done).
