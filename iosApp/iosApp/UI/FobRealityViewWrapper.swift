import Combine
import QuartzCore
import SwiftUI
import UIKit
import WebKit

// MARK: – LedCommand

/// A one-shot LED animation trigger.
/// The `id` is incremented by the caller each time a new command is issued so
/// that repeated commands of the same kind (two consecutive unlocks) both fire.
struct LedCommand: Equatable {
    enum Kind: Equatable {
        /// Firmware flash_unlock: green fade-in 300ms / hold 150ms / fade-out 300ms.
        case unlock
        /// Firmware flash_lock: red, same timing.
        case lock
        /// Firmware rainbow_sweep: full HSV rotation over 1500ms.
        case window
        /// Firmware prov_pulse loop: blue 500/200/500/50ms, repeating until cancelled.
        case prov
        /// Firmware flash_low_battery on the given command pin, 2000ms.
        case lowBatUnlock
        case lowBatLock
        /// Static instant-set (no animation); used for initial/idle state.
        case off
    }
    let kind: Kind
    let id:   Int
    static let idle = LedCommand(kind: .off, id: 0)
}

// MARK: – CameraController

private final class CameraDisplayLinkProxy: NSObject {
    weak var controller: CameraController?

    @objc func tick(_ link: CADisplayLink) {
        controller?.flushPendingCameraFromDisplayLink()
    }
}

/// Holds a weak WKWebView reference so FobInteractiveViewer gesture handlers
/// can evaluate JS camera commands (panCamera / zoomCamera) without retaining
/// the web view through the SwiftUI state graph.
fileprivate final class CameraController {
    weak var webView: WKWebView?

    private var pendingDTheta: CGFloat = 0
    private var pendingDPhi: CGFloat = 0
    private var pendingZoomProduct: CGFloat = 1
    private var displayLink: CADisplayLink?
    private let displayLinkProxy = CameraDisplayLinkProxy()

    init() {
        displayLinkProxy.controller = self
    }

    deinit {
        invalidateCameraDisplayLink()
    }

    func orbit(dTheta: CGFloat, dPhi: CGFloat) {
        pendingDTheta += dTheta
        pendingDPhi += dPhi
        startCameraDisplayLinkIfNeeded()
    }

    func zoom(factor: CGFloat) {
        pendingZoomProduct *= factor
        startCameraDisplayLinkIfNeeded()
    }

    /// Ensures the last sub-frame deltas are applied when the finger lifts (display link may not fire again).
    func flushCameraGesturesImmediately() {
        invalidateCameraDisplayLink()
        flushPendingCameraToWebView()
    }

    private func startCameraDisplayLinkIfNeeded() {
        guard displayLink == nil else { return }
        let link = CADisplayLink(target: displayLinkProxy, selector: #selector(CameraDisplayLinkProxy.tick(_:)))
        if #available(iOS 15.0, *) {
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 120, preferred: 120)
        } else {
            link.preferredFramesPerSecond = 0
        }
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func invalidateCameraDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    fileprivate func flushPendingCameraFromDisplayLink() {
        flushPendingCameraToWebView()
        if pendingDTheta == 0, pendingDPhi == 0, abs(pendingZoomProduct - 1) < 1e-6 {
            invalidateCameraDisplayLink()
        }
    }

    private func flushPendingCameraToWebView() {
        let dt = pendingDTheta
        let dp = pendingDPhi
        let zp = pendingZoomProduct
        pendingDTheta = 0
        pendingDPhi = 0
        pendingZoomProduct = 1
        guard dt != 0 || dp != 0 || abs(zp - 1) > 1e-6 else { return }
        let js = "if(window.flushCameraGestures)window.flushCameraGestures(\(Double(dt)),\(Double(dp)),\(Double(zp)));"
        webView?.evaluateJavaScript(js, completionHandler: nil)
    }

    /// Raycast in Three.js: true if the front-most surface at (nx, ny) is PCB or button, not enclosure.
    func queryFobInteractableAtNormalized(nx: CGFloat, ny: CGFloat, completion: @escaping (Bool) -> Void) {
        guard let wv = webView else {
            DispatchQueue.main.async { completion(false) }
            return
        }
        let nxD = Double(nx)
        let nyD = Double(ny)
        let js = "(typeof window.fobInteractableAtNormalized==='function')?!!window.fobInteractableAtNormalized(\(nxD),\(nyD)):false"
        wv.evaluateJavaScript(js) { result, _ in
            let ok: Bool
            if let b = result as? Bool {
                ok = b
            } else if let n = result as? NSNumber {
                ok = n.boolValue
            } else {
                ok = false
            }
            DispatchQueue.main.async {
                completion(ok)
            }
        }
    }
}

