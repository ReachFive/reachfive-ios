import UIKit
import WebKit
import SafariServices
import Reach5
import Alamofire

class LoginCustomWebviewController: UIViewController {
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        let pkce = Pkce.generate()
        let reachfive = AppDelegate.reachfive()
        AppDelegate.storage.save(key: reachfive.pkceKey, value: pkce)
        let webView = WKWebView(frame: view.frame, configuration: WKWebViewConfiguration())
        webView.navigationDelegate = self
        view = webView
        webView.load(URLRequest(url: reachfive.buildAuthorizeURL(pkce: pkce, origin: "LoginCustomWebviewController.viewWillAppear")))
    }
}

extension LoginCustomWebviewController: WKNavigationDelegate {
    public func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> ()) {
        let app: UIApplication = UIApplication.shared
        // not sure why the callback has a scheme in lowercase
        let reachfive = AppDelegate.reachfive()
        guard let url = navigationAction.request.url, url.scheme == reachfive.sdkConfig.baseScheme.lowercased(), app.canOpenURL(url) else {
            decisionHandler(.allow)
            return
        }
        
        decisionHandler(.cancel)
        
        let useScheme = true
        // two choices
        // 1. Let the SDK read the callback URL by opening the app with the URL Scheme and listening to the passwordless callback
        if (useScheme) {
            app.open(url)
            
            // create a one-time notification by removing the observer from within the observation block
            let center = NotificationCenter.default
            var token: NSObjectProtocol?
            token = center.addObserver(forName: .DidReceiveLoginCallback, object: nil, queue: nil) { (note) in
                center.removeObserver(token!)
                if let result = note.userInfo?["result"], let result = result as? Result<AuthToken, ReachFiveError> {
                    self.handleResult(result: result)
                }
            }
        } else {
            // 2. read the code yourself and call authWithCode
            let pkce: Pkce? = AppDelegate.storage.take(key: reachfive.pkceKey)
            guard let pkce else {
                print("Pkce not found")
                return
            }
            let params = URLComponents(url: url, resolvingAgainstBaseURL: true)?.queryItems
            if let code = params?.first(where: { $0.name == "code" })?.value {
                reachfive.authWithCode(code: code, pkce: pkce).onComplete { self.handleResult(result: $0) }
            }
        }
    }
}

extension LoginCustomWebviewController {
    // same as login with providers
    // used because when we do onFailure, we get a Swift.Error instead of a ReachFiveError
    func handleResult(result: Result<AuthToken, ReachFiveError>) {
        switch result {
        case .success(let authToken):
            goToProfile(authToken)
        case .failure(let error):
            let alert = AppDelegate.createAlert(title: "Login failed", message: "Error: \(error.message())")
            present(alert, animated: true)
        }
    }
}
