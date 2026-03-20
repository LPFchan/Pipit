# Session Log — 2026-03-19

**Time:** Thu Mar 19 2026, ~13:00 – 15:17 KST  
**Scope:** iOS 3D viewer polish, BLE architecture simplification, dead code removal

---

## 1. JS API implementation in `assets/viewer.html`

**What:** Added three public JavaScript APIs to the Three.js viewer:
- `window.setLedState(r, g, b, active, brightness)` — drives the LED material's emissive colour and intensity
- `window.setButtonDepth(depth)` — translates the `Button` group node along its travel axis
- `window.setModelTransform(px, py, pz, scale, rx, ry, rz)` — repositions/rotates the `modelPivot` wrapper group

Also added:
- `modelPivot` wrapper group so `setModelTransform` doesn't fight the normalisation offset
- `buttonGroup` / `buttonRestPos` tracked at load time so `setButtonDepth` has a stable origin
- `modelReady` postMessage fired after GLB load so Swift knows when to start calling the APIs

**Why:** `updateUIView` in `UIViewRepresentable` fires immediately on first render, before the GLB has finished loading over the custom `local://` URL scheme. Without the `modelReady` handshake the JS calls were silently no-ops every time.

---

## 2. `modelReady` coordinator in `FobRealityViewWrapper.swift`

**What:** Added `WKScriptMessageHandler` coordinator that listens for the `modelReady` message name and re-calls `applyState(to:)` when it fires.

**Why:** Ensures LED colour, button depth, and model transform are applied after the GLB is loaded, not just when SwiftUI drives a `updateUIView` pass.

---

## 3. Deleted obsolete RealityKit files

**Files deleted:**
- `iosApp/iosApp/UI/FobRealityView.swift` — old `UIViewRepresentable` around RealityKit `ARView`
- `iosApp/iosApp/UI/FobPlaceholderView.swift` — 2D SVG fallback that was never shown

**Why:** RealityKit was replaced by the Three.js WKWebView approach in a prior session. The dead files were still in the Xcode project and causing confusion.

---

## 4. Deleted `update_viewer.py`

**What:** Removed the Python script that did `shutil.copy("assets/viewer.html", "iosApp/iosApp/Resources/viewer.html")`.

**Why:** `iosApp/iosApp/Resources/viewer.html` is a **symlink** to `../../../assets/viewer.html`. The copy script was breaking the symlink on every run, silently replacing it with a regular file — causing all viewer edits to become invisible to the Xcode bundle on the next invocation of the script.

---

## 5. Camera parameter corrections

**What:** Updated the GLB load callback in `assets/viewer.html`:
- `PerspectiveCamera` initial `fov` changed from 24° → 60° and seeded at the final position `(-0.0000, -1.8538, -2.9860)` at construction time
- `USE_ORTHO = true` explicitly set before the ortho sync
- `syncOrthoCamera()` guard added: `Math.max(0.001, dist)` to prevent a collapsed ortho frustum when camera is at origin
- `model.rotation.set(0, 0, 3.141593)` — 180° Z flip to orient the fob face-forward

**Why:** The `PerspectiveCamera` was constructed at origin (same as OrbitControls target), giving OrbitControls a zero-length spherical offset. This caused the ortho view to render from the wrong angle. Seeding the position at construction matches the material-mapper convention and eliminates the degenerate state.

---

## 6. Button travel axis and direction fix

**What:**
- travel axis changed from Y → Z
- direction changed from `buttonRestPos.z - travel` → `buttonRestPos.z + travel`

**Why:** The button cap in the Onshape/glTF model sits on the +Z face of the enclosure (facing the camera after the 180° Z rotation). Pressing it into the enclosure moves it in the +Z direction in model space.

---

## 7. Fixed spurious Y-rotation on model

**What:** `FobInteractiveViewer` was passing `modelRotation: SIMD3<Float>(0, -0.4, 0)` (~-23° Y) into `setModelTransform`. Changed to `.zero`.

**Why:** This was a leftover tuning value from an earlier session. The material-mapper export has no Y rotation on the model root, so this rotation made the iOS view visually inconsistent with the design tool.

---

## 8. Fire-and-forget architecture restructure

**What:** Removed all locked/unlocked state tracking from the UI layer:
- `isUnlocked: Bool` parameter removed from `FobInteractiveViewer`
- `bleService.connectionState == .connectedUnlocked` check removed from `HomeView`
- `@AppStorage("hasLockedFobAtLeastOnce")` and `interactedThisSession` state removed from `HomeView`
- LED now always renders at rest with `isActive: true` (green on) — state is purely cosmetic, not driven by BLE connection state

**Why:** Pipit sends fire-and-forget AES-CCM commands over BLE, exactly like pressing a physical key fob. There is no reliable way for the app to know whether the vehicle actually locked or unlocked (the BLE write is unacknowledged at the application layer). Maintaining a `connectedUnlocked` UI state was architecturally misleading and created false feedback. The physical Uguisu fob has no locked/unlocked indicator — neither should the app.

---

## 9. `BUTTON_TRAVEL` calibrated to physical dimensions

**What:** `BUTTON_TRAVEL` changed from `0.012` → `0.005515`.

**Why:** Derived from the actual GLB bounding box. The Uguisu model is exported in glTF meter units: longest axis (Y) = 0.0544 m = 54.4 mm. The user requested 0.3 mm of physical travel, so:

$$\text{BUTTON\_TRAVEL} = \frac{0.3\text{ mm}}{54.4\text{ mm}} = 0.005515$$

The previous value of `0.012` corresponded to ~0.65 mm, visually too much for a tactile cap.

---

## 10. Whole-model press scale (ease-in-out), single `viewer.html` source

**What:** When Swift drives `setButtonDepth`, the viewer now tweens **`modelPivot`** scale by up to **2%** (`PRESS_MODEL_SCALE_DELTA = 0.02`) over **115 ms** with **`ease-in-out` cubic** easing, so the radial CSS gradient on `body` does not scale (only the GLB pivot does). `setModelTransform` stores the Swift-supplied scale as **`_modelBaseScale`** and applies **`_modelBaseScale * (1 - delta * press)`** via `_applyModelPivotScale()`.

**Where to edit:** `assets/viewer.html` only. `iosApp/iosApp/Resources/viewer.html` is a **symlink** to `../../../assets/viewer.html` (same for `materials.js` and `Uguisu.glb`). Do not copy over the symlink with a duplicate file.

**Button hit testing:** Swift calls `window.fobInteractableAtNormalized(nx, ny)` via `evaluateJavaScript` so the **closest** ray hit must be PCB (`BUTTON_TRIGGER_PART_NAMES`) or the KEY1 `buttonObject` — enclosure in front returns false. `postButtonHitRegionIfNeeded` remains in JS for optional diagnostics but the native `buttonHitRegion` message handler was removed; orbit is suppressed while the async hit test is in flight.

---

## Files changed this session

| File | Change |
|---|---|
| `assets/viewer.html` | JS APIs, camera params, button travel axis/direction/magnitude, ortho guard, press-scale tween on `modelPivot` |
| `iosApp/iosApp/UI/FobRealityViewWrapper.swift` | `modelReady` coordinator, removed `isUnlocked`, zeroed model rotation |
| `iosApp/iosApp/UI/HomeView.swift` | Removed state tracking, fire-and-forget wiring |
| `iosApp/iosApp/UI/FobRealityView.swift` | **Deleted** |
| `iosApp/iosApp/UI/FobPlaceholderView.swift` | **Deleted** |
| `update_viewer.py` | **Deleted** |
| `Pipit.xcodeproj/project.pbxproj` | Removed deleted file references |