// MARK: – FobViewer

/// Embedded Three.js fob viewer backed by WKWebView.
struct FobViewer: UIViewRepresentable {

    // ── LED ────────────────────────────────────────────────────
    /// Trigger a one-shot LED animation. The viewer fires the matching
    /// JS animation function only when `ledCommand.id` changes.
    var ledCommand: LedCommand = .idle

    // ── Button actuation ───────────────────────────────────────
    var buttonDepth: Double = 0.0

    // ── Model transform ────────────────────────────────────────
    var modelPosition: SIMD3<Float> = .zero
    var modelScale: Float = 1.0
    var modelRotation: SIMD3<Float> = .zero

    // ── Camera controller (JS bridge for pan / zoom) ────────────
    fileprivate var cameraController: CameraController?

    /// Onboarding recovery sheet: transparent chrome + looping triple-press + rainbow LED (viewer.html).
    var recoverySheetDemoLoop: Bool = false

    // MARK: Coordinator

    /// Holds the latest FobViewer value and listens for the JS `modelReady`
    /// message so it can push the initial LED / button state after the GLB loads.
    class Coordinator: NSObject, WKScriptMessageHandler {
        var parent: FobViewer
        weak var webView: WKWebView?
        /// Last command id pushed to JS; prevents re-firing on unrelated SwiftUI updates.
        var lastLedCommandId: Int = -1
        var lastRecoveryDemoPushed: Bool?

        init(_ parent: FobViewer) { self.parent = parent }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            switch message.name {
            case "modelReady":
                guard let wv = webView else { return }
                // Reset so the current command fires again after a page reload.
                lastLedCommandId = -1
                // Recovery demo JS is defined at end of module; first updateUIView often runs before it exists.
                // Clear the latch so applyState re-sends chrome + start now that WK is ready.
                if parent.recoverySheetDemoLoop {
                    lastRecoveryDemoPushed = nil
                }
                parent.applyState(to: wv, coordinator: self)
            default:
                break
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    // MARK: UIViewRepresentable

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(LocalSchemeHandler(), forURLScheme: "local")
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.preferences.setValue(true, forKey: "allowsPictureInPictureMediaPlayback")
        // Use a weak proxy so WKUserContentController doesn't retain Coordinator forever.
        config.userContentController.add(
            WeakScriptHandler(context.coordinator), name: "modelReady")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque                   = false
        webView.backgroundColor            = .clear
        webView.underPageBackgroundColor   = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isOpaque        = false
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces         = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never

        context.coordinator.webView = webView
        cameraController?.webView   = webView
        loadViewer(in: webView)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        // Keep coordinator up-to-date so modelReady replay uses current values.
        context.coordinator.parent = self
        applyState(to: webView, coordinator: context.coordinator)
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController
            .removeScriptMessageHandler(forName: "modelReady")
    }

    // MARK: – Apply state

