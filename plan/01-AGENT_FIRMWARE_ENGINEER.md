# Pipit Agent 1: Firmware Engineer

*Date: 2026-03-11*

**Status:** Active Brief
**Scope:** Guillemot & Uguisu Firmware Updates for Pipit Integration
**Working Directory:** `Immogen/` (You must execute all work within this specific directory)
**Role:** You are the Firmware Engineer responsible for the embedded C++ nRF52 codebase in the Immogen monorepo. Your task is to update the firmware to support the Pipit app's BLE Proximity and Key Management features.

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

*How you fit in:* You are building the C++ firmware backbone on the immobilizer that allows the Pipit app to communicate with it securely over BLE.

## 1. Mission & Deliverables
Your goal is to update `Guillemot` (the vehicle immobilizer) and `Uguisu` (the hardware key fob) to meet the new Pipit architecture requirements.
*   **Deliverable 1:** Flashing-ready `main.cpp` for `Guillemot` implementing dual BLE roles, stateful beaconing, and SMP pairing.
*   **Deliverable 2:** Updated serial and GATT command parser in `Guillemot`.
*   **Deliverable 3:** Updated `main.cpp` for `Uguisu` with explicit prefix byte packing for Slot 0, and new button debounce logic to detect triple-presses and send the `0x03` Window payload.

## 2. Technical Context
You only need to care about the embedded logic. Ignore mobile UI/UX or dashboard specifics.

### 2.1 BLE Roles & Beaconing
*   **Guillemot (Advertiser):** Must broadcast a continuous beacon as a connectable GATT peripheral.
*   **iBeacon Wake:** Guillemot simultaneously broadcasts an **iBeacon** advertisement using UUID `66962B67-9C59-4D83-9101-AC0C9CCA2B12` at a **fixed 300 ms interval**. The nRF52840's extended advertising allows both iBeacon and GATT to broadcast concurrently.
*   **Stateful Proximity Beaconing:** To support dynamic RSSI tracking for the app, the GATT advertising interval and Service UUID dynamically shift based on the latch state and provisioning window:
    *   **Locked:** UUID `C5380EF2-C3FC-4F2A-B3CC-D51A08EF5FA9`, **300 ms** interval.
    *   **Unlocked:** UUID `A1AA4F79-B490-44D2-A7E1-8A03422243A1`, **200 ms** interval.
    *   **Window Open:** UUID `B99F8D62-A1C3-4E8B-9D2F-5C3A1B4E6D7A`, **100 ms** interval.

### 2.2 GATT Service & Payload
*   **Immogen Proximity Service:** `942C7A1E-362E-4676-A22F-39130FAF2272`
*   **Unlock/Lock Command Characteristic:** `2522DA08-9E21-47DB-A834-22B7267E178B` (Write Without Response). Receives the 14-byte encrypted AES-CCM payload.
*   **Management Command Characteristic:** `438C5641-3825-40BE-80A8-97BC261E0EE9` (Write, Authenticated Link via SMP PIN).
*   **Management Response Characteristic:** `DA43E428-803C-401B-9915-4C1529F453B1` (Notify, MTU to 247 bytes).
*   **Payload structure (14 bytes):** `[1-byte Prefix (AAD)] [4-byte Counter (AAD)] [1-byte Command (Ciphertext)] [8-byte MIC]`. 
*   **Prefix Byte Packing:** `Prefix = (Slot_ID << 4)`. Upper 4 bits denote the target Key Slot (0-3). `Uguisu` must be updated to pack `0x00` (Slot 0).
*   **Commands:** `0x01` = Unlock, `0x02` = Lock, `0x03` = Identify, `0x04` = Window (Triple-press).

### 2.3 Security & Management PIN (SMP)
*   The 6-digit PIN established during USB setup serves as the standard BLE Pairing PIN (SMP) for authenticated management sessions.
*   **Rate Limiting:** Exponential backoff after 3 consecutive failures. 10 failures = 1 hour lockout.
*   **Anti-DoS Bypass:** Any valid AES-CCM Lock or Unlock payload instantly resets the PIN failure counter to zero.

### 2.4 The `IDENTIFY` Command
*   Management access is gated by SMP authentication AND slot identity.
*   The `IDENTIFY` payload is a standard 14-byte AES-CCM packet with command byte `0x03`.
*   Guillemot must store a `session_slot` variable for the lifetime of the GATT connection if `IDENTIFY` succeeds (MIC/counter valid). If invalid, session remains unbound.

