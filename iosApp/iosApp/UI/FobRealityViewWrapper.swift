import SwiftUI
import WebKit

// MARK: – FobViewer

/// Embedded Three.js fob viewer backed by WKWebView.
struct FobViewer: UIViewRepresentable {

    // ── LED ────────────────────────────────────────────────────
    var ledColor: Color
    var isActive: Bool
    var ledBrightness: Double = 1.0

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

        init(_ parent: FobViewer) { self.parent = parent }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard message.name == "modelReady", let wv = webView else { return }
            parent.applyState(to: wv)
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
        applyState(to: webView)
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController
            .removeScriptMessageHandler(forName: "modelReady")
    }

    // MARK: – Apply state

    /// Pushes the current LED, button-depth, and model-transform into the WebView.
    /// Safe to call before the page has loaded — the JS guards with `if (window.setX)`.
    /// The meaningful call happens via Coordinator.userContentController after `modelReady`.
    func applyState(to webView: WKWebView) {
        let (r, g, b) = ledColor.rgbComponents
        let active    = isActive ? "true" : "false"

        webView.evaluateJavaScript(
            "if (window.setLedState) window.setLedState(\(r), \(g), \(b), \(active), \(ledBrightness));",
            completionHandler: nil)
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
        guard let url = Bundle.main.url(forResource: "viewer", withExtension: "html") else {
            assertionFailure(
                "[FobViewer] viewer.html not found in bundle. " +
                "Add iosApp/iosApp/Resources/viewer.html to Xcode's " +
                "Copy Bundle Resources build phase.")
            return
        }
        let resourceDir = url.deletingLastPathComponent()
        webView.loadFileURL(url, allowingReadAccessTo: resourceDir)
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

// MARK: – Color helpers

private extension Color {
    /// Extracts (r, g, b) as integers in [0, 255].
    var rgbComponents: (Int, Int, Int) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        return (Int(r * 255), Int(g * 255), Int(b * 255))
    }
}

// MARK: - FobInteractiveViewer

/// A SwiftUI wrapper around FobViewer that adds tap and long-press gestures
/// and animates the button depression.
struct FobInteractiveViewer: View {
    var onTap: () -> Void
    var onLongPress: () -> Void

    @State private var isPressed: Bool = false

    var body: some View {
        FobViewer(
            ledColor: .green,
            isActive: true,
            ledBrightness: 1.0,
            buttonDepth: isPressed ? 1.0 : 0.0,
            modelPosition: .zero,
            modelScale: 1.0,
            modelRotation: .zero
        )
        // A transparent overlay to capture touch events over the WebView
        .overlay(
            Color.white.opacity(0.001)
                .gesture(
                    LongPressGesture(minimumDuration: 0.5)
                        .onChanged { _ in
                            withAnimation(.easeOut(duration: 0.1)) {
                                isPressed = true
                            }
                        }
                        .onEnded { _ in
                            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                            onLongPress()
                            withAnimation(.easeIn(duration: 0.2)) {
                                isPressed = false
                            }
                        }
                )
                .simultaneousGesture(
                    TapGesture()
                        .onEnded {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            withAnimation(.easeOut(duration: 0.05)) {
                                isPressed = true
                            }
                            onTap()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                withAnimation(.easeIn(duration: 0.1)) {
                                    isPressed = false
                                }
                            }
                        }
                )
        )
    }
}


