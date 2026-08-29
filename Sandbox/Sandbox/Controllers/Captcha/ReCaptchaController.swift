import Reach5
import WebKit

/// Demo page for classic reCAPTCHA (a **website** v3 key, not the native SDK's Enterprise one — see
/// `CaptchaProvider.reCaptcha`). v3 is invisible: there is no widget to look at, the token comes back
/// as soon as Google verifies the page's origin.
///
/// That origin is the whole difficulty. `loadHTMLString(_:baseURL:)` gives the document no origin at
/// all, which reCAPTCHA's domain check rejects outright, so this loads the page with
/// `loadSimulatedRequest(_:responseHTML:)` instead: a real `URLRequest` towards `https://localhost/captcha`
/// supplies the origin `localhost`, which reCAPTCHA's console lets a site key allow explicitly, without
/// this page actually hosting anything there.
///
/// **Unresolved**: whether Google's domain check accepts that simulated origin the way it accepts a
/// real one served from that host could not be determined this session — `grecaptcha.execute()` simply
/// never settles (neither resolves nor rejects, no console error either) for a site key Google has
/// never heard of, with or without a real origin behind the page. Testing that question needs an
/// actual registered site key; the `execute()` timeout below only guards against that same silence
/// being mistaken for the page being broken.
///
/// If it turns out Google refuses the simulated origin, the fallback is a page genuinely served from
/// the Sandbox's own domain (`local-sandbox.og4.me` or `integ-qa-fonctionnelle.reach5.net`), added to
/// the key's allowed domains — also the path to recommend to integrators. Last resort only: a test key
/// with "Domain/Package Name Validation" unchecked, which then requires the caller to verify `hostname`
/// server-side — ReachFive's backend does not read it, so that key is for this demo page alone, never
/// for production.
class ReCaptchaController: CaptchaWidgetController {
    override var siteKeyDefaultsKey: String { "recaptchaSiteKey" }
    override var providerRawValue: String { CaptchaProvider.reCaptcha.rawValue }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "reCAPTCHA"
    }

    override func load(siteKey: String, action: String, into webView: WKWebView) {
        let html = Self.html(siteKey: siteKey, action: action)

        if #available(iOS 15.0, *), let simulatedOrigin = URL(string: "https://localhost/captcha") {
            webView.loadSimulatedRequest(URLRequest(url: simulatedOrigin), responseHTML: html)
        } else {
            webView.loadHTMLString(html, baseURL: nil)
        }
    }

    private static func html(siteKey: String, action: String) -> String {
        """
        <!doctype html>
        <html>
        <head>
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <script src="https://www.google.com/recaptcha/api.js?render=\(siteKey)"></script>
        </head>
        <body>
        <script>
        function report(message) {
            window.webkit.messageHandlers.captcha.postMessage('error: ' + message);
        }
        window.onerror = function (message) { report(String(message)); };

        var waitedMs = 0;
        function waitForScript() {
            if (typeof grecaptcha !== "undefined" && grecaptcha.ready) { runChallenge(); return; }
            waitedMs += 100;
            if (waitedMs > 8000) { report('the reCAPTCHA script never loaded'); return; }
            setTimeout(waitForScript, 100);
        }

        function runChallenge() {
            var settled = false;
            setTimeout(function () {
                if (!settled) { report('timed out waiting for a token — see the guide\\'s note on unregistered site keys'); }
            }, 8000);
            try {
                grecaptcha.ready(function () {
                    grecaptcha.execute('\(siteKey)', { action: '\(action)' }).then(function (token) {
                        settled = true;
                        window.webkit.messageHandlers.captcha.postMessage(token);
                    }, function (err) {
                        settled = true;
                        report(String(err));
                    });
                });
            } catch (e) {
                settled = true;
                report(String(e));
            }
        }

        waitForScript();
        </script>
        </body>
        </html>
        """
    }
}
