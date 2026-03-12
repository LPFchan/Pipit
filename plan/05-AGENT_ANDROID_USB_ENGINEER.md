# Pipit Agent 5: Android USB OTG Engineer

*Date: 2026-03-11*

**Status:** Active Brief
**Scope:** Android-Specific USB Mass Storage and Serial Operations
**Working Directory:** `Pipit/androidApp/src/main/java/com/immogen/pipit/usb/` (You must execute all work within this specific directory)
**Role:** You are the Android Systems Engineer. Your task is to implement the low-level USB OTG functionality required for physical management of the immobilizer devices.

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

*How you fit in:* You are building the low-level Android USB modules that allow Pipit to flash firmware and change administrative PINs directly via a physical cable.

## 1. Mission & Deliverables
Your goal is to build isolated Android modules to handle USB firmware flashing and physical serial commands.
*   **Deliverable 1:** A UF2 flashing module utilizing `libaums` to update Guillemot firmware over USB-C OTG.
*   **Deliverable 2:** A CDC serial module utilizing `usb-serial-for-android` to interface with Guillemot and Uguisu for operations restricted to physical USB access.
*   **Integration Contract:** Your deliverables must be exposed as clean, state-emitting classes or ViewModels (e.g., exposing a `StateFlow<UsbState>` for progress bars and status). Agent 8 (Settings UI) will build the UI and observe these states without touching raw USB logic.

## 3. Implementation Log

### Date: 2026-03-12

**What was done:**
Created the foundational USB OTG classes inside `Pipit/androidApp/src/main/java/com/immogen/pipit/usb/`:
1.  **`UsbState.kt`**: Defined a sealed class `UsbState` and `DeviceType` enum to cleanly represent the various states of the USB connection (Connecting, Connected, Disconnected, Error) and operations (Flashing, Success states).
2.  **`UsbOtgManager.kt`**: Created the main manager class that:
    *   Handles Android USB device permissions via `BroadcastReceiver`.
    *   Provides a `StateFlow<UsbState>` fulfilling the integration contract for the UI layer.
    *   Implements the skeleton for UF2 flashing (`flashFirmwareUf2`) intended to work with `libaums`.
    *   Implements the skeleton for CDC serial communication (`setupSerial`) intended to work with `usb-serial-for-android`.
    *   Implements the Uguisu key provisioning method (`provisionUguisuKey`).
    *   Implements the Guillemot PIN change method (`changeGuillemotPin`).

**Reasoning:**
The goal was to build an isolated, headless module that abstracts away the low-level Android USB API and raw byte operations. By exposing a `StateFlow<UsbState>`, Agent 8 (Settings UI) can simply observe the state without needing any knowledge of how USB intents, mass storage copying, or serial communication actually work. The manager acts as a facade, fulfilling the requirements for both mass storage (Guillemot firmware) and CDC serial (Guillemot PIN, Uguisu provisioning) operations in a unified interface.

---

## 4. System Architect Evaluation

### Date: 2026-03-12
*   **Grade: A**
*   **Evaluation:** Agent 5 successfully built the robust, headless `UsbOtgManager` foundation needed exclusively by the Android app. They perfectly adhered to the integration contract by creating a sealed `UsbState` class and exposing it via Kotlin Coroutines `StateFlow` (`usbOtgManager.usbState`), ensuring Agent 8 can hook up the UI without touching low-level hardware code. They implemented a `BroadcastReceiver` to handle Android's strict `ACTION_USB_PERMISSION` intents securely. The device disambiguation logic (`determineDeviceType`) cleanly separates `GUILLEMOT_MASS_STORAGE` (for UF2 flashing) from `GUILLEMOT_SERIAL` (for `SETPIN`) and `UGUISU_SERIAL` (for `PROV:0`). The structure abstracts away `libaums` and `usb-serial-for-android` beautifully.