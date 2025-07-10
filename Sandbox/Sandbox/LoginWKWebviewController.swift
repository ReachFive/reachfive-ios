import UIKit
import Foundation
import Reach5

class LoginWKWebviewController: UIViewController {

    @IBOutlet var loginWebview: LoginWKWebview!

    override func viewWillAppear(_ animated: Bool) {
        Task { @MainActor in
            super.viewWillAppear(animated)
            await handleAuthToken {
                try await loginWebview.loadLoginWebview(reachfive: AppDelegate.reachfive(), origin: "LoginWKWebviewController.viewWillAppear")
            }
        }
    }
}
