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

## 2. Technical Context

### 2.1 The Need for USB OTG (Android Only)
Because iOS does not support USB OTG host mode for mass storage or raw CDC serial, these features are Android-exclusive. `SETPIN` and `RESETLOCK` are restricted to USB-C serial in the architecture to prevent remote attacks by compromised phones.

### 2.2 USB Flashing — Guillemot (UF2)
Flashes the Guillemot immobilizer firmware using the UF2 mass storage protocol.
1.  Detect the UF2 mass storage volume via `libaums` when the user connects Guillemot and enters bootloader mode.
2.  Provide logic to copy a selected `.uf2` firmware file to the root of the mass storage volume. (Guillemot will automatically reboot).

### 2.3 USB Flashing — Uguisu (CDC Serial)
Flashes the Uguisu hardware fob and provisions its Slot 0 key.
1.  Open a CDC serial connection via `usb-serial-for-android`.
2.  Implement the nRF52840's serial DFU protocol for sending compiled firmware binaries.
3.  Send the key provisioning command `PROV:0:<key>:0:Uguisu` via the serial console to configure its Slot 0 AES key.

### 2.4 Change PIN via Serial (Guillemot)
The Management PIN can only be changed over USB.
1.  Listen for Guillemot via CDC serial.
2.  Send `SETPIN:<6digits>` in plaintext.

*Note: Your deliverables should be headless utility classes or ViewModels. The UI layer will handle the actual text inputs and progress bars.*