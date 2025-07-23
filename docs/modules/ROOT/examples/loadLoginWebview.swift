import UIKit
import Foundation
import Reach5

class LoginWKWebviewController: UIViewController {

    @IBOutlet var loginWebview: LoginWKWebview!

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        Task {
            do {
                let authToken = try await loginWebview.loadLoginWebview(reachfive: AppDelegate.reachfive())
                goToProfile(authToken)
            } catch {
                let alert = AppDelegate.createAlert(title: "Login failed", message: "Error: \(error.localizedDescription)")
                self.present(alert, animated: true)
            }
        }
    }
}
