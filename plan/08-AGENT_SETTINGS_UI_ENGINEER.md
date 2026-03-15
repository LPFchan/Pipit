# Pipit Agent 8: Settings & Key Management UI Engineer

*Date: 2026-03-11*

*Sequencing Updated: 2026-03-16*

**Status:** Active Brief
**Scope:** Inline Slot Management, Proximity Controls, and Key Workflows
**Working Directory:** `Pipit/` (You must execute all work within this specific directory)
**Role:** You are the Mobile UI/UX Engineer. Your task is to build the Settings interface and the complex BLE management dialogue flows.

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

*How you fit in:* You are building the inline settings and complex administrative dialogue flows where users manage their keys, guest access, and proximity preferences.

## 1. Mission & Deliverables
Your goal is to build the Settings view (which the 3D screen flips into) and all the administrative flows branching off it.
*   **Deliverable 1:** The Settings UI containing Proximity sliders and Inline Key Slots.
*   **Deliverable 2:** The "Provision Guest Phone" Flow (QR generation).
*   **Deliverable 3:** The "Replace Flow" (Revocation + Provisioning).
*   **Deliverable 4:** The "Migration Flow" (Transfer to new phone).
*   **Integration Contract:**
    *   **App Shell:** You now own replacing the existing settings placeholders and wiring real Settings presentation into the app shell. On Android this means replacing `SettingsPlaceholderView` in `androidApp/src/main/java/com/immogen/pipit/ui/PipitApp.kt`. On iOS this means replacing `iosApp/iosApp/UI/SettingsPlaceholderViewController.swift` and keeping it wired through `iosApp/iosApp/UI/RootViewController.swift`.
    *   **Proximity Preferences:** You must save slider/toggle values using the exact keys: `pref_proximity_enabled` (Bool), `pref_unlock_rssi` (Int), `pref_lock_rssi` (Int). Agent 4 will read these.
    *   **USB Flashing (Android):** Hook up your UI to the `StateFlow<UsbState>` or ViewModels provided by Agent 5. Do not write raw USB logic.
    *   **BLE Management:** Agent 4 has now delivered the mobile BLE management transport. Use that transport directly for `SLOTS?`, `IDENTIFY`, `PROV`, `RENAME`, `REVOKE`, and `RECOVER`. Do not add a second BLE admin transport in UI code.

### 1.1 Required Work Before Administrative Flows
Before implementing QR generation, replacement, or migration workflows, Agent 8 should complete the following platform integration work in this order:

1.  **Replace the settings placeholders with real settings containers.**
    *   Android: take ownership of the settings route in `androidApp/src/main/java/com/immogen/pipit/ui/PipitApp.kt`.
    *   iOS: replace `iosApp/iosApp/UI/SettingsPlaceholderViewController.swift` while preserving the existing root navigation pattern in `iosApp/iosApp/UI/RootViewController.swift`.
2.  **Implement a read-only BLE-backed slot list first.**
    *   The first working settings milestone is not provisioning or deletion.
    *   It is: open Settings -> connect through Agent 4's standard management transport -> send `SLOTS?` -> render the four-slot list -> show loading, error, and retry states -> disconnect cleanly when Settings is dismissed.
3.  **Wire proximity controls to real persisted settings.**
    *   The toggle and sliders must read and write the exact keys consumed by Agent 4.
    *   Enforce the 10 dBm hysteresis rule in the UI.
4.  **Only after the read-only slot list and proximity controls are stable, add mutating key-management workflows.**

### 1.2 Recommended Delivery Order
Implement the work in this sequence:

1.  App-shell settings routing and placeholder replacement.
2.  Read-only slot listing via `SLOTS?`.
3.  Real proximity preference controls with hysteresis enforcement.
4.  Slot actions: `RENAME` and `IDENTIFY`.
5.  Guest provisioning flow using `PROV` plus QR generation.
6.  Replace flow using `REVOKE` plus `PROV`.
7.  Migration flow and local key deletion after confirmation.
8.  Android-only USB actions after the core BLE settings experience is working.