### 2.5 Serial & Management Protocol Parser
*   **USB-C Serial Only:** `SETPIN:<6digits>`, `RESETLOCK`. (Must be rejected if source is GATT, *except during the Provisioning Window*).
*   **GATT & Serial:** 
    *   `IDENTIFY` (GATT only)
    *   `PROV:<slot>:<key>:<ctr>:[name]`
    *   `RENAME:<slot>:<name>`
    *   `SLOTS?`
    *   `REVOKE:<slot>`
    *   `RECOVER:<slot>:<key>:<ctr>:[name]` (Requires Unlocked vehicle hardware state if unidentified).
*   **Response Format:** Structured JSON over both transports (e.g., `{"status":"ok","slot":1,"name":"iPhone","counter":0}`).

### 2.6 Fob-Authorized Provisioning Window
*   To allow users to add a Phone Key seamlessly later without needing USB, and to recover keys from lost phones, Guillemot must implement a **30-second Provisioning Window**.
*   **Trigger:** Whenever the user presses the Uguisu button **three times in quick succession**, Uguisu broadcasts a special `Window` payload (command byte `0x04`).
*   **Guillemot Reaction:** When Guillemot successfully receives and parses this valid `Window` payload from Slot 0 (Uguisu), it:
    1.  Starts a 30-second timer (which pauses while a GATT connection is active).
    2.  Plays a distinct chime (three fast beeps at 4 kHz) on the buzzer.
    3.  Changes its advertised Service UUID to the `Window Open` UUID.
*   **Behavior During Window:**
    *   The window temporarily elevates privileges for unauthenticated/unidentified GATT connections, but with strict contextual limits:
    *   **If Slot 1 is EMPTY (Initial Setup):** Guillemot accepts `SETPIN:<6digits>` and `PROV:1:<key>:<ctr>:[name]`. This allows the very first user to establish the PIN and Owner key without USB.
    *   **If Slot 1 is OCCUPIED (Lost Phone):** Guillemot rejects `SETPIN` and `PROV:1`. It only accepts `RECOVER:<slot>:<key>:<ctr>:[name]`. 
    *   *Security Note for RECOVER:* To prevent a guest from hijacking the Owner slot during a window, `RECOVER:1` is gated. Guillemot either requires the connection to be SMP Authenticated (proving the user knows the PIN) OR requires the user to send the correct `SETPIN` first over the unauthenticated link before it accepts `RECOVER:1`. (Guests recovering `RECOVER:2` or `3` do not need the PIN).

## 3. Work Log

### 2026-03-12 Firmware Architecture Updates
*   **What was done:** 
    *   Updated the `Command` enum in `immo_crypto.h` and the Kotlin shared codebase to remap `Identify` to `0x03` and `Window` to `0x04`, syncing with the `PIPIT_MASTER_ARCHITECTURE.md` updates.
    *   Implemented a rolling-window button debouncer in `Uguisu` (`wait_for_button_command`) to accurately detect short clicks, long holds, and triple-clicks, emitting the `0x04` Window payload when a triple-click occurs.
    *   Explicitly packed `(0 << 4)` as the slot ID prefix for `Uguisu` payloads.
    *   Added the `B99F8D...` Window UUID to `Guillemot`, along with a 30-second timer (`g_window_active`) that pauses when a GATT connection is opened.
    *   Refactored the serial parser in `Guillemot` to fully handle `SETPIN`, `RESETLOCK`, `PROV`, `RENAME`, `SLOTS?`, `REVOKE`, and `RECOVER`, backing each slot in an independent `/slotX.dat` LittleFS file rather than a single master key file.
    *   Enforced the tiered security logic in `mgmt_cmd_write_callback`: parsing binary `IDENTIFY` payloads to bind sessions to slot IDs, restricting write commands to the Owner (Slot 1), and securely elevating privileges exclusively during the active 30-second Provisioning Window.
*   **Why it was done:** The prior implementation of Guillemot was a monolithic key store that didn't yet support multi-tier phone access or dynamic provisioning flows. These updates satisfy the newly established Pipit application requirements, enabling secure, phone-based onboarding, isolated guest slots, and "break-glass" remote recovery flows while preserving strict replay protection and DoS resistance.
