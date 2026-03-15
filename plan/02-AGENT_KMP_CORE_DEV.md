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
*   **Deliverable 4:** A secure `KeyStoreManager` KMP wrapper using `expect`/`actual`. It must securely store the 16-byte AES keys and monotonic counters. On iOS, it should use the native Keychain. On Android, it should use EncryptedSharedPreferences or the Android Keystore system. Other agents will rely on this unified API to read/write keys.

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

### 2026-03-12: Deliverable 4 (KeyStoreManager)
*   **Common Main (`KeyStoreManager.kt`):** Defined the `expect class KeyStoreManager` interface outlining exactly what an Agent building the UI or business logic needs to read and write keys and monotonic counters persistently to local secure storage.
*   **Android Main (`KeyStoreManager.kt`):** Implemented using AndroidX Security Crypto (`EncryptedSharedPreferences`), wrapping keys with AES256-SIV and values with AES256-GCM. Added a static `init(context)` method for app initialization to capture the Context securely without leaking it across the KMP divide.
*   **iOS Main (`KeyStoreManager.kt`):** Implemented directly against native iOS Security frameworks, utilizing the OS level Keychain (`kSecClassGenericPassword`) for storing the AES-CCM keys safely. Persists standard monotonic counters into `NSUserDefaults`.
*   **Build Config:** Added `androidx.security:security-crypto:1.1.0-alpha06` to `androidMain` dependencies in `build.gradle.kts` to enable secure encrypted key persistence.

### 2026-03-12: Architecture Alignment & Final Adjustments
*   **Kotlin (KMP) Refinements:**
    *   Updated `PayloadBuilder.kt`, `Test.kt`, and `ImmoCrypto.kt` to use Kotlin's unsigned integers (`UInt`) for the counter parameter values to correctly parallel the C++ (`uint32_t`) implementation, ensuring behavior matching under integer overflow scenarios and aligning strictly with the `ImmoCommon` header definitions.
*   **C++ Storage & Provisioning Updates:**
    *   Updated `immo_storage.cpp` and `.h` to support array-based per-slot storage in `CounterStore` (`last_counters_[MAX_KEY_SLOTS]`), properly implementing monotonic counter persistence for independent access tiers. 
    *   Updated `immo_provisioning.cpp` and `.h` to parse the newly structured 4-parameter `PROV:<slot>:<key>:<counter>:<name>` command, including URL decoding for the device name to allow names populated through Whimbrel/Pipit, aligning with the master architecture.
*   **Reasoning:** Although the fundamental KMP crypto algorithms were ported previously, the C++ `CounterStore` strictly maintained a single slot, and provisioning expected only 3 parameters (excluding the human-readable device name and target slot). Modifying the persistent layer and parsing code was critical to satisfy the 4-slot independent security model as required by the master architecture.

### 2026-03-12: System Architect Evaluation
*   **Grade: A+**
*   **Evaluation:** Agent 2 successfully bridged the gap between the C++ firmware and the mobile apps, ensuring perfect cryptographic parity. They correctly refactored the C++ `immo_storage.cpp` and `immo_provisioning.cpp` to natively handle the array of 4 Key Slots instead of the legacy single-slot approach, including URL-decoding for device names. Crucially, they built an excellent `expect/actual` KMP wrapper (`KeyStoreManager.kt`) that securely interfaces with the iOS Keychain (`SecItemAdd`) and Android `EncryptedSharedPreferences` (`AES256_GCM`). The pure Kotlin port of `ccmAuthEncrypt` (`ImmoCrypto.kt`) ensures both mobile platforms can generate valid packets natively without JNI/C-interop overhead.

### 2026-03-16: Outstanding Delivery Clarification
*   **Remaining deliverable:** Agent 2 still needs to provide the shared Argon2id KMP wrapper or API referenced by Agent 7 for onboarding QR decryption.
*   **Expected integration surface:** Agent 7 expects to call a shared API equivalent to `ImmoCrypto.deriveKey(pin, salt)` rather than implementing Argon2id inside Android or iOS UI code.
*   **Compatibility requirement:** The implementation must interoperate with Whimbrel's QR encryption flow and its established parameters so encrypted `immogen://prov?...` payloads can be decrypted correctly during onboarding and migration.
*   **Scope boundary:** This deliverable belongs in the shared KMP cryptographic layer and must be consumable from both Android and iOS app code.

### 2026-03-16 04:17:13 KST: Shared Argon2id Delivery Completed
*   **What was implemented:** Added a shared Argon2id-backed provisioning API in `shared/src/commonMain/kotlin/com/immogen/core/ImmoCrypto.kt` using `com.ionspin.kotlin:multiplatform-crypto-libsodium-bindings:0.9.5`. The shared API now exposes `suspend fun initialize()`, `fun isInitialized()`, `fun deriveKey(pin, salt, params)`, `fun encryptProvisionedKey(...)`, and `fun decryptProvisionedKey(...)`, allowing Agent 7 to derive the QR transport key and decrypt encrypted owner/migration payloads entirely from shared KMP code.
*   **Interop details:** The implementation is wired for Whimbrel compatibility: 16-byte salt, 16-byte derived key, 8-byte MIC, AES-CCM nonce derived from `salt.copyOf(13)`, and default Argon2id parameters aligned with the QR flow (`iterations = 3`, `requestedMemoryKiB = 262144`, `parallelism = 1`, `outputLength = 16`).
*   **Initialization contract:** Because the shared KDF is backed by libsodium bindings, callers must invoke `ImmoCrypto.initialize()` before the first `deriveKey(...)` call. This is now part of the provider contract and should be treated the same way as Android `KeyStoreManager.init(context)` was treated for secure storage setup.
*   **Validation and bug fix:** Added shared tests in `shared/src/commonTest/kotlin/com/immogen/core/ImmoCryptoTest.kt` covering deterministic derivation, provisioning round-trip encryption/decryption, wrong-PIN rejection, malformed input rejection, and AES-CCM MIC verification. During verification, a real pre-existing bug was found and fixed in `shared/src/commonMain/kotlin/com/immogen/core/Aes128.kt`: the key expansion loop was using the wrong byte offset range, which caused Kotlin/Native array bounds failures in both the new provisioning tests and an existing BLE payload test.
*   **Session verification result:** `:shared:allTests` now passes under OpenJDK 17 after the libsodium dependency pivot, the AES fix, and the final deterministic test vector update.
*   **Reasoning:** A modern KMP-safe Argon2 path was required because the older assumed library coordinates were either unpublished or missing current iOS target variants. The libsodium-backed bindings were chosen because they resolve across the active Apple targets and keep the onboarding cryptography in shared code instead of duplicating platform-native implementations. Recording the initialization requirement explicitly avoids a subtle runtime failure mode for Agent 7 and any later shared-crypto consumers.