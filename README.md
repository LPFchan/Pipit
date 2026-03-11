# Pipit — Ninebot G30 BLE Immobilizer Companion App

**Pipit** is the mobile companion app of the [Immogen](https://github.com/LPFchan/Immogen) immobilizer ecosystem for the Ninebot Max G30. It provides seamless background proximity unlock, a manual 3D interactive key fob, and cryptographic key management.

Pipit connects to the **Guillemot** deck receiver and acts as a software alternative to the **Uguisu** hardware key fob. 

## Features

1. **Proximity Unlock (Background):** A low-power BLE service that detects the vehicle and automatically unlocks it based on customizable RSSI thresholding (e.g., approach to unlock, walk away to lock).
2. **Active Key Fob (Foreground):** A single-screen utility interface featuring a photorealistic 3D interactive render of the Uguisu fob. Tap to unlock, hold to lock.
3. **Multi-Slot Key Management:** Securely manage up to 4 key slots. Provision guest phones, revoke compromised keys, and securely migrate devices.
4. **Offline Provisioning:** Uses Argon2id-encrypted QR codes for owner setup (via the [Whimbrel](https://github.com/LPFchan/Whimbrel) dashboard) and plaintext QR codes for simple guest provisioning—all without relying on an external cloud server.

## Tech Stack

*   **Shared Core:** Kotlin Multiplatform (KMP) handling AES-CCM crypto and monotonic counter logic (shared between iOS and Android).
*   **Native UI:** UIKit/RealityKit (iOS) and Jetpack Compose/SceneView (Android) for performant 3D rendering and platform-specific haptic schedules.
*   **Background Services:** Native CoreLocation iBeacon monitoring + CoreBluetooth (iOS) and Foreground Service GATT scanning (Android) to ensure reliable background proximity detection.

## Repository Structure

| Path             | Description                                                                                                                                                                       |
| ---------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `shared/`        | **[Agent 2]** Kotlin Multiplatform core containing platform-agnostic business logic, AES-CCM crypto math, and monotonic counter models (`commonMain`, `androidMain`, `iosMain`). |
| `androidApp/`    | **[Agents 4, 5, 6, 7, 8]** Native Android application. Contains Jetpack Compose/SceneView UI (`ui/`), Background GATT Services (`ble/`), and USB OTG/CDC utilities (`usb/`). |
| `iosApp/`        | **[Agents 4, 6, 7, 8]** Native iOS application. Contains SwiftUI/RealityKit UI (`UI/`) and CoreLocation/CoreBluetooth Background Services (`BLE/`). |
| `plan/`          | AI Project Management briefs outlining specific domains (Firmware, KMP, BLE, UI) used to delegate tasks across multiple autonomous AI agents. |
| `33-PIPIT_MASTER_ARCHITECTURE.md` | The definitive architectural blueprint for the entire Pipit system, key slot management, and GATT protocol. |

## Ecosystem Integration

Pipit interacts with the other Immogen projects via specific BLE GATT characteristics and payloads:
- **Unlock/Lock:** 14-byte encrypted AES-CCM payload sent to Guillemot via a Write Without Response characteristic.
- **Management:** Administrative operations (`PROV`, `REVOKE`, `RENAME`) performed over an authenticated BLE session gated by an SMP 6-digit PIN.

## Safety & Legal

- This is a prototype security/power-interrupt device. Use at your own risk.
- Not affiliated with Segway-Ninebot.
- **Do not test “lock” behavior while riding.**