## 2. Technical Context

### 2.1 Settings UI Layout
Settings is presented as a scrollable sheet containing sections: PROXIMITY, KEYS, DEVICE, and ABOUT. The UI renders differently based on the user's tier (Slot 1 = Owner, Slot 2/3 = Guest).

**Owner Settings (Slot 1)**
```
┌─────────────────────────────┐
│  Settings                 ✕ │
│─────────────────────────────│
│                             │
│  PROXIMITY                  │
│  ┌─────────────────────────┐│
│  │ Background Unlock  [ON] ││
│  │─────────────────────────││
│  │ Unlock Distance   ━━●━━ ││
│  │ (~2m / -65 dBm)        ││
│  │─────────────────────────││
│  │ Lock Distance     ━●━━━ ││
│  │ (~5m / -75 dBm)        ││
│  └─────────────────────────┘│
│                             │
│  KEYS                       │
│  ┌─────────────────────────┐│
│  │ Slot 0  Uguisu     🔑 ⋮││
│  │─────────────────────────││
│  │ Slot 1  Owner's iPhone  ││
│  │         OWNER           ││
│  │─────────────────────────││
│  │ Slot 2  Guest 1        ⋮││
│  │         GUEST           ││
│  │─────────────────────────││
│  │ Slot 3       ⊕          ││
│  │         GUEST           ││
│  └─────────────────────────┘│
│                             │
│  DEVICE                     │
│  ┌─────────────────────────┐│
│  │ Transfer to New Phone ▶ ││
│  │─────────────────────────││
│  │ Change PIN (USB)      ▶ ││
│  │─────────────────────────││
│  │ Flash Firmware (USB)  ▶ ││
│  └─────────────────────────┘│
│                             │
│  ABOUT                      │
│  ┌─────────────────────────┐│
│  │ Version            1.0  ││
│  └─────────────────────────┘│
│                             │
└─────────────────────────────┘
```

**Guest Settings (Slot 2–3)**
```
┌─────────────────────────────┐
│  Settings                 ✕ │
│─────────────────────────────│
│                             │
│  PROXIMITY                  │
│  ┌─────────────────────────┐│
│  │ Background Unlock  [ON] ││
│  │─────────────────────────││
│  │ Unlock Distance   ━━●━━ ││
│  │ (~2m / -65 dBm)        ││
│  │─────────────────────────││
│  │ Lock Distance     ━●━━━ ││
│  │ (~5m / -75 dBm)        ││
│  └─────────────────────────┘│
│                             │
│  YOUR KEY                   │
│  ┌─────────────────────────┐│
│  │ Slot 2 · Guest 1       ││
│  │ Transfer to New Phone ▶ ││
│  └─────────────────────────┘│
│                             │
│  ABOUT                      │
│  ┌─────────────────────────┐│
│  │ Version            1.0  ││
│  └─────────────────────────┘│
│                             │
└─────────────────────────────┘
```

### 2.2 Proximity Controls
*   Toggle: "Background Unlock".
*   Slider 1: Unlock Distance (-50 to -85 dBm, default -65).
*   Slider 2: Lock Distance (-60 to -95 dBm, default -75).
*   **Validation:** Lock distance slider must always be at least 10 dBm below the unlock slider (hysteresis gap). Auto-adjust the sibling slider if dragged past constraints.

### 2.3 Inline Key Management (KEYS Section)
This section queries `SLOTS?` via BLE Management Command to populate the UI.
*   **Implementation note:** Treat this `SLOTS?` read path as the first required milestone for Agent 8. The slot list must be working before any rename, replace, delete, or QR flow is attempted.
*   **Owner View:** Shows all 4 slots. 
    *   Slot 0 (Uguisu): iOS is non-interactive. Android has a 3-dot menu with "Replace".
    *   Slot 1 (Self): No 3-dot menu.
    *   Slot 2/3 (Active Guest): 3-dot menu with "Rename", "Replace", "Delete".
    *   Slot 2/3 (Empty Guest): Shows a large ⊕ icon to trigger Provisioning.
