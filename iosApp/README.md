# Pipit iOS App

The iOS target is a SwiftUI app rooted at `PipitApp.swift`. `RootView.swift` decides whether the user sees onboarding, the home fob surface, or Settings based on local provisioning state and BLE connection state.

## Setup

- Open `Pipit.xcodeproj` and build the `Pipit` scheme.
- Ensure the Kotlin Multiplatform `shared.framework` has been built and linked into the iOS target.
- Add all files under `iosApp/iosApp/`, `iosApp/iosApp/UI/`, and `iosApp/iosApp/BLE/` to the target as needed.
- The app entry point is `@main` in `PipitApp.swift`.

## UI Structure

- `RootView.swift` switches between onboarding, home, and settings.
- `HomeView.swift` hosts the fob interaction surface.
- `OnboardingView.swift` and `OnboardingViewModel.swift` drive QR import and recovery flows.
- `SettingsView.swift` and `SettingsViewModel.swift` drive slot management and proximity controls.

## Fob Viewer

The fob surface is currently driven by `FobRealityViewWrapper.swift`, which embeds the local `viewer.html` experience through `WKWebView` and `LocalSchemeHandler`.

- Local viewer assets come from `assets/` and the vendored `vendor/three/` dependency.
- SwiftUI bridges button depth, LED state, hit-region updates, and camera commands into the viewer.
- Placeholder assets can still be swapped for final production assets later without changing the overall interaction contract.

## BLE

`IosBleProximityService.swift` owns scanning, connection state, proximity commands, management commands, and onboarding or settings support. Manual fob actions and management flows should call through that service instead of implementing their own BLE stack.
