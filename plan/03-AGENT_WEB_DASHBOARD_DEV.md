# Pipit Agent 3: Web Dashboard Dev

*Date: 2026-03-11*

**Status:** Active Brief
**Scope:** Whimbrel Dashboard BLE Management & QR Generation
**Working Directory:** `Whimbrel/` (You must execute all work within this specific directory)
**Role:** You are the Web Developer managing the `Whimbrel` web dashboard, built with vanilla JS, Web Serial, and Web Bluetooth.

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

*How you fit in:* You are building the Web Dashboard provisioning flow that generates the secure QR codes the Pipit app will scan during user onboarding.

## 1. Mission & Deliverables
Your goal is to update the Whimbrel dashboard to support the new Pipit multi-slot provisioning system, Web Bluetooth key management, and secure Argon2id encrypted QR generation.
*   **Deliverable 1:** Updated `serial.js` / `api.js` to support new commands (`RENAME`, `PROV` with names, plaintext `SETPIN`).
*   **Deliverable 2:** New Web Bluetooth manager to connect to the GATT service, authenticate via SMP PIN, and handle `SLOTS?` JSON responses.
*   **Deliverable 3:** Integration of an Argon2id WebAssembly library to derive the AES-128 key from the PIN and generate the encrypted provisioning QR codes.

## 2. Technical Context

### 2.1 GATT Characteristics & MTU
*   **Management Command Characteristic:** `438C5641-3825-40BE-80A8-97BC261E0EE9` (Write, Authenticated Link). Triggers native OS PIN prompt.
*   **Management Response Characteristic:** `DA43E428-803C-401B-9915-4C1529F453B1` (Notify).
*   MTU negotiation to 247 bytes is handled automatically by Web Bluetooth.

### 2.2 Serial & Management Protocol Updates
*   The API wrappers must append device names to the `PROV` command (`PROV:<slot>:<key>:<ctr>:[name]`).
*   Implement `RENAME:<slot>:<name>`.
*   Send `SETPIN:<6digits>` as plaintext digits over USB serial (not hashed).
*   Parse the JSON response from `SLOTS?` (e.g., `{"status":"ok","slots":[{"id":0,"used":true,"counter":4821,"name":"Uguisu"}, ...]}`).

### 2.3 Key Provisioning & Argon2id QR Generation (Owner - Slot 1)
When the user adds a phone (Slot 1) via Whimbrel:
1.  Derive an AES-128 key from the 6-digit PIN using **Argon2id** (parameters: `m=262144` (256 MB), `t=3`, `p=1`, with a random 16-byte salt). *Use a WebAssembly port like `argon2-browser`.*
2.  Encrypt the newly generated 16-byte slot key using AES-CCM with the derived key.
3.  The QR contains: `immogen://prov?slot=1&salt=<hex>&ekey=<encrypted_key_hex>&ctr=0&name=iPhone`
4.  The PIN is **never** included in the QR code.

### 2.4 UI Updates
*   Add text fields for "Device Name" during the "Add Phone" wizard.
*   Add an "Edit Name" button next to active slots in the dashboard view, triggering the `RENAME` command.

---

## 3. Session Progress & Adjustments (Phase 1 Complete)
*Date: 2026-03-11*

*   **USB Provisioning Refactor**: Removed the legacy single-key generation logic in favor of a clean multi-slot flow. Flash Receiver provisions Slot 0 (Uguisu) locally. Flash Key Fob mirrors this to the physical hardware. Crucially, the "Phone Key" setup has been extracted out of the USB flow and is now purely wireless to ensure plug-and-play simplicity for fob-only users.
*   **Web Bluetooth Dashboard (`dashboard.js` & `ble.js`)**: Built a fully responsive, animated modal overlay (accessed via a footer button) that connects to Guillemot's Proximity Service. Implemented `SLOTS?` fetching, UI rendering, and `RENAME` commands over the authenticated Management Characteristic.
*   **Argon2id & AES-CCM Implementation (`ccm.js`)**: Included `argon2-browser` and `aes-js` to correctly derive the AES-128 key from the 6-digit PIN and encrypt the Phone Slot payload into the final `immogen://prov...` QR string.
*   **Fob-Authorized Provisioning Window**: Adjusted the architecture so that an `Unlock` payload from Uguisu triggers a 30-second window during which Guillemot allows `SETPIN` and `PROV:1` over BLE. The dashboard's tutorial flow perfectly models this: instructing the user to press the fob before establishing the connection.
*   **Demo Mode Sync**: Brought all these changes over to the `demo` branch, mocking the BLE slot responses, connection delays, and QR derivations flawlessly.

## 4. UI/UX Bug Fixes (Phase 1.1 Complete)
*Date: 2026-03-12*
*   **Dashboard Navigation & UI**: Unified the dashboard overlay navigation, corrected button text labels, replaced "Connect" buttons with "Yes"/"Skip for now" flows, and introduced a "No Phone Key" fallback section with proper back-navigation.
*   **PIN Entry Bug**: Fixed the UI state issue where entering digits would trigger multiple circle indicators to light up; implemented a guard against multiple submissions on key-down.
*   **BLE Handling**: Corrected the demo mode logic to completely skip BLE connection attempts if the user skips key setup, and resolved the `window.Whimbrel.abortableDelay` error by using a standard `Promise`-based delay.
*   **Device Slots Visibility**: Resolved an issue where device slots were invisible in the "Manage Keys" pop-up by explicitly styling the `slots-container` and ensuring correct DOM visibility; updated slots to be interactable.

## 5. System Architect Evaluation
*   **Date:** 2026-03-12
*   **Grade: A**
*   **Evaluation:** Agent 3 successfully handled the web-based BLE provisioning interface. They implemented `dashboard.js` to reliably connect to `Guillemot` via `navigator.bluetooth`, seamlessly triggering the OS-level SMP PIN prompt natively. They successfully query `SLOTS?`, parse the JSON response, render the active slots, and dispatch `RENAME` commands back to the peripheral. Finally, they successfully integrated the `argon2-browser` WebAssembly library to derive the AES-128 key from the 6-digit PIN and generate the encrypted `immogen://prov...` QR codes for the mobile app to scan.