    /// Pushes button-depth and model-transform every update; fires the LED
    /// JS command only when `ledCommand.id` has changed (prevents cancelling
    /// an in-progress animation on unrelated SwiftUI re-renders).
    func applyState(to webView: WKWebView, coordinator: Coordinator) {
        if coordinator.lastRecoveryDemoPushed != recoverySheetDemoLoop {
            coordinator.lastRecoveryDemoPushed = recoverySheetDemoLoop
            if recoverySheetDemoLoop {
                webView.evaluateJavaScript(
                    "if(window.setRecoveryDemoChrome)window.setRecoveryDemoChrome(true);"
                    + "if(window.startRecoveryTriplePressDemo)window.startRecoveryTriplePressDemo();",
                    completionHandler: nil)
            } else {
                webView.evaluateJavaScript(
                    "if(window.stopRecoveryTriplePressDemo)window.stopRecoveryTriplePressDemo();"
                    + "if(window.setRecoveryDemoChrome)window.setRecoveryDemoChrome(false);",
                    completionHandler: nil)
            }
        }

        // ── LED + button depth (recovery demo drives these from JS) ───────────
        if !recoverySheetDemoLoop {
            if ledCommand.id != coordinator.lastLedCommandId {
                coordinator.lastLedCommandId = ledCommand.id
                let js: String
                switch ledCommand.kind {
                case .unlock:      js = "if(window.playLedUnlock)  window.playLedUnlock();"
                case .lock:        js = "if(window.playLedLock)    window.playLedLock();"
                case .window:      js = "if(window.playLedWindow)  window.playLedWindow();"
                case .prov:        js = "if(window.startLedProv)   window.startLedProv();"
                case .lowBatUnlock: js = "if(window.playLedLowBat) window.playLedLowBat(0,255,0);"
                case .lowBatLock:   js = "if(window.playLedLowBat) window.playLedLowBat(255,0,0);"
                case .off:         js = "if(window.stopLedAnim)    window.stopLedAnim();"
                }
                webView.evaluateJavaScript(js, completionHandler: nil)
            }

            webView.evaluateJavaScript(
                "if (window.setButtonDepth) window.setButtonDepth(\(buttonDepth));",
                completionHandler: nil)
        }

        let p = modelPosition
        let rot = modelRotation
        webView.evaluateJavaScript(
            "if (window.setModelTransform) window.setModelTransform(\(p.x), \(p.y), \(p.z), \(modelScale), \(rot.x), \(rot.y), \(rot.z));",
            completionHandler: nil)
    }

    // MARK: – Private helpers

    private func loadViewer(in webView: WKWebView) {
        // Load via the local:// custom scheme so that ES module imports
        // (e.g. './materials.js') resolve to local://app/… and are served by
        // LocalSchemeHandler with CORS headers.  loadFileURL blocks cross-file
        // ES module imports in modern WebKit; the custom scheme avoids that.
        // #pipitRecovery: clean sheet embed. #pipitFps: FPS HUD (see viewer.html boot script).
        let urlString = recoverySheetDemoLoop
            ? "local://app/viewer.html#pipitRecovery-pipitFps"
            : "local://app/viewer.html#pipitFps"
        guard let url = URL(string: urlString) else { return }
        webView.load(URLRequest(url: url))
    }
}

extension FobViewer {
    /// Onboarding recovery sheet: non-interactive triple-press + rainbow demo.
    /// `cameraController` is `fileprivate`, so the synthesized memberwise `init` is not visible outside this file; use this factory from other Swift files.
    static func recoverySheetDemo() -> FobViewer {
        FobViewer(
            ledCommand: .idle,
            buttonDepth: 0,
            modelPosition: .zero,
            modelScale: 1.0,
            modelRotation: .zero,
            cameraController: nil,
            recoverySheetDemoLoop: true
        )
    }
}

// MARK: – Recovery sheet: pooled WKWebView (prewarm on camera, attach in sheet)

/// Single shared `WKWebView` for onboarding recovery: loads `Uguisu` off-screen while the QR camera is visible,
/// then moves into the sheet and starts the triple-press demo only when the sheet is shown.
final class RecoveryFobWebViewPool: ObservableObject {
    private static let uguisuDisplayScale: Double = 1.4
    /// Optional pivot-space X tweak (viewer also auto-centres the projected bbox horizontally).
    private static let uguisuPivotOffsetX: Double = -0.00

    @Published private(set) var isModelReady = false

    private let scriptCoordinator = RecoveryFobPoolCoordinator()
    private var _webView: WKWebView?

    /// True while the recovery bottom sheet is on-screen (user should see the demo).
    private var recoverySheetPresented = false
    private var demoRunning = false

    init() {
        scriptCoordinator.pool = self
    }

    /// Touch the web view so GLB loading begins before the sheet opens.
    func ensureWebViewCreated() {
        _ = webView
    }

    var webView: WKWebView {
        if let w = _webView { return w }

        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(LocalSchemeHandler(), forURLScheme: "local")
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.preferences.setValue(true, forKey: "allowsPictureInPictureMediaPlayback")
        config.userContentController.add(
            WeakRecoveryPoolScriptHandler(scriptCoordinator), name: "modelReady")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.underPageBackgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isOpaque = false
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never

        scriptCoordinator.webView = webView
        _webView = webView

        if let url = URL(string: "local://app/viewer.html#pipitRecovery-pipitFps") {
            webView.load(URLRequest(url: url))
        }
        return webView
    }

