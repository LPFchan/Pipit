# Pipit Agent 8: Settings & Key Management UI Engineer

*Date: 2026-03-16*

**Status:** Ready to Start
**Scope:** Settings UI, slot management, proximity preferences, and settings-driven admin flows
**Working Directory:** `Pipit/`
**Role:** Build the real Settings experience on top of the app shell, BLE management transport, shared settings layer, secure storage, and Android USB backend that already exist.

---

## 0. Current Handoff State

This brief replaces the older, more speculative version. It is intentionally shorter and should be treated as the current source of truth for Agent 8.

What already exists:
*   The home screen and app shell are already in place on both platforms. Settings still routes to placeholders.
*   Agent 4 has delivered the BLE management transport and the foreground/background command path needed by Settings.
*   Agent 5 has delivered the Android USB backend used by Settings. The UI should consume it, not reimplement it.
*   Shared proximity settings keys already exist and are already consumed by the BLE layer.
*   Shared crypto, QR parsing, keystore access, and onboarding are already implemented.

If this brief conflicts with older notes in other agent docs, prefer the current codebase and this document.

---

## 1. Mission

Your job is to replace the current Settings placeholders with a real, usable Settings surface on Android and iOS.

Your work must be staged. The first successful milestone is not QR generation or deletion. It is a stable Settings screen that:
*   opens from the existing app shell,
*   connects through the existing BLE management transport,
*   reads `SLOTS?`,
*   renders the slot list,
*   renders proximity controls backed by real persisted settings,
*   and disconnects cleanly when Settings closes.

Do not take ownership of:
*   low-level BLE transport,
*   low-level USB logic,
*   command payload crypto,
*   onboarding,
*   or root app architecture beyond replacing the settings placeholders.

---

## 2. Files You Own

Primary entry points:
*   Android settings route: `androidApp/src/main/java/com/immogen/pipit/ui/PipitApp.kt`
*   iOS settings view controller: `iosApp/iosApp/UI/SettingsPlaceholderViewController.swift`
*   iOS settings presentation path: `iosApp/iosApp/UI/RootViewController.swift`

Shared integration surfaces you must consume:
*   BLE state and management transport: `shared/src/commonMain/kotlin/com/immogen/pipit/ble/BleService.kt`
*   Proximity settings keys: `shared/src/commonMain/kotlin/com/immogen/pipit/settings/SettingsManager.kt`
*   Android USB state contract: `androidApp/src/main/java/com/immogen/pipit/usb/UsbState.kt`

Do not create a second BLE admin transport. Do not add raw USB operations inside UI code.

---

## 3. Real Starting Point

Current placeholder surfaces:
*   Android currently shows `SettingsPlaceholderView` from `PipitApp.kt`.
*   iOS currently installs `SettingsPlaceholderViewController` from `RootViewController`.

Current backend reality:
*   `BleService.managementTransport` is the correct path for `connect`, `disconnect`, `SLOTS?`, `IDENTIFY`, `PROV`, `RENAME`, `REVOKE`, and `RECOVER`.
*   Proximity preferences must use these exact keys:
    *   `pref_proximity_enabled`
    *   `pref_unlock_rssi`
    *   `pref_lock_rssi`
*   Android USB backend already exposes a usable `StateFlow<UsbState>` for connection, flashing, PIN change, and Uguisu key provisioning.

Important scope note:
*   Android USB support is real enough for Settings integration.
*   Uguisu firmware flashing is not the first Settings milestone and should not block the main BLE-backed Settings flow.
*   Preserve the current shell and routing pattern first. Do not block the Settings milestone on transition polish.

---

## 4. Delivery Order

Build in this order.

### 4.1 Milestone 1: Replace Placeholder Settings Screens
Deliver a real Settings container on both platforms.

Requirements:
*   Keep the existing app-shell routing pattern.
*   Open Settings from the existing gear action.
*   Close Settings back to Home cleanly.
*   Show loading, empty, and error states where needed.

### 4.2 Milestone 2: Read-Only Slot List via BLE
This is the first real Settings milestone.

Requirements:
*   On Settings open, connect using the existing standard BLE management path.
*   Request `SLOTS?` using the existing transport.
*   Render the four returned slots.
*   Support loading, retry, and disconnect-on-close.
*   Do not start mutation flows yet.

### 4.3 Milestone 3: Real Proximity Controls
Add proximity preferences backed by the shared settings keys.

Requirements:
*   Background Unlock toggle.
*   Unlock RSSI control.
*   Lock RSSI control.
*   Enforce the 10 dBm hysteresis gap.
*   Read and write the exact keys already used by Agent 4.

### 4.4 Milestone 4: Low-Risk Slot Actions
Only after slot listing and proximity controls are stable.

Requirements:
*   Determine the current phone tier from the locally provisioned slot.
*   Use the existing management session for `IDENTIFY` and `RENAME`.
*   Keep owner and guest layouts distinct.

