# Pipit Agent 2: Core Logic KMP Dev

*Date: 2026-03-11*

**Status:** Active Brief
**Scope:** `ImmoCommon` Struct Update & Kotlin Multiplatform (KMP) Port
**Working Directory:** `Pipit/shared/` and `Immogen/lib/` (You must execute all work within these specific directories)
**Role:** You are the Core Logic Developer responsible for maintaining the cryptographic core of the Immogen ecosystem.

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

*How you fit in:* You are building the pure Kotlin cryptographic core that Pipit uses to construct the secure AES-CCM payloads to unlock the scooter.

## 1. Mission & Deliverables
Your goal is to refactor the existing C++ shared library to support the new 4-slot architecture, and then port this exact logic to a pure Kotlin Multiplatform (KMP) module for use in the iOS and Android Pipit apps.
*   **Deliverable 1:** Updated C++ `immo_storage.h` and `immo_crypto.cpp` to support 4 key slots.
*   **Deliverable 2:** A new Kotlin Multiplatform (KMP) module named `shared` containing the AES-CCM crypto, state management, and payload builder, validated to behave identically to the C++ version.
*   **Deliverable 3:** An Argon2id KMP wrapper or implementation. Agent 7 (Onboarding UI) will need to call this (e.g., `ImmoCrypto.deriveKey(pin, salt)`) to decrypt QR codes.

## 2. Technical Context

### 2.1 Key Slot Architecture
Guillemot supports **4 key slots** (0–3), each with an independent 16-byte AES-CCM PSK, monotonic counter, and an optional 24-character human-readable device name.
*   Slot 0: `Uguisu` (Hardware Fob)
*   Slot 1: Owner (Full management access)
*   Slot 2: Guest 1 (Lock/unlock only)
*   Slot 3: Guest 2 (Lock/unlock only)

### 2.2 Payload Structure & Slot Identification
The 14-byte command payload structure is: `[1-byte Prefix (AAD)] [4-byte Counter (AAD)] [1-byte Command (Ciphertext)] [8-byte MIC]`.

The 1-byte Prefix carries the Slot ID to route payloads to the correct AES key.
*   **`Prefix = (Slot_ID << 4)`**
*   **Upper 4 bits:** Target Key Slot (0-3).
*   **Lower 4 bits:** Reserved (zero).
*   *Example:* `0x10` instructs Guillemot to pull the AES key for Slot 1.

### 2.3 Required Codebase Modifications (`ImmoCommon`)
*   **Struct Update (`immo_storage.h`):** Refactor the storage struct from a single key/counter into an array of 4 Key Slots. Each slot must contain an AES key array, a monotonic counter, and a `char name[24]` buffer.
*   **Crypto Update (`immo_crypto.cpp`):** Update `verify_payload()` to extract the `Slot ID` using bitwise logic (`prefix >> 4`), validate that the target slot is active, and fetch the correct AES key from storage before executing the CCM MIC check.

### 2.4 Security Model
*   Each key slot maintains an independent strictly-monotonic counter. Any payload where `counter <= last_seen_counter` is rejected. There is no tolerance window.
*   Your KMP port must strictly adhere to this model, exposing the payload builder (`build_payload(slot_id, command, key, counter)`) and the monotonic counter incrementing logic so the UI layer can easily call it.

## 3. Implementation Log

### 2026-03-12: Architecture Alignment & Final Adjustments
*   **Kotlin (KMP) Refinements:**
    *   Updated `PayloadBuilder.kt`, `Test.kt`, and `ImmoCrypto.kt` to use Kotlin's unsigned integers (`UInt`) for the counter parameter values to correctly parallel the C++ (`uint32_t`) implementation, ensuring behavior matching under integer overflow scenarios and aligning strictly with the `ImmoCommon` header definitions.
*   **C++ Storage & Provisioning Updates:**
    *   Updated `immo_storage.cpp` and `.h` to support array-based per-slot storage in `CounterStore` (`last_counters_[MAX_KEY_SLOTS]`), properly implementing monotonic counter persistence for independent access tiers. 
    *   Updated `immo_provisioning.cpp` and `.h` to parse the newly structured 4-parameter `PROV:<slot>:<key>:<counter>:<name>` command, including URL decoding for the device name to allow names populated through Whimbrel/Pipit, aligning with the master architecture.
*   **Reasoning:** Although the fundamental KMP crypto algorithms were ported previously, the C++ `CounterStore` strictly maintained a single slot, and provisioning expected only 3 parameters (excluding the human-readable device name and target slot). Modifying the persistent layer and parsing code was critical to satisfy the 4-slot independent security model as required by the master architecture.