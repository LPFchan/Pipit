# Pipit Agent 1: Firmware Engineer

*Date: 2026-03-11*

**Status:** Active Brief
**Scope:** Guillemot & Uguisu Firmware Updates for Pipit Integration
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
*   **Deliverable 3:** Updated `main.cpp` for `Uguisu` with explicit prefix byte packing for Slot 0.

## 2. Technical Context
You only need to care about the embedded logic. Ignore mobile UI/UX or dashboard specifics.

### 2.1 BLE Roles & Beaconing
*   **Guillemot (Advertiser):** Must broadcast a continuous beacon as a connectable GATT peripheral.
*   **iBeacon Wake:** Guillemot simultaneously broadcasts an **iBeacon** advertisement using UUID `66962B67-9C59-4D83-9101-AC0C9CCA2B12` at a **fixed 300 ms interval**. The nRF52840's extended advertising allows both iBeacon and GATT to broadcast concurrently.
*   **Stateful Proximity Beaconing:** To support dynamic RSSI tracking for the app, the GATT advertising interval and Service UUID dynamically shift based on the latch state:
    *   **Locked:** UUID `C5380EF2-C3FC-4F2A-B3CC-D51A08EF5FA9`, **300 ms** interval.
    *   **Unlocked:** UUID `A1AA4F79-B490-44D2-A7E1-8A03422243A1`, **200 ms** interval.

### 2.2 GATT Service & Payload
*   **Immogen Proximity Service:** `942C7A1E-362E-4676-A22F-39130FAF2272`
*   **Unlock/Lock Command Characteristic:** `2522DA08-9E21-47DB-A834-22B7267E178B` (Write Without Response). Receives the 14-byte encrypted AES-CCM payload.
*   **Management Command Characteristic:** `438C5641-3825-40BE-80A8-97BC261E0EE9` (Write, Authenticated Link via SMP PIN).
*   **Management Response Characteristic:** `DA43E428-803C-401B-9915-4C1529F453B1` (Notify, MTU to 247 bytes).
*   **Payload structure (14 bytes):** `[1-byte Prefix (AAD)] [4-byte Counter (AAD)] [1-byte Command (Ciphertext)] [8-byte MIC]`. 
*   **Prefix Byte Packing:** `Prefix = (Slot_ID << 4)`. Upper 4 bits denote the target Key Slot (0-3). `Uguisu` must be updated to pack `0x00` (Slot 0).

### 2.3 Security & Management PIN (SMP)
*   The 6-digit PIN established during USB setup serves as the standard BLE Pairing PIN (SMP) for authenticated management sessions.
*   **Rate Limiting:** Exponential backoff after 3 consecutive failures. 10 failures = 1 hour lockout.
*   **Anti-DoS Bypass:** Any valid AES-CCM Lock or Unlock payload instantly resets the PIN failure counter to zero.

### 2.4 The `IDENTIFY` Command
*   Management access is gated by SMP authentication AND slot identity.
*   The `IDENTIFY` payload is a standard 14-byte AES-CCM packet with command byte `0x02`.
*   Guillemot must store a `session_slot` variable for the lifetime of the GATT connection if `IDENTIFY` succeeds (MIC/counter valid). If invalid, session remains unbound.

### 2.5 Serial & Management Protocol Parser
*   **USB-C Serial Only:** `SETPIN:<6digits>`, `RESETLOCK`. (Must be rejected if source is GATT).
*   **GATT & Serial:** 
    *   `IDENTIFY` (GATT only)
    *   `PROV:<slot>:<key>:<ctr>:[name]`
    *   `RENAME:<slot>:<name>`
    *   `SLOTS?`
    *   `REVOKE:<slot>`
    *   `RECOVER:<slot>:<key>:<ctr>:[name]` (Requires Unlocked vehicle hardware state if unidentified).
*   **Response Format:** Structured JSON over both transports (e.g., `{"status":"ok","slot":1,"name":"iPhone","counter":0}`).