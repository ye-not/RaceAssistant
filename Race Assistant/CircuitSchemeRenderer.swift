import UIKit
import WebKit
import PDFKit

/// Vector SVG stays vector in the phone viewer; CarPlay receives a display-ready image.
enum CircuitSchemeMarkup {
    static func svg(_ data: Data) -> String? {
        guard var text = String(data: data, encoding: .utf8), text.contains("<svg") else { return nil }
        text = text.replacingOccurrences(of: "filter=\"[^\"]*\"", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "shape-rendering=\"crispEdges\"", with: "shape-rendering=\"geometricPrecision\"")
        text = text.replacingOccurrences(of: "<\\?xml[^>]*\\?>", with: "", options: .regularExpression)
        return text
    }
    static func html(_ data: Data, mime: String, fitViewport: Bool = false) -> String {
        let content: String
        if mime == "image/svg+xml", let svg = svg(data) { content = svg }
        else {
            let safe = ["image/png", "image/jpeg"].contains(mime) ? mime : "image/png"
            content = "<img src=\"data:\(safe);base64,\(data.base64EncodedString())\">"
        }
        let layout = fitViewport
            ? "html,body{width:100%;height:100%;margin:0;background:white}body{display:flex;align-items:center;justify-content:center}svg,img{display:block;width:100%;height:100%;object-fit:contain}"
            : "html,body{margin:0;background:white}svg,img{display:block;width:100%;height:auto}"
        return """
        <html><head><meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=10">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src data:; style-src 'unsafe-inline'">
        <style>\(layout)
        svg *{shape-rendering:geometricPrecision;filter:none!important}</style></head><body>\(content)</body></html>
        """
    }
}

@MainActor
final class CircuitSchemeRenderer: NSObject, WKNavigationDelegate {
    private var view: WKWebView?
    private var continuation: CheckedContinuation<UIImage, Error>?
    private var timeout: Task<Void, Never>?

    enum RenderError: LocalizedError {
        case invalid, timeout
        var errorDescription: String? {
            switch self {
            case .invalid: return "Неподдерживаемая или повреждённая схема"
            case .timeout: return "Схема не загрузилась вовремя. Повторите открытие."
            }
        }
    }
    static func image(data: Data, mime: String) async throws -> UIImage {
        if let image = UIImage(data: data) { return image }
        if mime == "application/pdf", let page = PDFDocument(data: data)?.page(at: 0) {
            return page.thumbnail(of: CGSize(width: 2400, height: 1800), for: .mediaBox)
        }
        guard mime == "image/svg+xml", CircuitSchemeMarkup.svg(data) != nil else { throw RenderError.invalid }
        if let originalURL = Bundle.main.url(forResource: "MRW_GP9", withExtension: "svg"),
           let original = try? Data(contentsOf: originalURL), original == data,
           let pngURL = Bundle.main.url(forResource: "MRW_GP9_CarPlay", withExtension: "png"),
           let image = UIImage(contentsOfFile: pngURL.path) { return image }
        let renderer = CircuitSchemeRenderer()
        return try await renderer.render(data)
    }
    private func render(_ data: Data) async throws -> UIImage {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let config = WKWebViewConfiguration()
            config.defaultWebpagePreferences.allowsContentJavaScript = false
            var height: CGFloat = 900
            if let text = CircuitSchemeMarkup.svg(data),
               let pattern = try? NSRegularExpression(pattern: #"viewBox="\s*[-\d.]+[ ,]+[-\d.]+[ ,]+([\d.]+)[ ,]+([\d.]+)\s*""#),
               let match = pattern.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
               let wr = Range(match.range(at: 1), in: text), let hr = Range(match.range(at: 2), in: text),
               let width = Double(text[wr]), let svgHeight = Double(text[hr]), width > 0, svgHeight > 0 {
                height = min(2400, max(300, 1200 * svgHeight / width))
            }
            let view = WKWebView(frame: CGRect(x: 0, y: 0, width: 1200, height: height), configuration: config)
            view.navigationDelegate = self
            self.view = view
            view.loadHTMLString(CircuitSchemeMarkup.html(data, mime: "image/svg+xml"), baseURL: nil)
            timeout = Task { [weak self] in
                try? await Task.sleep(for: .seconds(15))
                guard !Task.isCancelled else { return }
                self?.finish(.failure(RenderError.timeout))
            }
        }
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let config = WKSnapshotConfiguration()
        config.snapshotWidth = 2400
        webView.takeSnapshot(with: config) { [weak self] image, error in
            if let image { self?.finish(.success(image)) }
            else { self?.finish(.failure(error ?? RenderError.invalid)) }
        }
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { finish(.failure(error)) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { finish(.failure(error)) }
    private func finish(_ result: Result<UIImage, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        timeout?.cancel(); timeout = nil
        view?.navigationDelegate = nil; view?.stopLoading(); view = nil
        continuation.resume(with: result)
    }
}
