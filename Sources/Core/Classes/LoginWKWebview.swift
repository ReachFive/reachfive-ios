import UIKit
@preconcurrency import WebKit

public class LoginWKWebview: UIView {
    var webView: WKWebView?
    var reachfive: ReachFive?
    var continuation: CheckedContinuation<AuthToken, Error>?
    var pkce: Pkce?

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    /// Loads the ReachFive **first-party** login form into this embedded webview and awaits the
    /// `AuthToken`. The flow completes on the SDK's custom scheme, intercepted by the webview.
    ///
    /// **Only flows that never leave the app are supported by this path.**
    public func loadLoginWebview(reachfive: ReachFive, state: String? = nil, nonce: String? = nil, scope: [String]? = nil, origin: String? = nil) async throws -> AuthToken {
        let pkce = Pkce.generate()
        self.reachfive = reachfive
        self.pkce = pkce
        self.reachfive?.storage.save(key: reachfive.pkceKey, value: pkce)

        let rect = CGRect(origin: .zero, size: frame.size)
        let webView = WKWebView(frame: rect, configuration: WKWebViewConfiguration())
        self.webView = webView
        webView.navigationDelegate = self
        addSubview(webView)
        webView.load(URLRequest(url: reachfive.buildAuthorizeURL(pkce: pkce, state: state, nonce: nonce, scope: scope, origin: origin)))
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
    }
}

extension LoginWKWebview: WKNavigationDelegate {
    public func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard let reachfive,
              let pkce,
              let continuation,
              let url = navigationAction.request.url,
              // Both sides folded. `URL.scheme` comes back with the case the redirect_uri was registered
              // with, so comparing it raw to an already-lowercased scheme never matched once the custom
              // scheme held an uppercase letter — the default case, since it derives from the clientId.
              url.normalizedScheme == reachfive.sdkConfig.customScheme.lowercased()
        else {
            return .allow
        }

        continuation.resume {
            try await reachfive.authWithCode(code: url.authorizationCode(), pkce: pkce)
        }
        self.continuation = nil
        return .cancel
    }
}
