import Reach5
import WebKit

/// Demo page for CaptchaFox: renders the real widget in a `WKWebView` and writes the resulting token
/// to `CaptchaStore`. The widget is shown, not hidden, because this is a page meant to be watched.
class CaptchaFoxController: CaptchaWidgetController {
    override var siteKeyDefaultsKey: String { "captchaFoxSiteKey" }
    override var providerRawValue: String { CaptchaProvider.captchaFox.rawValue }

    /// CaptchaFox has no notion of an action: nothing is sealed into its token, and its widget takes
    /// no such parameter.
    override var usesActions: Bool { false }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "CaptchaFox"
    }

    override func load(siteKey: String, action _: String, into webView: WKWebView) {
        let html = Self.html(siteKey: siteKey)

        // CaptchaFox checks the page's domain against the site configuration and answers
        // `site-not-allowed` otherwise. `loadHTMLString(_:baseURL:)` gives the document no origin at
        // all, which fails that check by construction; a simulated request gives it a real one, to be
        // allowed in the CaptchaFox site configuration like any other domain.
        if #available(iOS 15.0, *), let simulatedOrigin = URL(string: "https://localhost/captcha") {
            webView.loadSimulatedRequest(URLRequest(url: simulatedOrigin), responseHTML: html)
        } else {
            webView.loadHTMLString(html, baseURL: nil)
        }
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