    func attach(to container: UIView) {
        let wv = webView
        if wv.superview === container { return }
        wv.removeFromSuperview()
        container.addSubview(wv)
        wv.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            wv.topAnchor.constraint(equalTo: container.topAnchor),
            wv.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            wv.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            wv.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        let s = Self.uguisuDisplayScale
        let ox = Self.uguisuPivotOffsetX
        wv.evaluateJavaScript(
            "if(window.setModelTransform)window.setModelTransform(\(ox),0,0,\(s),0,0,0);",
            completionHandler: nil)
    }

    @MainActor
    fileprivate func handleModelReady() {
        let s = Self.uguisuDisplayScale
        let ox = Self.uguisuPivotOffsetX
        webView.evaluateJavaScript(
            "if(window.setModelTransform)window.setModelTransform(\(ox),0,0,\(s),0,0,0);",
            completionHandler: nil)
        isModelReady = true
        tryStartRecoveryDemo()
    }

    @MainActor
    func recoverySheetBecamePresented(_ presented: Bool) {
        recoverySheetPresented = presented
        if presented {
            tryStartRecoveryDemo()
        } else {
            stopRecoveryDemo()
        }
    }

    @MainActor
    private func tryStartRecoveryDemo() {
        guard recoverySheetPresented, isModelReady, !demoRunning else { return }
        demoRunning = true
        webView.evaluateJavaScript(
            "if(window.setRecoveryDemoChrome)window.setRecoveryDemoChrome(true);"
                + "if(window.startRecoveryTriplePressDemo)window.startRecoveryTriplePressDemo();",
            completionHandler: nil)
    }

    @MainActor
    private func stopRecoveryDemo() {
        demoRunning = false
        webView.evaluateJavaScript(
            "if(window.stopRecoveryTriplePressDemo)window.stopRecoveryTriplePressDemo();"
                + "if(window.setRecoveryDemoChrome)window.setRecoveryDemoChrome(false);",
            completionHandler: nil)
    }
}

private final class RecoveryFobPoolCoordinator: NSObject, WKScriptMessageHandler {
    weak var pool: RecoveryFobWebViewPool?
    weak var webView: WKWebView?

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard message.name == "modelReady" else { return }
        Task { @MainActor in
            pool?.handleModelReady()
        }
    }
}

private final class WeakRecoveryPoolScriptHandler: NSObject, WKScriptMessageHandler {
    private weak var target: RecoveryFobPoolCoordinator?
    init(_ target: RecoveryFobPoolCoordinator) { self.target = target }
    func userContentController(
        _ uc: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        target?.userContentController(uc, didReceive: message)
    }
}

/// Hosts the pooled recovery `WKWebView` in a `UIView` subtree (prewarm container or sheet slot).
struct RecoveryFobAnchor: UIViewRepresentable {
    @ObservedObject var pool: RecoveryFobWebViewPool
    var shouldAttach: Bool

    func makeUIView(context: Context) -> UIView {
        let v = UIView()
        v.backgroundColor = .clear
        v.clipsToBounds = true
        return v
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        guard shouldAttach else { return }
        pool.attach(to: uiView)
    }
}

// MARK: – Weak script-handler proxy

/// Breaks the WKUserContentController → Coordinator retain cycle.
private final class WeakScriptHandler: NSObject, WKScriptMessageHandler {
    private weak var target: FobViewer.Coordinator?
    init(_ target: FobViewer.Coordinator) { self.target = target }
    func userContentController(
        _ uc: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        target?.userContentController(uc, didReceive: message)
    }
}

// MARK: - FobInteractiveViewer

/// A SwiftUI wrapper around FobViewer that adds tap and long-press gestures,
/// animates button depression, and triggers firmware-matching LED animations.
///
/// Tap detection mirrors the Uguisu firmware wait_for_button_command logic:
///   - After each tap release, a 400 ms inter-click window opens (UGUISU_MULTI_CLICK_WINDOW_MS).
///   - If no follow-up tap arrives → single tap → Unlock LED + BLE command.
///   - If ≥ 3 taps accumulate before the window expires → Window (rainbow) LED.
///     (2-tap sequences also resolve as Unlock, matching firmware click_count < 3 behaviour.)
///   - Long press is detected during hold (no inter-click delay needed) → Lock LED + BLE command.
private let UGUISU_MULTI_CLICK_WINDOW_MS: Double = 0.400

