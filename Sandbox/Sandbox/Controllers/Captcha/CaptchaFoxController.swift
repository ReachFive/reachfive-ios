import Reach5
import WebKit

/// Demo page for CaptchaFox: renders the real widget in a `WKWebView` and writes the resulting token
/// to `CaptchaStore`. The widget is shown, not hidden, because this is a page meant to be watched.
class CaptchaFoxController: CaptchaWidgetController {
    override var siteKeyDefaultsKey: String { "captchaFoxSiteKey" }
    override var providerRawValue: String { CaptchaProvider.captchaFox.rawValue }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "CaptchaFox"
    }

    override func load(siteKey: String, action: String, into webView: WKWebView) {
        webView.loadHTMLString(Self.html(siteKey: siteKey), baseURL: nil)
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
