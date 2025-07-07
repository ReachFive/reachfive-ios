import UIKit
import Foundation
import Reach5


class LoginWKWebviewController: UIViewController {

    @IBOutlet var loginWebview: LoginWKWebview!

    override func viewWillAppear(_ animated: Bool) {
        Task { @MainActor in
            super.viewWillAppear(animated)
            try await loginWebview.loadLoginWebview(reachfive: AppDelegate.reachfive(), origin: "LoginWKWebviewController.viewWillAppear")
                .onSuccess(callback: goToProfile)
                .onFailure { error in
                    let alert = AppDelegate.createAlert(title: "Login failed", message: "Error: \(error.localizedDescription)")
                    self.present(alert, animated: true)
                }
        }
    }
}
