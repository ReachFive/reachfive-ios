import UIKit
import Foundation
import IdentitySdkCore

class UpdatePasswordController: UIViewController {
    var authToken: AuthToken?
    @IBOutlet weak var newPassword: UITextField!
    @IBOutlet weak var username: UITextField!
    
    override func viewWillAppear(_ animated: Bool) {
        if let authToken = AppDelegate.storage.getToken() {
            AppDelegate.reachfive()
                .getProfile(authToken: authToken)
                .onSuccess { profile in
                    DispatchQueue.main.async {
                        self.username.text = ProfileController.username(profile: profile)
                    }
                }
        }
        
        super.viewWillAppear(animated)
    }
    
    @IBAction func update(_ sender: Any) {
        if let authToken {
            AppDelegate.reachfive()
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
