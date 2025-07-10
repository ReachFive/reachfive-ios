import UIKit
@preconcurrency import WebKit
import Alamofire

public class LoginWKWebview: UIView {
    var webView: WKWebView?
    var reachfive: ReachFive?
    var continuation: CheckedContinuation<AuthToken, Error>?
    var pkce: Pkce?

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    public func loadLoginWebview(reachfive: ReachFive, state: String? = nil, nonce: String? = nil, scope: [String]? = nil, origin: String? = nil) async throws -> AuthToken {
        let pkce = Pkce.generate()
        self.reachfive = reachfive
        self.pkce = pkce

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
              url.scheme == reachfive.sdkConfig.baseScheme.lowercased()
        else {
            return .allow
        }

        let params = URLComponents(url: url, resolvingAgainstBaseURL: true)?.queryItems
        if let params, let code = params.first(where: { $0.name == "code" })?.value {
            await continuation.resume {
                try await reachfive.authWithCode(code: code, pkce: pkce)
            }
        } else {
            continuation.resume(throwing: ReachFiveError.TechnicalError(reason: "No authorization code", apiError: ApiError(fromQueryParams: params)))
        }
        self.continuation = nil
        return .cancel
    }
}
