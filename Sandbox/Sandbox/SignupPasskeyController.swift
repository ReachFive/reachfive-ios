import UIKit
import Reach5

class SignupPasskeyController: UIViewController {
    @IBOutlet weak var usernameInput: UITextField!
    @IBOutlet weak var nameInput: UITextField!
    
    @IBAction func signup(_ sender: Any) {
        guard let username = usernameInput.text, !username.isEmpty else {
            let alert = AppDelegate.createAlert(title: "Signup with Passkey", message: "Please provide a username")
            present(alert, animated: true)
            return
        }
        let profile: ProfilePasskeySignupRequest
        if (username.contains("@")) {
            profile = ProfilePasskeySignupRequest(
                email: username,
                name: nameInput.text
            )
        } else {
            profile = ProfilePasskeySignupRequest(
                phoneNumber: username,
                name: nameInput.text
            )
        }
        
        if #available(iOS 16.0, *) {
            let window: UIWindow = view.window!
            AppDelegate.reachfive().signup(withRequest: PasskeySignupRequest(passkeyProfile: profile, friendlyName: username, anchor: window, origin: "SignupPasskeyController.signup"))
                .onSuccess(callback: goToProfile)
                .onFailure { error in
                    switch (error) {
                    case .AuthCanceled: return
                    default:
                        let alert = AppDelegate.createAlert(title: "Signup with Passkey", message: "Error: \(error.message())")
                        self.present(alert, animated: true)
                    }
                }
        } else {
            let alert = AppDelegate.createAlert(title: "Signup with Passkey", message: "Passkey requires iOS 16")
            present(alert, animated: true)
        }
    }
}