/// At least this many points from the bottom are excluded for orbit (covers home indicator even if insets are odd).
private let fobOrbitHomeZoneMinHeightPt: CGFloat = 56
/// Padding added to `safeAreaInsets.bottom` when computing the excluded bottom band.
private let fobOrbitHomeZoneExtraMarginPt: CGFloat = 32
/// Orbit only after this drag distance — reduces spurious pans before the system takes the home gesture.
private let fobOrbitMinimumDragPt: CGFloat = 24

private enum FobInteractHaptics {
    static let pressDown = UIImpactFeedbackGenerator(style: .light)
}

struct FobInteractiveViewer: View {
    var onTap: () -> Void
    var onLongPress: () -> Void

    @State private var isPressed: Bool = false
    @State private var ledCommand: LedCommand = .idle
    @State private var cmdCounter: Int = 0

    // Running tap accumulator and the debounce work-item.
    @State private var pendingTapCount: Int = 0
    @State private var tapDebounceItem: DispatchWorkItem?

    // Set to true when a long press fires (while finger is still down) so that
    // the TapGesture.onEnded that fires on the subsequent finger-lift is ignored.
    @State private var longPressFired: Bool = false

    // True when the front-most surface under the touch (Three.js raycast) is PCB or button.
    @State private var inButtonZone: Bool = false

    /// Bumps on each new finger-down (first drag event) so stale WK hit-test completions are ignored.
    @State private var touchGeneration: UInt = 0
    @State private var sentSurfaceHitTestForDrag: Bool = false
    @State private var surfaceHitTestInFlight: Bool = false
    /// Normalized tap origin for a second raycast at tap-up (fast taps may finish before the first WK callback).
    @State private var dragStartNormalized: (x: CGFloat, y: CGFloat)? = nil

    // Camera orbit / zoom — driven by SwiftUI gestures, forwarded to JS.
    @State private var cameraController      = CameraController()
    @State private var lastOrbitTranslation: CGSize = .zero
    @State private var lastMagScale: CGFloat         = 1.0
    @State private var isPanning: Bool               = false
    @State private var orbitSuppressed: Bool         = false

