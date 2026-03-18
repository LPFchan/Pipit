import WebKit
import Foundation

class LocalSchemeHandler: NSObject, WKURLSchemeHandler {
    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url else { return }
        
        let fileName = url.lastPathComponent
        let ext = (fileName as NSString).pathExtension
        let name = (fileName as NSString).deletingPathExtension
        
        let bundle = Bundle.main
        guard let fileURL = bundle.url(forResource: name, withExtension: ext) else {
            NSLog("LocalSchemeHandler Error: File not found in bundle! name: \(name), ext: \(ext)")
            urlSchemeTask.didFailWithError(NSError(domain: "LocalSchemeHandler", code: 404, userInfo: nil))
            return
        }
        
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
