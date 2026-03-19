import SwiftUI
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

    // MARK: Coordinator

    /// Holds the latest FobViewer value and listens for the JS `modelReady`
    /// message so it can push the initial LED / button state after the GLB loads.
    class Coordinator: NSObject, WKScriptMessageHandler {
        var parent: FobViewer
        weak var webView: WKWebView?
        /// Last command id pushed to JS; prevents re-firing on unrelated SwiftUI updates.
        var lastLedCommandId: Int = -1

        init(_ parent: FobViewer) { self.parent = parent }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard message.name == "modelReady", let wv = webView else { return }
            // Reset so the current command fires again after a page reload.
            lastLedCommandId = -1
            parent.applyState(to: wv, coordinator: self)
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
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces         = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never

        context.coordinator.webView = webView
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
        // ── LED (fire only on new command id) ─────────────────────────────────
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
        guard let url = URL(string: "local://app/viewer.html") else { return }
        webView.load(URLRequest(url: url))
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

    var body: some View {
        FobViewer(
            ledCommand: ledCommand,
            buttonDepth: isPressed ? 1.0 : 0.0,
            modelPosition: .zero,
            modelScale: 1.0,
            modelRotation: .zero
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
                        .onChanged { _ in
                            withAnimation(.easeOut(duration: 0.08)) { isPressed = true }
                        }
                        .onEnded { _ in
                            withAnimation(.easeIn(duration: 0.15)) { isPressed = false }
                            // Defer the flag reset so TapGesture.onEnded (which may fire on
                            // the same lift) sees longPressFired = true and suppresses the
                            // spurious post-long-press tap before the flag is cleared.
                            DispatchQueue.main.async { longPressFired = false }
                        }
                )
                .gesture(
                    LongPressGesture(minimumDuration: 0.5)
                        .onChanged { _ in
                            // isPressed is managed by DragGesture; nothing to do here.
                        }
                        .onEnded { _ in
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
                            // If a long press already fired this touch, swallow the
                            // spurious finger-lift tap. The flag is cleared by DragGesture.onEnded.
                            guard !longPressFired else { return }
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            // isPressed is driven by DragGesture; no manual flash needed.

                            // Accumulate tap count and restart the 400 ms decision window,
                            // mirroring firmware multi_click_deadline behaviour.
                            pendingTapCount += 1
                            let capturedCount = pendingTapCount

                            tapDebounceItem?.cancel()
                            let item = DispatchWorkItem {
                                pendingTapCount = 0
                                cmdCounter += 1
                                if capturedCount >= 3 {
                                    // Triple-press → Window (rainbow sweep)
                                    ledCommand = LedCommand(kind: .window, id: cmdCounter)
                                } else {
                                    // Single or double tap → Unlock
                                    ledCommand = LedCommand(kind: .unlock, id: cmdCounter)
                                    onTap()
                                }
                            }
                            tapDebounceItem = item
                            DispatchQueue.main.asyncAfter(
                                deadline: .now() + UGUISU_MULTI_CLICK_WINDOW_MS, execute: item)
                        }
                )
        )
    }
}


