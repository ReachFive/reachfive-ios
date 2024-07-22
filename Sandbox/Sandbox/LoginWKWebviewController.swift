import UIKit
import Foundation
import Reach5
import BrightFutures

class LoginWKWebviewController: UIViewController {
    
    @IBOutlet var loginWebview: LoginWKWebview!
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        loginWebview.loadLoginWebview(reachfive: AppDelegate.reachfive(), origin: "LoginWKWebviewController.viewWillAppear")
            .onSuccess(callback: goToProfile)
            .onFailure { error in
                let alert = AppDelegate.createAlert(title: "Login failed", message: "Error: \(error.message())")
                self.present(alert, animated: true)
            }
    }
}
