import WebKit
import SwiftUI

// MARK: - RecoveryFobWebViewPool

/// Owns a single pre-warmed WKWebView running the Three.js fob viewer so it
/// can be cheaply moved between the parked off-screen prewarm slot and the
/// recovery sheet without reloading the page.
final class RecoveryFobWebViewPool: NSObject, ObservableObject {
    @Published private(set) var isModelReady = false

    private(set) var webView: WKWebView?
    private var scriptHandler: ScriptHandler?

    /// Creates the WKWebView and starts loading viewer.html if not done yet.
    func ensureWebViewCreated() {
        guard webView == nil else { return }

        let handler = ScriptHandler(pool: self)
        scriptHandler = handler

        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(LocalSchemeHandler(), forURLScheme: "local")
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.userContentController.add(WeakMessageHandler(handler), name: "modelReady")

        let wv = WKWebView(frame: .zero, configuration: config)
        wv.isOpaque                             = false
        wv.backgroundColor                      = .clear
        wv.underPageBackgroundColor             = .clear
        wv.scrollView.backgroundColor           = .clear
        wv.scrollView.isScrollEnabled           = false
        wv.scrollView.bounces                   = false
        wv.scrollView.contentInsetAdjustmentBehavior = .never

        webView = wv

        guard let url = URL(string: "local://app/viewer.html") else { return }
        wv.load(URLRequest(url: url))
    }

    /// Called when the recovery sheet appears or disappears.
    func recoverySheetBecamePresented(_ presented: Bool) {
        // Reserved for future use (e.g. pause/resume rendering).
    }

    fileprivate func handleModelReady() {
        DispatchQueue.main.async { self.isModelReady = true }
    }
}

// MARK: - RecoveryFobAnchor

/// A SwiftUI wrapper that places (or removes) the pool's shared WKWebView
/// inside this view's UIKit container depending on `shouldAttach`.
struct RecoveryFobAnchor: UIViewRepresentable {
    let pool: RecoveryFobWebViewPool
    let shouldAttach: Bool

    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        container.backgroundColor = .clear
        return container
    }

    func updateUIView(_ container: UIView, context: Context) {
        guard let webView = pool.webView else { return }

        if shouldAttach {
            guard webView.superview !== container else { return }
            webView.removeFromSuperview()
            container.addSubview(webView)
            webView.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                webView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                webView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                webView.topAnchor.constraint(equalTo: container.topAnchor),
                webView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            ])
        } else {
            if webView.superview === container {
                webView.removeFromSuperview()
            }
        }
    }
}

// MARK: - Private helpers

private final class ScriptHandler: NSObject, WKScriptMessageHandler {
    weak var pool: RecoveryFobWebViewPool?
    init(pool: RecoveryFobWebViewPool) { self.pool = pool }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        if message.name == "modelReady" { pool?.handleModelReady() }
    }
}

/// Breaks the WKUserContentController → ScriptHandler retain cycle.
private final class WeakMessageHandler: NSObject, WKScriptMessageHandler {
    private weak var target: ScriptHandler?
    init(_ target: ScriptHandler) { self.target = target }

    func userContentController(
        _ uc: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        target?.userContentController(uc, didReceive: message)
    }
}
