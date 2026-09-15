import UIKit
import WebKit

/// Forwards script messages to a weak target, so a `WKUserContentController` holding this proxy does
/// not keep the controller itself alive — `add(_:name:)` retains its handler strongly.
class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?

    init(target: WKScriptMessageHandler) {
        self.target = target
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(userContentController, didReceive: message)
    }
}

/// A ``CaptchaController`` whose provider mints its token in a web page: shows a `WKWebView` for the
/// duration of the challenge and takes the token from the `captcha` script message. A subclass only
/// supplies how it loads its widget into that web view.
class CaptchaWidgetController: CaptchaController, WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate {
    static let messageHandlerName = "captcha"

    private(set) var webView: WKWebView!

    override func viewDidLoad() {
        super.viewDidLoad()
        setupWebView()
    }

    private func setupWebView() {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(WeakScriptMessageHandler(target: self), name: Self.messageHandlerName)

        let webView = WKWebView(frame: .zero, configuration: configuration)
        self.webView = webView
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.translatesAutoresizingMaskIntoConstraints = false
        captchaView.webViewContainer.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: captchaView.webViewContainer.topAnchor),
            webView.leadingAnchor.constraint(equalTo: captchaView.webViewContainer.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: captchaView.webViewContainer.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: captchaView.webViewContainer.bottomAnchor),
        ])
    }

    override func obtain(siteKey: String, action: String) {
        captchaView.webViewContainer.isHidden = false
        load(siteKey: siteKey, action: action, into: webView)
    }

    /// Loads the provider's widget into `webView` for `siteKey`, using `action` if the provider takes
    /// one. Called on the main thread, right after `webView` is shown.
    func load(siteKey: String, action: String, into webView: WKWebView) {
        fatalError("override load(siteKey:action:into:)")
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == Self.messageHandlerName, let body = message.body as? String else { return }

        let errorPrefix = "error: "
        if body.hasPrefix(errorPrefix) {
            deliver(error: String(body.dropFirst(errorPrefix.count)))
        } else {
            deliver(token: body)
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        deliver(error: "page load failed: \(error.localizedDescription)")
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        deliver(error: "page load failed: \(error.localizedDescription)")
    }

    // Without a `WKUIDelegate`, a page calling `alert`/`confirm`/`prompt` blocks its JS thread forever —
    // nothing ever calls the completion handler. A captcha vendor's script can do exactly that on an
    // error it otherwise has no visible surface to report (v3 has no widget UI), so these just dismiss
    // immediately rather than actually presenting anything.
    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        completionHandler()
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        completionHandler(false)
    }

    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
        completionHandler(nil)
    }
}
