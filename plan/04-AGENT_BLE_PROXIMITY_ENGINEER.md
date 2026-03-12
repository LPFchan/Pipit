# Pipit Agent 4: BLE Proximity Engineer

*Date: 2026-03-11*

**Status:** Completed
**Scope:** iOS & Android Headless Background BLE Services
**Working Directory:** `Pipit/` (You must execute all work within this specific directory)
**Role:** You are the Mobile BLE Engineer. Your task is to build the low-level, headless proximity engine for Pipit. You are not building UI.

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

*How you fit in:* You are building the headless iOS/Android BLE background engines that detect the vehicle and trigger the proximity unlocks.

## 1. Mission & Deliverables
Your goal is to build the background services that detect the Guillemot beacon and automatically trigger the AES-CCM payloads based on RSSI thresholding.
*   **Deliverable 1 (iOS):** Swift service utilizing `CoreLocation` (iBeacon region monitoring) to wake the app, handing off to `CoreBluetooth` for GATT connection and RSSI evaluation.
*   **Deliverable 2 (Android):** Kotlin `Foreground Service` utilizing `BluetoothLeScanner` directly for the GATT advertisement.
*   **Deliverable 3:** A unified state stream (e.g., Flow/Publisher) exposing connection state and RSSI to the UI layer.
*   **Deliverable 4:** A foreground scanning hook/Flow that specifically listens for the `Window Open` UUID. Agent 7 (Onboarding UI) will subscribe to this for the "Recover Key from Lost Phone" flow.

## 2. Technical Context

### 2.1 The BLE Roles & Beacon Types
*   **Guillemot (Advertiser):** Broadcasts both a continuous GATT peripheral beacon AND an iBeacon.
*   **iBeacon Wake (iOS specifically):** Guillemot broadcasts an iBeacon (`66962B67-9C59-4D83-9101-AC0C9CCA2B12`) at a fixed 300 ms interval. CoreLocation detects this region entry and wakes Pipit to initiate the CoreBluetooth GATT connection.

### 2.2 Stateful Proximity Beaconing & Dynamic Intervals
Guillemot dynamically changes its advertised Service UUID based on the latch state and provisioning window:
*   **Immogen Proximity - Locked:** UUID `C5380EF2-C3FC-4F2A-B3CC-D51A08EF5FA9` (300 ms interval). Pipit scans for this on approach.
*   **Immogen Proximity - Unlocked:** UUID `A1AA4F79-B490-44D2-A7E1-8A03422243A1` (200 ms interval). Pipit monitors this for walk-away.
*   **Immogen Proximity - Window Open:** UUID `B99F8D62-A1C3-4E8B-9D2F-5C3A1B4E6D7A` (100 ms interval). Pipit scans for this during the lost phone recovery flow.

### 2.3 RSSI Thresholds & Hysteresis Logic
You must implement a 10 dBm hysteresis gap to prevent rapid lock/unlock cycling:
*   **Unlock threshold (default):** `-65 dBm`
*   **Lock threshold (default):** `-75 dBm`
Both thresholds are user-configurable via the UI (stored locally).
*   **Approach:** When scanning the `Locked` UUID, if RSSI >= Unlock threshold, connect via GATT and send the Unlock payload.
*   **Walk-Away:** When monitoring the `Unlocked` UUID, maintain a rolling history of high-frequency RSSI readings. When RSSI <= Lock threshold, connect and send the Lock payload.

### 2.4 The Walk-Away Dropout Edge Case
If the beacon drops entirely *before* reaching the lock threshold (e.g., walking behind a concrete wall):
*   Analyze the recent RSSI history trend.
*   If decreasing: Infer a walk-away, enter an aggressive scanning state, and fire the Lock payload the instant the beacon is visible again.
*   If stable: Assume a sudden failure (e.g., phone reboot) and safely ignore the drop.

### 2.5 GATT Service & Characteristic UUIDs
*   **Immogen Proximity Service:** `942C7A1E-362E-4676-A22F-39130FAF2272`
*   **Unlock/Lock Command Characteristic:** `2522DA08-9E21-47DB-A834-22B7267E178B` (Write Without Response). The payload byte array will be provided to you by the KMP Core logic module.

### 2.6 Local Storage Contract (Integration with Agent 8)
Agent 8 (Settings UI) provides sliders to adjust proximity thresholds. To ensure your headless service reads the correct values, you must both use the following strict keys for `UserDefaults` (iOS) and `SharedPreferences` (Android) (or a Multiplatform Settings library):
*   `pref_proximity_enabled` (Boolean, default: true)
*   `pref_unlock_rssi` (Integer, default: -65)
*   `pref_lock_rssi` (Integer, default: -75)