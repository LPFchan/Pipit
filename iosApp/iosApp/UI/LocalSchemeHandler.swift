import WebKit
import Foundation

class LocalSchemeHandler: NSObject, WKURLSchemeHandler {
    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url else { return }

        let bundle = Bundle.main
        guard let resourceBaseURL = bundle.resourceURL else {
            urlSchemeTask.didFailWithError(NSError(domain: "LocalSchemeHandler", code: 500, userInfo: nil))
            return
        }

        // Resolve by full URL path so subdirectory assets (e.g. three-addons/controls/OrbitControls.js) work.
        let relativePath = url.path.hasPrefix("/") ? String(url.path.dropFirst()) : url.path
        let fileURL = resourceBaseURL.appendingPathComponent(relativePath)

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            NSLog("LocalSchemeHandler Error: File not found in bundle! path: \(relativePath)")
            urlSchemeTask.didFailWithError(NSError(domain: "LocalSchemeHandler", code: 404, userInfo: nil))
            return
        }

        let ext = fileURL.pathExtension
        
        do {
            let data = try Data(contentsOf: fileURL)
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: [
                "Content-Type": contentType(for: ext),
                "Access-Control-Allow-Origin": "*"
            ])!
            urlSchemeTask.didReceive(response)
            urlSchemeTask.didReceive(data)
            urlSchemeTask.didFinish()
        } catch {
            NSLog("LocalSchemeHandler Error: Failed to read file data: \(error)")
            urlSchemeTask.didFailWithError(error)
        }
    }
    
    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
        // Nothing to do for stopping
    }
    
    private func contentType(for ext: String) -> String {
        switch ext.lowercased() {
        case "html": return "text/html"
        case "js": return "application/javascript"
        case "css": return "text/css"
        case "glb": return "model/gltf-binary"
        case "gltf": return "model/gltf+json"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "json": return "application/json"
        default: return "application/octet-stream"
        }
    }
}
