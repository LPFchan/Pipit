# Project Guidelines

## Canonical Docs

- Treat [SPEC.md](../SPEC.md) as the project-level source of truth for what Pipit is supposed to be.
- Treat [STATUS.md](../STATUS.md) as the source of truth for current accepted repo reality.
- Treat [PLANS.md](../PLANS.md) as the source of truth for accepted future direction.
- Treat [PIPIT_MASTER_ARCHITECTURE.md](../PIPIT_MASTER_ARCHITECTURE.md) as the authoritative reference for slot semantics, BLE flows, provisioning, and security constraints.
- Use [records/decisions/](../records/decisions/) for durable rationale and [records/agent-worklogs/](../records/agent-worklogs/) for execution history.

## Architecture

- Keep protocol, crypto, counter, and shared business logic in `shared/`; keep OS integration in the native app targets.
- iOS-specific UI, BLE, CoreLocation, and bundled viewer work live under `iosApp/iosApp/`.
- Android-specific UI, BLE service, camera, and USB work lives under `androidApp/src/main/`.
- Slot tiers are fixed by internal slot ID and should not be reinterpreted in logic: internal slot 0 = Uguisu hardware fob, internal slot 1 = owner, internal slots 2-3 = guest. User-facing UI may label these as slots 1-4 as long as the underlying mapping remains unchanged.

## Build And Test

- Use JDK 17 for all Gradle commands.
- Android builds require SDK 35 configured through `local.properties` or `ANDROID_HOME` / `ANDROID_SDK_ROOT`.
- Validate shared/KMP changes with `./gradlew :shared:compileIosMainKotlinMetadata :shared:assemble`.
- Validate Android app changes with `./gradlew :androidApp:assembleDebug` and `./gradlew :androidApp:testDebug` when tests are relevant.
- Validate iOS app changes with `xcodebuild -project Pipit.xcodeproj -scheme Pipit -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build`.
- Prefer `Pipit.xcodeproj` for iOS work. `iosApp/Package.swift` is not the authoritative app build entry point.

## Conventions

- Do not edit generated outputs under `build/`, `androidApp/build/`, `shared/build/`, or Xcode user data directories.
- Keep the iOS deployment target at 17.0 or newer. The onboarding flow uses Swift Observation and will not compile correctly below iOS 17.
- `Pipit.xcodeproj` links the KMP `shared.framework` from `shared/build/bin`; simulator builds depend on the simulator slices and search paths being correct for both `iosSimulatorArm64` and `iosX64`.
- Preserve the strict monotonic-counter security model. Do not add replay windows, shared-slot behavior, or relaxed counter acceptance unless the architecture document is updated accordingly.
- Follow existing native patterns instead of forcing cross-platform UI abstractions: SwiftUI plus platform BLE APIs on iOS, Jetpack Compose plus Android services on Android, `StateFlow` for shared and Android state.
- Prefer the canonical repo surfaces over any retired brief-style planning documents. Route new truth, plans, decisions, research, and logs into the new root docs and `records/` directories.
- In docs and user-facing text, prefer `vehicle` over `scooter` to match the architecture terminology.

## Collaboration

- Route untriaged intake to `INBOX.md`, reusable dependency context to `research/`, durable decisions to `records/decisions/`, and execution history to `records/agent-worklogs/`.
- Prefer appending to the current relevant `LOG-*` when the same workstream continues; create a new `LOG-*` only when the execution thread is materially distinct or reuse would obscure provenance.
- Ask clarifying questions when user intent, constraints, or acceptance criteria are ambiguous instead of guessing.
- Prefer current repository docs and internet verification over memory when checking APIs, libraries, frameworks, platform behavior, or tool availability.
- Before recommending a specific external dependency, service, framework, or API, verify that it exists, is readily available, and is not end-of-life.
- If the user's approach is unclear or potentially weak, ask for clearer direction or present an explicit alternative instead of silently changing the approach.
- When implementing from a Figma design or prototype, treat visual fidelity as a rigid requirement: match sizing, position, spacing, padding, font sizes, and colors as closely as possible to pixel-perfect accuracy.

## Key Files

- [SPEC.md](../SPEC.md) for project identity, invariants, and core capabilities.
- [STATUS.md](../STATUS.md) for current repo reality and active risks.
- [PLANS.md](../PLANS.md) for accepted future direction.
- [README.md](../README.md) for repo overview and baseline build requirements.
- [PIPIT_MASTER_ARCHITECTURE.md](../PIPIT_MASTER_ARCHITECTURE.md) for system design and protocol rules.
- [shared/build.gradle.kts](../shared/build.gradle.kts) for KMP targets and framework generation.
- [iosApp/iosApp/RootView.swift](../iosApp/iosApp/RootView.swift), [iosApp/iosApp/UI/OnboardingView.swift](../iosApp/iosApp/UI/OnboardingView.swift), and [iosApp/iosApp/UI/SettingsView.swift](../iosApp/iosApp/UI/SettingsView.swift) for current iOS UI patterns.
- [iosApp/iosApp/BLE/IosBleProximityService.swift](../iosApp/iosApp/BLE/IosBleProximityService.swift) and [androidApp/src/main/java/com/immogen/pipit/ble/AndroidBleProximityService.kt](../androidApp/src/main/java/com/immogen/pipit/ble/AndroidBleProximityService.kt) for platform BLE behavior.