*   **Guest View:** Only shows a "YOUR KEY" section with their own slot name and a "Transfer to New Phone" button. They see no other slots.

### 2.4 Workflows (Driven by KMP and BLE Headless Services)

**Precondition for all workflows**
Before any workflow below is enabled in the UI, the Settings screen must already have a working management session lifecycle and a successful `SLOTS?` read implementation.

**1. Provision Guest Phone**
Triggered via ⊕ on an empty guest slot. Generates new AES key, sends `PROV:<slot>:<key>:0:Guest X` via BLE. Displays a **plaintext QR code** for the guest to scan.
```
┌─────────────────────────────┐
│                             │
│   Add a guest key?          │
│                             │
│   This will create a key    │
│   for Slot 2 (Guest 1).    │
│   The guest will be able    │
│   to lock and unlock only.  │
│                             │
│        [ Create Key ]       │
│        [ Cancel ]           │
│                             │
└─────────────────────────────┘
```
*(QR Display Screen)*
```
┌─────────────────────────────┐
│                             │
│   Scan this on the          │
│   guest's phone             │
│                             │
│   ┌───────────────────┐     │
│   │                   │     │
│   │    [QR Code]      │     │
│   │                   │     │
│   └───────────────────┘     │
│                             │
│   The guest just needs to   │
│   scan — no PIN required.   │
│                             │
│        [ Done ]             │
│                             │
└─────────────────────────────┘
```

**2. Replace Flow (Break-Glass)**
Triggered via 3-dot menu -> Replace. Sends `REVOKE:<slot>`, generates new key, sends `PROV:<slot>:<key>:0:<name>`. Generates the appropriate QR (plaintext for guest slots, Argon2id encrypted for Owner slot).
*   **Sequencing note:** Do not implement this before the simpler `RENAME` and `IDENTIFY` actions are already working through the same BLE management session.
```
┌─────────────────────────────┐
│                             │
│   ⚠ Replace "Jamie's       │
│   iPhone" (Slot 1)?         │
│                             │
│   This will permanently     │
│   lock out the old device   │
│   and create a new key      │
│   for a replacement phone.  │
│                             │
│   [ Replace ]               │
│   [ Cancel ]                │
│                             │
└─────────────────────────────┘
```

**3. Transfer to New Phone (Migration)**
Generates a QR containing the existing key AND the current counter value. Guest keys generate plaintext QR; Owner keys generate Argon2id PIN-encrypted QR. On confirmation of scan, the key is permanently deleted from the local secure keystore.
*   **Sequencing note:** This is not the first QR flow to build. Implement it after slot listing, preference controls, and guest provisioning are already stable.
```
┌─────────────────────────────┐
│                             │
│   Transfer your key to a    │
│   new phone?                │
│                             │
│   This will generate a QR   │
│   code for your new phone   │
│   to scan. After the        │
│   transfer, this phone      │
│   will no longer work as    │
│   a key.                    │
│                             │
│   [ Generate QR Code ]      │
│   [ Cancel ]                │
│                             │
└─────────────────────────────┘
```
*(QR Display Screen)*
```
┌─────────────────────────────┐
│                             │
│   Scan this on your         │
│   new phone                 │
│                             │
│   ┌───────────────────┐     │
│   │                   │     │
│   │    [QR Code]      │     │
│   │                   │     │
│   └───────────────────┘     │
│                             │
│   Open Pipit on your new    │
│   phone and scan this code. │
│                             │
│   [ Done — I've Scanned ]   │
│   [ Cancel ]                │
│                             │
└─────────────────────────────┘
```
