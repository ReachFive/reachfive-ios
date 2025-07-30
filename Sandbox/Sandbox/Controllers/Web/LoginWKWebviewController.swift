import UIKit
import Foundation
import Reach5

class LoginWKWebviewController: UIViewController {

    @IBOutlet var loginWebview: LoginWKWebview!

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        Task {
            await handleAuthToken {
                try await loginWebview.loadLoginWebview(reachfive: AppDelegate.reachfive(), origin: "LoginWKWebviewController.viewWillAppear")
            }
        }
    }
}
