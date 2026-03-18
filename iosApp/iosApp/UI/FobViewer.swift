import SwiftUI
import WebKit

// MARK: – FobViewer

/// Embedded Three.js fob viewer backed by WKWebView.
///
/// **Bundle requirement** — `viewer.html` must be present in the app bundle.
/// It is already at `iosApp/iosApp/Resources/viewer.html`; make sure Xcode
/// includes the Resources folder in the "Copy Bundle Resources" build phase
/// (it should be if Resources is already a folder reference in the project).
///
/// **Three.js / CDN** — The viewer loads Three.js from CDN at runtime.
/// This works because `loadHTMLString(_:baseURL:)` is called with a CDN base
/// URL, which lets the importmap ES-module imports resolve over HTTPS.
///
/// For fully-offline / production use, bundle Three.js locally and switch to
/// `loadFileURL(_:allowingReadAccessTo:)` — see the inline TODO below.
struct FobViewer: UIViewRepresentable {

    // ── LED ────────────────────────────────────────────────────
    /// Colour of the LED die.
    var ledColor: Color
    /// Whether the LED is lit at all.
    var isActive: Bool
    /// Perceived brightness, 0.0 (dim) → 1.0 (full). Default: 1.
    var ledBrightness: Double = 1.0

    // ── Button actuation ───────────────────────────────────────
    /// Physical press depth: 0.0 = resting, 1.0 = fully depressed.
    var buttonDepth: Double = 0.0

    // ── Model transform ────────────────────────────────────────
    /// Position offset from centre (metres). Default: (0, 0, 0).
    var modelPosition: SIMD3<Float> = .zero
    /// Uniform scale multiplier. Default: 1 (no change).
    var modelScale: Float = 1.0
    /// Euler rotation angles in radians, XYZ order. Default: (0, 0, 0).
    var modelRotation: SIMD3<Float> = .zero

    // MARK: UIViewRepresentable

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.preferences.setValue(true, forKey: "allowsPictureInPictureMediaPlayback")
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        if #available(iOS 15.4, *) {
            config.preferences.isTextInteractionEnabled = false // Not required but nice
        }

        let userContentController = WKUserContentController()
        let logScript = """
        window.onerror = function(msg, url, line) { window.webkit.messageHandlers.log.postMessage("ERR: " + msg + " at " + url + ":" + line); };
        window.console.log = function(msg) { window.webkit.messageHandlers.log.postMessage("LOG: " + msg); };
        window.console.warn = function(msg) { window.webkit.messageHandlers.log.postMessage("WARN: " + msg); };
        window.console.error = function(msg) { window.webkit.messageHandlers.log.postMessage("ERROR: " + msg); };
        """
        let userScript = WKUserScript(source: logScript, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        userContentController.addUserScript(userScript)
        config.userContentController = userContentController

        let webView = WebLoggerWebView(frame: .zero, configuration: config)
        if #available(iOS 16.4, *) {
            webView.isInspectable = true
        }
        webView.isOpaque                   = false
        webView.backgroundColor            = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces         = false

        loadViewer(in: webView)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        let (r, g, b) = ledColor.rgbComponents
        let active    = isActive ? "true" : "false"

        // LED colour + active + brightness
        webView.evaluateJavaScript(
            "if (window.setLedState) window.setLedState(\(r), \(g), \(b), \(active), \(ledBrightness));",
            completionHandler: nil
        )

        // Button actuation depth
        webView.evaluateJavaScript(
            "if (window.setButtonDepth) window.setButtonDepth(\(buttonDepth));",
            completionHandler: nil
        )

        // Model transform
        let p = modelPosition
        let rot = modelRotation
        webView.evaluateJavaScript(
            "if (window.setModelTransform) window.setModelTransform(\(p.x), \(p.y), \(p.z), \(modelScale), \(rot.x), \(rot.y), \(rot.z));",
            completionHandler: nil
        )
    }

    // MARK: – Private helpers

    private func loadViewer(in webView: WKWebView) {
        guard let url = Bundle.main.url(forResource: "viewer", withExtension: "html") ?? Bundle(for: FobPlaceholderView.self).url(forResource: "viewer", withExtension: "html") else {
            assertionFailure(
                "[FobViewer] viewer.html not found in bundle. " +
                "Add iosApp/iosApp/Resources/viewer.html to Xcode's " +
                "Copy Bundle Resources build phase."
            )
            return
        }

        // Load from the bundle file system so that relative paths (GLB, textures)
        // resolve against the Resources/ directory.
        // allowingReadAccessTo grants the WebView read access to the whole
        // Resources/ folder — Three.js CDN imports still work because WKWebView
        // can make outbound HTTPS requests even from a file:// origin.
        let resourceDir = url.deletingLastPathComponent()
        webView.loadFileURL(url, allowingReadAccessTo: resourceDir)
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
    var isUnlocked: Bool
    var onTap: () -> Void
    var onLongPress: () -> Void

    @State private var isPressed: Bool = false

    var body: some View {
        FobViewer(
            ledColor: isUnlocked ? .green : .blue,
            isActive: true,
            ledBrightness: 1.0,
            buttonDepth: isPressed ? 1.0 : 0.0,
            modelPosition: .zero,
            modelScale: 1.0,
            modelRotation: SIMD3<Float>(0, -0.4, 0)
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



// MARK: - WebLoggerWebView

class WebLoggerWebView: WKWebView, WKScriptMessageHandler {
    init(frame: CGRect, configuration: WKWebViewConfiguration) {
        super.init(frame: frame, configuration: configuration)
        configuration.userContentController.add(self, name: "log")
    }
    required init?(coder: NSCoder) { fatalError() }
    
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        print("[WebView] \(message.body)")
    }
}
