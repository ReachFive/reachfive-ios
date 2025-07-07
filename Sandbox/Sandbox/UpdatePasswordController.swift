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
                try await AppDelegate.reachfive()
                    .getProfile(authToken: authToken)
                    .onSuccess { profile in
                        DispatchQueue.main.async {
                            self.username.text = ProfileController.username(profile: profile)
                        }
                    }
            }

            super.viewWillAppear(animated)
        }
    }

    @IBAction func update(_ sender: Any) {
        Task { @MainActor in
            if let authToken {
                try await AppDelegate.reachfive()
                    .updatePassword(.FreshAccessTokenParams(authToken: authToken, password: newPassword.text ?? ""))
                    .onSuccess {
                        let alert = AppDelegate.createAlert(title: "Update Password", message: "Success")
                        self.present(alert, animated: true)
                    }
                    .onFailure { error in
                        let alert = AppDelegate.createAlert(title: "Update Password", message: "Error: \(error.message())")
                        self.present(alert, animated: true)
                    }
            }
        }
    }
}
