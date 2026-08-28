import Reach5
import UIKit
import WebKit

/// Forwards script messages to a weak target, so a `WKUserContentController` holding this proxy does
/// not keep the controller itself alive — `add(_:name:)` retains its handler strongly.
private class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?

    init(target: WKScriptMessageHandler) {
        self.target = target
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(userContentController, didReceive: message)
    }
}

/// Demo page for CaptchaFox: renders the real widget in a `WKWebView` and writes the resulting token
/// to `CaptchaStore`. The widget is shown, not hidden, because this is a page meant to be watched.
class CaptchaFoxController: UIViewController, WKScriptMessageHandler {
    private static let siteKeyDefaultsKey = "captchaFoxSiteKey"
    private static let messageHandlerName = "captcha"
    private static let actions = ["login", "signup", "update_email", "passwordless_email", "passwordless_phone", "account_recovery", "password_reset_requested"]

    private var captchaView: CaptchaView!
    private var webView: WKWebView!

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "CaptchaFox"
        view.backgroundColor = .systemBackground

        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        guard let captchaView = CaptchaView.create() else { return }
        self.captchaView = captchaView
        captchaView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(captchaView)
        NSLayoutConstraint.activate([
            captchaView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            captchaView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            captchaView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            captchaView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            captchaView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
        ])

        setupWebView()
        setupActionSegments()

        captchaView.siteKeyField.text = UserDefaults.standard.string(forKey: Self.siteKeyDefaultsKey)
        captchaView.obtainButton.addTarget(self, action: #selector(obtainTapped), for: .touchUpInside)
        captchaView.copyButton.addTarget(self, action: #selector(copyTapped), for: .touchUpInside)
        captchaView.webViewContainer.isHidden = true
    }

    private func setupWebView() {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(WeakScriptMessageHandler(target: self), name: Self.messageHandlerName)

        let webView = WKWebView(frame: .zero, configuration: configuration)
        self.webView = webView
        webView.translatesAutoresizingMaskIntoConstraints = false
        captchaView.webViewContainer.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: captchaView.webViewContainer.topAnchor),
            webView.leadingAnchor.constraint(equalTo: captchaView.webViewContainer.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: captchaView.webViewContainer.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: captchaView.webViewContainer.bottomAnchor),
        ])
    }

    private func setupActionSegments() {
        captchaView.actionSegmentedControl.removeAllSegments()
        for (index, action) in Self.actions.enumerated() {
            captchaView.actionSegmentedControl.insertSegment(withTitle: action, at: index, animated: false)
        }
        captchaView.actionSegmentedControl.selectedSegmentIndex = 0
    }

    private var selectedAction: String {
        let index = captchaView.actionSegmentedControl.selectedSegmentIndex
        return index >= 0 ? Self.actions[index] : Self.actions[0]
    }

    @objc private func obtainTapped() {
        guard let siteKey = captchaView.siteKeyField.text, !siteKey.isEmpty else {
            presentAlert(title: "Site key missing", message: "Enter a CaptchaFox site key first.")
            return
        }
        UserDefaults.standard.set(siteKey, forKey: Self.siteKeyDefaultsKey)

        captchaView.webViewContainer.isHidden = false
        webView.loadHTMLString(Self.html(siteKey: siteKey), baseURL: nil)
    }

    @objc private func copyTapped() {
        guard let token = CaptchaStore.peek()?.token else { return }
        UIPasteboard.general.string = token

        let originalText = captchaView.tokenLabel.text
        captchaView.tokenLabel.text = "Copied!"
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.captchaView.tokenLabel.text = originalText
        }
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == Self.messageHandlerName, let token = message.body as? String else { return }

        CaptchaStore.entry = CaptchaStore.Entry(
            token: token,
            provider: CaptchaProvider.captchaFox.rawValue,
            action: selectedAction,
            obtainedAt: Date()
        )

        let truncated = token.count > 24 ? "\(token.prefix(24))…" : token
        captchaView.tokenLabel.text = truncated
        captchaView.webViewContainer.isHidden = true
    }

    private static func html(siteKey: String) -> String {
        """
        <!doctype html>
        <html>
        <head>
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <script src="https://cdn.captchafox.com/api.js" async defer></script>
        <style>body { margin: 0; padding-top: 16px; display: flex; justify-content: center; font-family: -apple-system; }</style>
        </head>
        <body>
        <div id="captcha-container"></div>
        <script>
        function initCaptchaFox() {
            if (typeof captchafox === "undefined") { setTimeout(initCaptchaFox, 50); return; }
            captchafox.render(document.getElementById("captcha-container"), {
                sitekey: "\(siteKey)",
                mode: "inline",
                onVerify: function (token) {
                    window.webkit.messageHandlers.captcha.postMessage(token);
                }
            });
        }
        initCaptchaFox();
        </script>
        </body>
        </html>
        """
    }
}