    var body: some View {
        GeometryReader { geo in
        FobViewer(
            ledCommand: ledCommand,
            buttonDepth: isPressed ? 1.0 : 0.0,
            modelPosition: .zero,
            modelScale: 1.0,
            modelRotation: .zero,
            cameraController: cameraController
        )
        // A transparent overlay to capture touch events over the WebView
        .overlay(
            Color.white.opacity(0.001)
                // DragGesture(minimumDistance: 0) is the authoritative isPressed source:
                // onChanged fires immediately on finger-down; onEnded fires on finger-lift.
                // This keeps the button visually depressed for the full duration of the hold,
                // whether a tap or long-press, and releases only when the finger leaves.
                .simultaneousGesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            if !sentSurfaceHitTestForDrag && !isPanning {
                                sentSurfaceHitTestForDrag = true
                                touchGeneration &+= 1
                                let tg = touchGeneration
                                surfaceHitTestInFlight = true
                                inButtonZone = false
                                isPressed = false
                                FobInteractHaptics.pressDown.prepare()
                                let s = value.startLocation
                                let nx = s.x / max(geo.size.width, 1)
                                let ny = s.y / max(geo.size.height, 1)
                                dragStartNormalized = (nx, ny)
                                cameraController.queryFobInteractableAtNormalized(nx: nx, ny: ny) { ok in
                                    surfaceHitTestInFlight = false
                                    guard tg == touchGeneration else { return }
                                    inButtonZone = ok
                                    if ok, !isPanning {
                                        FobInteractHaptics.pressDown.impactOccurred()
                                        withAnimation(.easeOut(duration: 0.08)) { isPressed = true }
                                    }
                                }
                            } else if inButtonZone, !isPanning {
                                withAnimation(.easeOut(duration: 0.08)) { isPressed = true }
                            }
                        }
                        .onEnded { _ in
                            sentSurfaceHitTestForDrag = false
                            surfaceHitTestInFlight = false
                            withAnimation(.easeIn(duration: 0.15)) { isPressed = false }
                            // Defer flag resets so TapGesture.onEnded (same lift) runs first.
                            DispatchQueue.main.async {
                                longPressFired = false
                                isPanning      = false
                                inButtonZone   = false
                            }
                        }
                )
                .gesture(
                    LongPressGesture(minimumDuration: 0.5)
                        .onChanged { _ in
                            // isPressed is managed by DragGesture; nothing to do here.
                        }
                        .onEnded { _ in
                            guard inButtonZone && !isPanning else { return }
                            // Long press confirmed — now cancel any pending tap decision.
                            tapDebounceItem?.cancel()
                            tapDebounceItem = nil
                            pendingTapCount = 0
                            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                            longPressFired = true
                            cmdCounter += 1
                            ledCommand = LedCommand(kind: .lock, id: cmdCounter)
                            // isPressed stays true until DragGesture.onEnded (finger-lift).
                            onLongPress()
                        }
                )
                .simultaneousGesture(
                    TapGesture()
                        .onEnded {
                            guard !longPressFired, !isPanning else { return }
                            guard let o = dragStartNormalized else { return }
                            let tg = touchGeneration
                            cameraController.queryFobInteractableAtNormalized(nx: o.x, ny: o.y) { ok in
                                guard ok, tg == touchGeneration else { return }
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()

                                pendingTapCount += 1
                                let capturedCount = pendingTapCount

                                tapDebounceItem?.cancel()
                                let item = DispatchWorkItem {
                                    pendingTapCount = 0
                                    cmdCounter += 1
                                    if capturedCount >= 3 {
                                        ledCommand = LedCommand(kind: .window, id: cmdCounter)
                                    } else {
                                        ledCommand = LedCommand(kind: .unlock, id: cmdCounter)
                                        onTap()
                                    }
                                }
                                tapDebounceItem = item
                                DispatchQueue.main.asyncAfter(
                                    deadline: .now() + UGUISU_MULTI_CLICK_WINDOW_MS, execute: item)
                            }
                        }
                )
                // ── Orbit: drag past threshold rotates camera around the model. ─────────
                // Suppressed when the gesture's start location is within the
                // projected button mesh region to avoid accidental orbit
                // when the user is trying to tap or long-press the button.
                // Also suppressed when the drag starts in a wide bottom band (home / app switcher).
                // Upward, mostly-vertical drags starting just above that band are treated as the same
                // (finger often lands slightly above the home indicator).
                .simultaneousGesture(
                    DragGesture(minimumDistance: fobOrbitMinimumDragPt)
                        .onChanged { value in
                            let bottomBand = max(
                                geo.safeAreaInsets.bottom + fobOrbitHomeZoneExtraMarginPt,
                                fobOrbitHomeZoneMinHeightPt)
                            let homeBandTopY = geo.size.height - bottomBand
                            let startedInHomeZone = value.startLocation.y >= homeBandTopY
                            let t = value.translation
                            let upward = t.height < -12
                            let verticalDominant = abs(t.height) > abs(t.width) * 1.2
                            let extendedBottomTopY = geo.size.height - (bottomBand + 56)
                            let likelyHomeSwipe = upward && verticalDominant
                                && value.startLocation.y >= extendedBottomTopY
                            if !isPanning {
                                // Wait for raycast before orbiting from PCB area; enclosure stays orbit-able.
                                orbitSuppressed = inButtonZone || surfaceHitTestInFlight
                                    || startedInHomeZone || likelyHomeSwipe
                                if !orbitSuppressed {
                                    withAnimation(.easeIn(duration: 0.1)) { isPressed = false }
                                }
                            }
                            guard !orbitSuppressed else { return }
                            isPanning = true
                            let rawDX = value.translation.width  - lastOrbitTranslation.width
                            let rawDY = value.translation.height - lastOrbitTranslation.height
                            lastOrbitTranslation = value.translation
                            let sensitivity: CGFloat = 0.006
                            // Negate so drag direction matches intuitive finger-follows-model feel.
                            cameraController.orbit(dTheta: -rawDX * sensitivity,
                                                   dPhi:   -rawDY * sensitivity)
                        }
                        .onEnded { _ in
                            cameraController.flushCameraGesturesImmediately()
                            lastOrbitTranslation = .zero
                            orbitSuppressed = false
                            isPanning = false
                        }
                )
                // ── Pinch: two-finger scale zooms the Three.js camera in / out. ───────
                .simultaneousGesture(
                    MagnificationGesture()
                        .onChanged { scale in
                            let delta = scale / lastMagScale
                            lastMagScale = scale
                            cameraController.zoom(factor: delta)
                        }
                        .onEnded { _ in
                            cameraController.flushCameraGesturesImmediately()
                            lastMagScale = 1.0
                        }
                )
        )
        } // GeometryReader
    }
}


