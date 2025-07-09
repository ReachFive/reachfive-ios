import UIKit
import Foundation
import Reach5

class UpdatePasswordController: UIViewController {
    var authToken: AuthToken?
    @IBOutlet weak var newPassword: UITextField!
    @IBOutlet weak var username: UITextField!

    override func viewWillAppear(_ animated: Bool) {
        Task { @MainActor in
            authToken = AppDelegate.storage.getToken()
            if let authToken {
                let profile = try await AppDelegate.reachfive().getProfile(authToken: authToken)
                self.username.text = ProfileController.username(profile: profile)
            }

            super.viewWillAppear(animated)
        }
    }

    @IBAction func update(_ sender: Any) {
        Task { @MainActor in
            if let authToken {
                do {
                    try await AppDelegate.withFreshToken(potentiallyStale: authToken) { refreshableToken in
                        try await AppDelegate.reachfive().updatePassword(.FreshAccessTokenParams(authToken: refreshableToken, password: newPassword.text ?? ""))
                    }
                    self.presentAlert(title: "Update Password", message: "Success")
                } catch {
                    self.presentErrorAlert(title: "Update Password", error)
                }
            }
        }
    }
}
