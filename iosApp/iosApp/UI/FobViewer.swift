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
/// The `.glb` model is loaded by Three.js's GLTFLoader from a path relative
/// to the base URL; for the placeholder phase this load is expected to fail
/// gracefully and the built-in geometry is used instead.
///
/// For fully-offline / production use, bundle Three.js locally and switch to
/// `loadFileURL(_:allowingReadAccessTo:)` — see the inline TODO below.
struct FobViewer: UIViewRepresentable {

    var ledColor: Color
    var isActive: Bool

    // MARK: UIViewRepresentable

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []

        // Allows the page to run requestAnimationFrame / setAnimationLoop
        // while the view is not the foreground focus (e.g. partially scrolled).
        config.preferences.setValue(true, forKey: "allowsPictureInPictureMediaPlayback")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque                         = false
        webView.backgroundColor                  = .clear
        webView.scrollView.backgroundColor       = .clear
        webView.scrollView.isScrollEnabled       = false
        webView.scrollView.bounces               = false

        loadViewer(in: webView)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        let (r, g, b) = ledColor.rgbComponents
        let active    = isActive ? "true" : "false"
        webView.evaluateJavaScript(
            "if (window.setLedState) window.setLedState(\(r), \(g), \(b), \(active));",
            completionHandler: nil
        )
    }

    // MARK: – Private helpers

    private func loadViewer(in webView: WKWebView) {
        guard
            let url  = Bundle.main.url(forResource: "viewer", withExtension: "html"),
            let html = try? String(contentsOf: url, encoding: .utf8)
        else {
            assertionFailure(
                "[FobViewer] viewer.html not found in bundle. " +
                "Add iosApp/iosApp/Resources/viewer.html to Xcode's " +
                "Copy Bundle Resources build phase."
            )
            return
        }

        // Load as string with CDN as baseURL so the importmap can resolve
        // Three.js from cdn.jsdelivr.net even though the document has no
        // network origin of its own.
        //
        // TODO (offline): Replace with the two lines below once Three.js is
        // bundled locally under Resources/vendor/:
        //
        //   let resourceDir = url.deletingLastPathComponent()
        //   webView.loadFileURL(url, allowingReadAccessTo: resourceDir)
        //
        // When using loadFileURL the GLTFLoader can also resolve
        // `./uguisu_placeholder.glb` from the same Resources/ directory.
        let cdnBase = URL(string: "https://cdn.jsdelivr.net")
        webView.loadHTMLString(html, baseURL: cdnBase)
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
