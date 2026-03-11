# Pipit Agent 7: Onboarding & QR UI Engineer

*Date: 2026-03-11*

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

## 2. Technical Context

### 2.1 Step 1: Camera-First QR Scan
*   The app launches directly into the camera. No welcome screens.
*   **UI:** Darkened overlay (~70% black) with a transparent rounded-rectangle viewfinder in the center. Text: "Scan from Whimbrel" below it. A subtle link "recover key from lost phone >" at the bottom.
*   **Parsing:** Scan for QR codes starting with `immogen://prov?`. Silently ignore non-matching codes.
*   **Routing:**
    *   If QR has `salt` and `ekey` parameters (Owner/Migration): Proceed to Step 2 (PIN Entry).
    *   If QR has a `key` parameter (Guest Plaintext): Skip Step 2. Save the key to the keystore and jump directly to Step 3 (Animation).

### 2.2 Step 2: PIN Entry (Owner Only)
*   **UI:** "Enter your 6-digit PIN. This is the PIN you set during Guillemot setup." with a 6-box input field.
*   **Logic:** Use Argon2id (parameters from QR salt) to derive the AES-128 key and decrypt the `ekey`. The UI must handle incorrect PINs with an inline error message.

### 2.3 Step 3: QR Decryption Animation
On successful PIN entry (or immediately for Guest scans), play a ~1 second animation:
1.  **Dissolve (0–400 ms):** The QR code image breaks apart into a particle field of small squares (matching the QR grid) scattering outward with random velocities.
2.  **Convergence (400–800 ms):** Particles re-converge toward the center, shifting from black/white to the app's accent color.
3.  **Resolve (800–1000 ms):** Particles snap into a key icon with a brief glow/pulse. Fire a `.medium` haptic impact.
*(If the Argon2id KDF runs slow on older hardware, pause the animation at the convergence phase until decryption finishes).*

### 2.4 Step 4 & 5: Completion
*   **Step 4 (iOS Only):** Prompt for "Always Allow" location permission with clear text explaining Proximity Unlock. Offer "Enable Proximity" or "Skip for Now".
*   **Step 5 (Slot Overview):** Show a success screen listing all 4 slots (0–3) with tier labels (`OWNER` / `GUEST`). Highlight the user's slot. "Done" button dismisses onboarding.