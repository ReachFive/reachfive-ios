import UIKit
import Foundation
import IdentitySdkCore
import BrightFutures

class LoginWKWebviewController: UIViewController {
    
    @IBOutlet var loginWebview: LoginWKWebview!
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        let promise = Promise<AuthToken, ReachFiveError>()
        loginWebview.loadLoginWebview(reachfive: AppDelegate.reachfive(), promise: promise, origin: "LoginWKWebviewController.viewWillAppear")
        promise.future
            .onSuccess(callback: goToProfile)
            .onFailure { error in
                let alert = AppDelegate.createAlert(title: "Login failed", message: "Error: \(error.message())")
                self.present(alert, animated: true)
            }
    }
}