### 4.5 Milestone 5: Guest Provisioning and Replace Flow
Only after the simpler actions are stable.

Requirements:
*   Provision guest slots using `PROV`.
*   Replace slots using `REVOKE` followed by `PROV`.
*   Generate the correct QR form:
    *   plaintext for guest keys,
    *   Argon2-backed encrypted QR for owner flows.

### 4.6 Milestone 6: Migration and Local Deletion
Build this after the earlier QR flow works.

Requirements:
*   Generate a transfer QR from the existing local key and counter.
*   Delete the local key only after explicit user confirmation of transfer completion.

### 4.7 Milestone 7: Android-Only USB Settings Actions
This is later work, not the first milestone.

Requirements:
*   Bind Settings UI to the existing Android USB backend.
*   Surface connection state, progress, success, and failure from `UsbState`.
*   Support the Android USB actions that are already backed by Agent 5's headless implementation.
*   Do not rewrite the backend inside the UI layer.

---

## 5. Layout Rules

Keep the Settings layout simple and data-driven.

Owner view should contain:
*   PROXIMITY
*   KEYS
*   DEVICE
*   ABOUT

Guest view should contain:
*   PROXIMITY
*   YOUR KEY
*   ABOUT

Slot behavior:
*   Slot 0: Uguisu hardware slot.
*   Slot 1: owner phone slot.
*   Slot 2 and Slot 3: guest phone slots.

Expected action model:
*   Slot 0:
    *   iOS: non-interactive.
    *   Android: later USB-driven maintenance action only.
*   Slot 1:
    *   Self row, no destructive action in the first pass.
*   Slot 2 and Slot 3:
    *   Rename, replace, revoke, and provisioning behaviors depending on occupancy and ownership.

Do not spend time reproducing large static mockups from the old brief. Prefer a clean, working layout that reflects real state and current backend capabilities.

---

## 6. Platform Guidance

### Android
*   Replace `SettingsPlaceholderView` in the existing Compose root flow.
*   Reuse the current screen state structure in `PipitApp.kt`.
*   Consume the BLE service and the existing management transport.
*   Consume `UsbState` later, after the BLE-backed Settings core is stable.

### iOS
*   Replace `SettingsPlaceholderViewController` while preserving the current `RootViewController` child-install flow.
*   Consume the existing Swift BLE service APIs rather than wrapping them in another transport layer.
*   Prioritize a clean, working settings container over animation polish.

---

## 7. Done Criteria

Agent 8 should consider the work complete only when the following are true:
*   Settings opens on both platforms without placeholder content.
*   Settings can connect, request `SLOTS?`, render slot data, and retry on failure.
*   Settings disconnects the BLE management session cleanly when dismissed.
*   Proximity settings persist through the existing shared preference keys.
*   Owner and guest variants are clearly separated.
*   Mutation flows are layered in only after the read-only slot list and proximity settings are stable.
*   Android USB UI, if implemented, is only a consumer of the existing backend state and methods.

---

## 8. Build Expectations

While working:
*   Keep Android changes compatible with `./gradlew :androidApp:compileDebugKotlin`.
*   Keep iOS source diagnostics clean in the touched UIKit files.
*   Prefer small, working milestones over a large one-shot rewrite.

That is the assignment. Start with real settings containers, then the read-only slot list, then proximity controls, and only then move into mutating admin flows.

---

## 9. Session Update

**Updated:** 2026-03-16 15:57:03 KST

What I did in this session:
*   Replaced the Android Settings placeholder with a real Compose settings screen wired into the existing app shell route from `PipitApp.kt`.
*   Added Android Settings support for opening a fresh BLE management session, requesting `SLOTS?`, rendering all four slots, showing loading and retry states, and disconnecting the management session when Settings closes.
*   Added Android proximity controls backed by the existing shared settings keys `pref_proximity_enabled`, `pref_unlock_rssi`, and `pref_lock_rssi`, including enforcement of the 10 dBm hysteresis rule.
*   Replaced the iOS Settings placeholder with a real UIKit settings controller that connects through the existing Swift BLE management APIs, requests `SLOTS?`, renders owner and guest sections, and disconnects cleanly on dismissal.
*   Updated the iOS root presentation path so the global disconnect overlay is hidden while Settings is active, allowing the settings screen to own its own BLE management loading and error states.
*   Validated the work with `./gradlew :androidApp:compileDebugKotlin` and `xcodebuild -project Pipit.xcodeproj -scheme Pipit -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' ARCHS=arm64 ONLY_ACTIVE_ARCH=YES build`.

Why I did it:
*   This session was focused on Milestone 1 through Milestone 3 from this agent brief: replacing placeholder settings screens, delivering the first real read-only slot list through the existing BLE management transport, and wiring real persisted proximity controls through the existing shared settings layer.
*   The goal was to establish a stable, build-validated Settings foundation on both platforms before moving on to lower-risk mutations like `IDENTIFY` and `RENAME`, and before attempting guest provisioning, replace flows, migration, or Android USB UI work.
